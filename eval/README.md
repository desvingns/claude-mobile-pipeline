# eval/ — deterministic regression rail

The first executable eval layer covers contracts that do not require a live LLM: telemetry
backward compatibility, structured usage aggregation, low-feedback candidate shape, renderer
properties, sync cursors, and proposal lifecycle. It gives CI a real baseline now; real shipped
feature/clone cases can be promoted as evidence accumulates.

## Run

```bash
bash eval/runner.sh
```

`runner.py` discovers `eval/cases/*.json`, evaluates their fixture deterministically, checks
`baseline.json`, emits one JSON summary, and exits non-zero on any regression. Case kinds:

- `telemetry_summary` — summarize a JSONL event fixture and compare an expected subset;
- `json_subset` — compare an expected JSON subtree.

## Turn low feedback into candidates

```bash
bash eval/ingest-low-feedback.sh \
  --runs 'path/to/project/selfimprove/runs/*.jsonl' \
  --out eval/candidates
```

Every feedback event with score ≤3 becomes a content-addressed, idempotent candidate. A candidate
is deliberately `needs-human-rubric`: attach the correlated SPEC/output and define acceptance before
moving it into `eval/cases/`. Re-running the importer skips the same event instead of duplicating it.

`eval/clone-fit/` remains the higher-cost device/vision suite. Its documented fixture should be
automated once the reference APK and throwaway AVD are available in a safe test environment.
