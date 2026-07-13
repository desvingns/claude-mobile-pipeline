#!/usr/bin/env python3
"""Deterministic cmp eval runner and low-feedback candidate ingester."""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_jsonl(paths: Iterable[Path]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for path in paths:
        with path.open("r", encoding="utf-8") as handle:
            for number, raw in enumerate(handle, 1):
                line = raw.strip()
                if not line:
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(f"{path}:{number}: invalid JSON: {error.msg}") from error
                if not isinstance(value, dict):
                    raise ValueError(f"{path}:{number}: event must be a JSON object")
                events.append(value)
    return events


def feedback_score(event: dict[str, Any]) -> int | None:
    direct = event.get("feedback_score")
    if isinstance(direct, int):
        return direct
    metric = event.get("metric", "")
    if isinstance(metric, str):
        match = re.search(r"(?:^|;)\s*score=([1-5])(?:\s*;|$)", metric)
        if match:
            return int(match.group(1))
    return None


def telemetry_summary(events: list[dict[str, Any]]) -> dict[str, Any]:
    verdicts = {"pass": 0, "fail": 0, "partial": 0}
    totals = {
        "tokens_in": 0,
        "tokens_out": 0,
        "tokens_cached": 0,
        "tokens_reasoning": 0,
        "cost_usd": 0.0,
        "duration_ms": 0,
    }
    structured = correlated = low_feedback = 0
    usage_sources = {"provider": 0, "estimated": 0, "unspecified": 0}
    optional = {
        "tokens_cached",
        "tokens_reasoning",
        "cost_usd",
        "duration_ms",
        "correlation_id",
    }
    for event in events:
        verdict = event.get("verdict")
        if verdict in verdicts:
            verdicts[verdict] += 1
        for field in totals:
            value = event.get(field)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                totals[field] += value
        if any(field in event for field in optional):
            structured += 1
        if isinstance(event.get("correlation_id"), str) and event["correlation_id"]:
            correlated += 1
        source = event.get("usage_source")
        if source in {"provider", "estimated"}:
            usage_sources[source] += 1
        else:
            usage_sources["unspecified"] += 1
        score = feedback_score(event)
        if score is not None and score <= 3:
            low_feedback += 1
    totals["cost_usd"] = round(float(totals["cost_usd"]), 8)
    return {
        "events": len(events),
        "legacy_events": len(events) - structured,
        "structured_events": structured,
        "correlated_events": correlated,
        "low_feedback_events": low_feedback,
        "usage_sources": usage_sources,
        "verdicts": verdicts,
        "totals": totals,
    }


def compare_subset(actual: Any, expected: Any, path: str = "$") -> list[str]:
    failures: list[str] = []
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f"{path}: expected object, got {type(actual).__name__}"]
        for key, value in expected.items():
            if key not in actual:
                failures.append(f"{path}.{key}: missing")
            else:
                failures.extend(compare_subset(actual[key], value, f"{path}.{key}"))
        return failures
    if actual != expected:
        failures.append(f"{path}: expected {expected!r}, got {actual!r}")
    return failures


def run_case(case_path: Path) -> dict[str, Any]:
    case = read_json(case_path)
    if not isinstance(case, dict):
        raise ValueError(f"{case_path}: case must be an object")
    case_id = case.get("id")
    kind = case.get("kind")
    fixture_value = case.get("fixture")
    expected = case.get("expected")
    if not isinstance(case_id, str) or not case_id:
        raise ValueError(f"{case_path}: non-empty id is required")
    if kind not in {"telemetry_summary", "json_subset"}:
        raise ValueError(f"{case_path}: unsupported kind {kind!r}")
    if not isinstance(fixture_value, str) or not isinstance(expected, dict):
        raise ValueError(f"{case_path}: fixture and expected object are required")
    fixture = (case_path.parent / fixture_value).resolve()
    if kind == "telemetry_summary":
        actual = telemetry_summary(read_jsonl([fixture]))
    else:
        actual = read_json(fixture)
    failures = compare_subset(actual, expected)
    return {
        "id": case_id,
        "pass": not failures,
        "failures": failures,
        "actual": actual,
    }


def command_run(args: argparse.Namespace) -> int:
    cases_dir = Path(args.cases).resolve()
    if args.case:
        case_paths = [Path(value).resolve() for value in args.case]
    else:
        case_paths = sorted(cases_dir.glob("*.json"))
    if not case_paths:
        print(json.dumps({"ok": False, "error": "no eval cases found"}, separators=(",", ":")))
        return 2
    results: list[dict[str, Any]] = []
    errors: list[str] = []
    for case_path in case_paths:
        try:
            results.append(run_case(case_path))
        except (OSError, ValueError, json.JSONDecodeError) as error:
            errors.append(str(error))
    passed = sum(1 for result in results if result["pass"])
    failed = len(results) - passed + len(errors)
    baseline_path = Path(args.baseline).resolve() if args.baseline else None
    baseline_failures: list[str] = []
    if baseline_path and baseline_path.exists():
        baseline = read_json(baseline_path)
        expected_ids = baseline.get("case_ids", [])
        actual_ids = [result["id"] for result in results]
        missing = [case_id for case_id in expected_ids if case_id not in actual_ids]
        if missing:
            baseline_failures.append(f"baseline cases missing: {', '.join(missing)}")
        minimum = baseline.get("minimum_pass_rate", 1.0)
        rate = passed / len(results) if results else 0.0
        if rate < minimum:
            baseline_failures.append(f"pass rate {rate:.3f} below baseline {minimum:.3f}")
    failed += len(baseline_failures)
    summary = {
        "ok": failed == 0,
        "cases": len(results),
        "passed": passed,
        "failed": failed,
        "results": results,
        "errors": errors + baseline_failures,
    }
    print(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))
    return 0 if summary["ok"] else 1


def event_fingerprint(event: dict[str, Any]) -> str:
    stable = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(stable.encode("utf-8")).hexdigest()[:12]


def candidate_from_event(event: dict[str, Any]) -> dict[str, Any]:
    score = feedback_score(event)
    assert score is not None
    fingerprint = event_fingerprint(event)
    ts = str(event.get("ts", "unknown"))
    date = re.sub(r"[^0-9]", "", ts)[:12] or "undated"
    return {
        "id": f"feedback-{date}-{fingerprint}",
        "status": "needs-human-rubric",
        "kind": "low_feedback_candidate",
        "source": {
            "project": event.get("project", ""),
            "ts": event.get("ts", ""),
            "agent": event.get("agent", "feedback"),
            "correlation_id": event.get("correlation_id", ""),
            "score": score,
            "note": event.get("note", ""),
            "event_fingerprint": fingerprint,
        },
        "expected": {
            "minimum_feedback_score": 4,
            "human_rubric_required": True,
            "instruction": "Attach the correlated SPEC/output and define evidence-backed acceptance before promoting to eval/cases.",
        },
    }


def expand_run_paths(patterns: list[str]) -> list[Path]:
    paths: list[Path] = []
    seen: set[Path] = set()
    for pattern in patterns:
        matches = [Path(value) for value in glob.glob(pattern)]
        if not matches and Path(pattern).is_file():
            matches = [Path(pattern)]
        for path in matches:
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                paths.append(resolved)
    return sorted(paths)


def command_ingest(args: argparse.Namespace) -> int:
    paths = expand_run_paths(args.runs)
    if not paths:
        print(json.dumps({"ok": False, "error": "no telemetry logs matched"}, separators=(",", ":")))
        return 2
    try:
        events = read_jsonl(paths)
    except (OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False, separators=(",", ":")))
        return 2
    candidates = [
        candidate_from_event(event)
        for event in events
        if event.get("agent") == "feedback"
        and feedback_score(event) is not None
        and feedback_score(event) <= 3
    ]
    out_dir = Path(args.out).resolve()
    created = skipped = 0
    files: list[str] = []
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
    for candidate in candidates:
        path = out_dir / f"{candidate['id']}.json"
        files.append(str(path))
        if args.dry_run:
            continue
        try:
            with path.open("x", encoding="utf-8", newline="\n") as handle:
                json.dump(candidate, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            created += 1
        except FileExistsError:
            skipped += 1
    summary = {
        "ok": True,
        "matched_events": len(candidates),
        "created": created,
        "skipped_existing": skipped,
        "dry_run": args.dry_run,
        "files": files,
    }
    print(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run", help="run deterministic eval cases")
    run.add_argument("--cases", default=str(Path(__file__).parent / "cases"))
    run.add_argument("--case", action="append", default=[])
    run.add_argument("--baseline", default=str(Path(__file__).parent / "baseline.json"))
    run.set_defaults(func=command_run)
    ingest = subparsers.add_parser("ingest-low-feedback", help="stage low-feedback eval candidates")
    ingest.add_argument("--runs", action="append", required=True, help="JSONL file or glob; repeatable")
    ingest.add_argument("--out", default=str(Path(__file__).parent / "candidates"))
    ingest.add_argument("--dry-run", action="store_true")
    ingest.set_defaults(func=command_ingest)
    return result


def main() -> int:
    args = parser().parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
