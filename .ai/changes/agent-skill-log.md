# Agent / skill change-log

Append-only. Newest at the bottom. Format + semantics: see [README.md](README.md).
`sync-state.json` is the authoritative consumed-cursor; do not infer it from this file.

---

## 2026-05-25T00:00-baseline
type: add
target: .ai/
summary: established the dual-tool coordination layer — .ai/ workspace, canonical AGENTS.md, thin CLAUDE.md, and the Codex action-plan brief
reason: make cmp drivable by both Claude Code and Codex CLI (see .ai/tasks/codex-001-dual-tool.md)
affects:
by: claude

## 2026-05-28T12:00-instrumented-runner
type: add
target: templates/android/agents/{{PREFIX}}-runner-instrumented-android.md
summary: new Android agent that runs ONE connectedDebugAndroidTest class on a connected device and returns parsed pass/fail JSON (device suite, not JVM)
reason: the existing runner is JVM-only; on-device Compose-UI coverage had no runner
affects: claude, codex
by: claude

## 2026-05-28T12:01-device-workflow
type: add
target: templates/common/commands/{{PREFIX}}.md
summary: new --device <screen|scope> workflow (Android) — mandatory device-connection gate (ask user + record to memo if missing/lost), write ONE instrumented test, run via the instrumented runner; plus two Rules bullets
reason: give a less-capable model an on-rails one-test-at-a-time on-device loop
affects: claude, codex
by: claude

## 2026-05-28T12:02-device-connection-memo
type: add
target: templates/android/memory/device-connection.md.tmpl
summary: new memory template recording the verified device/emulator connection; holds the mandatory/ask/update-if-lost rule
reason: stop re-asking how the test device is connected; make a connected device a hard precondition
affects: claude, codex
by: claude

## 2026-05-28T12:03-device-seam-policy
type: update
target: templates/android/agents/{{PREFIX}}-tester-android.md, templates/android/agents/{{PREFIX}}-developer-android.md, templates/common/agents/{{PREFIX}}-reviewer-base.md
summary: device-test seam policy — tester gets an instrumented-compose-ui test type; developer may add only testTag/contentDescription/public seams; reviewer Check 7 blocks behaviour beyond a declared seam
reason: prevent a weaker model from inventing UI/events under the guise of a test seam
affects: claude, codex
by: claude

## 2026-05-29T10:00-spec-group
type: add
target: templates/spec/ (skills/app-spec-creator/ + agents/*.md ×17 + prompts/)
summary: ported the requirements→design→handoff half — the app-spec-creator skill, 17 spec/analyzer agents, and the harness-agnostic prompt library (EARS/Gherkin/NFR/a11y/security/analytics/evaluator rubrics, design+platform templates, feature-inventory schema). Prompt paths neutralized to {{AGENT_DIR}}; SKILL.md gets a tool:claude|codex harness-notes block (AskUserQuestion vs STOP gates; native-subagent dispatch).
reason: cmp covered only the dev half; bring in the spec-creation half so the pipeline spans requirements→implementation. See .ai/tasks/claude-002-spec-integration.md.
affects: claude, codex
by: claude

## 2026-05-29T10:01-spec-codex-adapters
type: add
target: templates/spec/codex/ (agent.toml.tmpl, skills/app-spec-creator/agents/openai.yaml, config-fragment.toml)
summary: Codex form of the spec tool — a thin .toml subagent-shim template (re-reads the canonical .md, maps Claude tool names, returns the same JSON, no descendants), the skill openai.yaml interface, and an [agents] config fragment (max_threads=6 >= widest fan-out, max_depth=1).
reason: dual-harness — Codex natively supports SKILL.md + .toml subagents; mirror MyMoney's proven .codex pattern.
affects: codex
by: claude

## 2026-05-29T10:02-install-spec
type: add
target: install-spec.sh (repo root)
summary: standalone global installer — renders {{AGENT_DIR}} to a portable ~/.claude or ~/.codex, strips off-tool blocks, copies the Claude form + generates the 17 Codex shims + merges [agents] config. --harness claude|codex|both, --dry-run, --force. Smoke-tested into a throwaway home (no {{}} / tool: leaks).
reason: the spec tool is GLOBAL (fixed names), not per-project — installs once. NOTE for codex-001: later lib/sync.sh or a bootstrap --install-spec mode may absorb this; install-spec.sh does NOT touch bootstrap.sh/lib/ (codex-owned), and the spec group already ships both forms so it works before sync.sh exists.
affects: claude, codex
by: claude

## 2026-05-29T22:00-selfimprove-loop
type: add
target: selfimprove/ (record-run.sh, reflect.sh, REFLECTION-PROMPT.md, lessons.md, README.md, runs/.gitkeep) + .claude/agents/selfimprove-retro.md
summary: self-improvement loop kit — L1 capture (record-run.sh → runs/*.jsonl, gitignored), L2 reflect (reflect.sh → retro/*.md, awk-only), L3 propose (REFLECTION-PROMPT.md + selfimprove-retro agent), human-gated into THIS change-log → lib/sync. Replicated as a uniform kit into MyMoney_app + diet_helper (app projects gate into their own lessons.md).
reason: close the observe→reflect→propose→gate loop on cmp's own primitives ("self-improvement is a loop, not a store"); it dogfoods the change-log rail it feeds. See .ai/memory/self-improvement-loop.md.
affects: claude, codex
by: claude

## 2026-05-30T12:00-spec-backlog-board
type: add
target: templates/common/commands/{{PREFIX}}.md, templates/common/specs/README.md, templates/common/specs/{backlog,active,done}/.gitkeep
summary: SPEC backlog board — large --feature epics that split into ≥2 SPECs are written as files under .claude/specs/{backlog,active,done}/ (a SPEC's status is the folder it lives in); --feature Phase 1 gains a split step, plus a "## SPEC backlog board" section + a Rules bullet; specs README rewritten to document layout/epic-naming/file-format/lifecycle while keeping the --discuss brainstorm-artifact format
reason: a feature too big for one SPEC was only ever printed to chat; persist + order + resume it as a file-based backlog/current/done board (user request)
affects: claude, codex
by: claude

## 2026-05-30T12:05-spec-backlog-bootstrap
type: update
target: bootstrap.sh
summary: copy_phase now also creates .claude/specs/{backlog,active,done}/ and copies their .gitkeep (so the SPEC backlog board ships to freshly bootstrapped projects, not just the README); dry-run output lists the board folders
reason: complete the spec-backlog-board feature for new projects (companion to 2026-05-30T12:00-spec-backlog-board); does NOT touch the codex-owned --tools/{{AGENT_DIR}}/adapter-emission seams
affects: claude, codex
by: claude

## 2026-05-30T12:10-spec-flag-and-consume
type: add
target: templates/common/commands/{{PREFIX}}.md, templates/common/specs/README.md
summary: --spec <desc> = author SPEC(s) ONLY → write straight to .claude/specs/backlog/ as Status:draft (no agents, no approval gate); --feature gains backlog-consume mode (--next / --backlog <slug>) that moves backlog→active and runs Phase 2 with the stored SPEC verbatim, SKIPPING Phase 0+1 (no re-create, no re-approve); Usage + Rules + specs-README lifecycle updated (draft status added)
reason: separate spec-authoring (fill the backlog) from implementation, and stop re-creating/re-approving a SPEC that was already approved when it entered the backlog (user request)
affects: claude, codex
by: claude

## 2026-05-31T10:00-marketplace-spec
type: add
target: lib/build-marketplace.sh, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json
summary: cmp is now a multi-harness plugin marketplace (mobile-pipeline); new generator emits claude-plugins/mp-spec (skill /mp-spec + 17 sub-agents) and codex-plugins/mp-spec (skill only) from templates/spec
reason: reuse one updatable source across projects (diet_helper, MyMoney_app, future) instead of copy-per-project; modelled on the ai-team-bootstrap marketplace pattern (user request)
affects:
by: claude

## 2026-05-31T10:05-marketplace-dev
type: add
target: lib/build-marketplace.sh, claude-plugins/mp-dev/
summary: emit the dev pipeline as the Claude-only mp-dev plugin (/mp orchestrator + specialist agents + deterministic scripts), de-specialized — agent bodies read .claude/mp/config.json + CLAUDE.md + .claude/mp/extras/*.md at runtime; scripts resolve via ${CLAUDE_PLUGIN_ROOT}
reason: share the dev pipeline across projects without baking package/prefix per copy; honour the codex-001 ownership boundary by generating (not editing) bootstrap.sh / templates scripts
affects:
by: claude

## 2026-05-31T10:10-projects-wired
type: update
target: diet_helper/.claude, MyMoney_app/.claude, MyMoney/.claude (downstream — outside this repo)
summary: wired three projects to the mobile-pipeline marketplace via .claude/settings.json (extraKnownMarketplaces + enabledPlugins). MyMoney staging → mp-spec; MyMoney_app + diet_helper → mp-spec + mp-dev, each with .claude/mp/config.json + .claude/mp/extras/. MyMoney_app .codex max_threads 4→6. Old local cmp-*/dh-* agents left in place (file-safety) — listed for manual removal.
reason: deliver the cross-project reuse the marketplace exists for; additive + reversible (no deletions)
affects:
by: claude

## 2026-05-31T14:00-fold-and-improve
type: add
target: templates/common/agents/{{PREFIX}}-{intake,knowledge,planner,improve}.md, templates/common/scripts/{{PREFIX}}-propose-improvement.sh, templates/common/commands/{{PREFIX}}.md
summary: folded intake (SPEC synth), knowledge (post-ship lesson routing), planner (generic /mp-spec bundle to .claude/specs/backlog bridge), and improve (plugin-level fix drafter) into canonical mp-dev; added orchestrator --plan + --improve workflows + a post-ship Knowledge step + Rules. New propose-improvement.sh opens a gated PR against mobile-pipeline. build-marketplace.sh now also emits common agents + common scripts.
reason: bring diet_helper intake/knowledge + MyMoney planner into the shared canon (user request) and implement the downstream to mobile-pipeline self-improvement PR loop
affects:
by: claude

## 2026-05-31T14:05-diet-helper-archive
type: remove
target: diet_helper/.claude (downstream — outside this repo)
summary: archived diet_helper generic dh-* agents + dh.md + dh-runner/reviewer.sh + PowerShell build/test + folded dh-intake/dh-knowledge into .claude/_archive_pre_mp/ (MOVED not deleted). diet_helper now uses /mp; only selfimprove-retro.md stays local. MyMoney_app left intact (bespoke --phase/--check workflow).
reason: clean up superseded local copies now the mp-dev plugin provides them (user granted cleanup rights); reversible
affects:
by: claude

## 2026-05-31T16:00-improve-batch-reflect-ci
type: add
target: templates/common/scripts/{{PREFIX}}-{improve-drain,cross-reflect}.sh, templates/common/agents/{{PREFIX}}-reflect.md, templates/common/commands/{{PREFIX}}.md, .github/workflows/validate-plugins.yml
summary: improvement loop gains batch + cross-project + CI. --improve splits into direct (own PR) vs --drain (batch all queued proposals into one PR); mp-knowledge/mp-reflect now STAGE to the .ai/proposals/ queue. New --reflect aggregates lessons across projects (cross-reflect.sh + mp-reflect agent, projects from ~/.config/mobile-pipeline/projects.txt) and queues >=2-project patterns. New GitHub Actions CI gate: JSON validity + bash -n + leak check + regeneration-drift. gh installed for auto-PR.
reason: user-requested batch/cross-project/CI on the self-improvement workflow; reduce PR noise, catch systemic patterns, and protect the one-source discipline
affects:
by: claude

## 2026-05-31T17:00-mp-spec-plugin-paths
type: fix
target: lib/build-marketplace.sh, claude-plugins/mp-spec/, codex-plugins/mp-spec/
summary: marketplace mp-spec output now rewrites legacy app-spec-creator names to mp-spec and points Claude sub-agents at ${CLAUDE_PLUGIN_ROOT}/skills/mp-spec/prompts instead of the old global ~/.claude skill path
reason: avoid broken prompt reads after removing the old app-spec-creator global install; keep generated plugin trees cleanly named as mp-spec while preserving the canonical/global install source
affects:
by: codex

## 2026-06-01T09:00-codex-model-tiering
type: update
target: install-spec.sh, templates/spec/codex/agent.toml.tmpl, templates/spec/skills/app-spec-creator/SKILL.md, templates/common/agents/{{PREFIX}}-maintainer.md, templates/common/commands/{{PREFIX}}.md, docs/SPEC-PIPELINE.md, docs/MARKETPLACE.md, CHANGELOG.md
summary: Codex spec-agent install now emits explicit model and model_reasoning_effort tiers; mp-dev templates/docs define the future Codex dev-agent tier contract
reason: avoid every Codex subagent inheriting the parent session's expensive frontier model and reasoning effort
affects: codex
by: codex

## 2026-06-01T18:00-fidelity-loop
type: add
target: templates/android/agents/{{PREFIX}}-fidelity-android.md, templates/common/commands/{{PREFIX}}.md
summary: M1 clone-fidelity gate — new {{PREFIX}}-fidelity-android (multimodal opus, read-only) compares each built screen's screenshot against its reference image, scores per-screen fidelity, honours an intended-deviation ledger (spec/deviations.md), flags behavioural divergences as behavioural_unverified, and returns ready-to-file divergence SPECs; new orchestrator --fidelity workflow captures built screens (Roborazzi/screen-tour/adb), runs the comparator, prints the report, and writes divergence SPECs to .claude/specs/backlog/ behind a y/d/n gate; Usage line + Rules bullet added. Auto-emitted into claude-plugins/mp-dev by build-marketplace (android agents glob).
reason: M1 of the clone-loop closure — the pipeline captured business logic but never compared the built app to its reference, so clones drift (the 7 MyMoney↔Monefy divergences). This is the reference-comparison gate the user requested.
affects: claude, codex
by: claude

## 2026-06-01T18:10-fidelity-spec-inputs
type: add
target: templates/spec/agents/fidelity-checklist-author.md, templates/spec/skills/app-spec-creator/SKILL.md, install-spec.sh
summary: M2 spec-side fidelity inputs — new clone-only spec agent fidelity-checklist-author (opus, multimodal) writes spec/fidelity/<Sxx>.md (per-screen visual+behavioural must-match checklists), spec/fidelity/registry.csv (screen↔reference↔FR/AC), and a spec/deviations.md intended-deviation ledger; SKILL gains a Phase E clone fan-out for it, depth=reference default for clone, the bundle layout entries, and a handoff note about the --fidelity loop; install-spec.sh $AGENTS gains the new agent so the Codex shim is generated too. (Claude mp-spec auto-globs the agent.)
reason: give the M1 fidelity gate a precise, grounded contract per screen + a deviation ledger so intended departures aren't flagged — and default clones to full fidelity depth.
affects: claude, codex
by: claude

## 2026-06-01T18:20-phase-plan-model
type: add
target: templates/common/agents/{{PREFIX}}-phase-planner.md, templates/common/implementation_plan/*.tmpl, templates/common/commands/{{PREFIX}}.md, lib/build-marketplace.sh
summary: M3 generic phase-plan model — ported MyMoney cmp-planner-android into the generic {{PREFIX}}-phase-planner (read-only; design→PHASE_NN + PROGRESS/00_overview deltas; content-addressed slug+hash anchors; sentinel-gated merge; bootstrap/sync/phase modes) + 4 implementation_plan doc templates (README/00_overview/PROGRESS/PHASE_TEMPLATE) + orchestrator workflows --plan --phases / --phase / --check (Usage + sections + Rules). The phase-planner auto-emits a per-screen "Visual QA vs reference" task and (clone) appends a final Fidelity-gate phase. build-marketplace common-agent list gains phase-planner. Phases for clones/large builds; backlog board stays for ad-hoc.
reason: the heavy pofazovaya model that produced MyMoney lived only in MyMoney_app/.claude; bring it into the marketplace as a generic capability + wire reference-comparison as the explicit final phase (user request).
affects: claude
by: claude

## 2026-06-01T18:30-capture-depth
type: update
target: templates/spec/agents/screenshot-business-analyzer.md, templates/spec/skills/app-spec-creator/prompts/templates/design.tmpl.md, templates/spec/skills/app-spec-creator/SKILL.md
summary: M4 capture depth — business-analyzer now extracts a per-screen interactions[] map (gestures / entry order / partial-vs-full overlays) and state_gaps[] (states present in the app but not screenshotted); design.tmpl gains a per-screen "Поведение и жесты" section + an explicit per-state requirement; SKILL A-clone surfaces state_gaps in intake (capture the missing empty/loading/error states). Closes the behavioural/state class of divergence (swipe, entry order, empty state) that static single screenshots miss.
reason: the 7 MyMoney divergences included behavioural/state misses a single screenshot can't show; capture them up front so the fidelity gate (incl. its acceptance/feature arm) can check them.
affects: claude, codex
by: claude

## 2026-06-01T18:40-clone-hardening
type: add
target: templates/android/agents/{{PREFIX}}-tester-android.md, docs/CLONE-PLAYBOOK.md, eval/clone-fidelity/README.md, VERSION
summary: M5 hardening/DX/docs/eval — tester gains a Roborazzi golden-lock note (lock a screen as a CI golden once it passes --fidelity: the deterministic half of the hybrid strategy); new docs/CLONE-PLAYBOOK.md (end-to-end reference→spec→phases→build→fidelity→fix loop + definition-of-clone-done); new eval/clone-fidelity/README.md (MyMoney↔Monefy fixture: detection recall on the 7 known divergences, no intended-deviation false positives, non-increasing-divergence convergence guard); VERSION 1.4.0→1.5.0.
reason: make the clone loop teachable, regression-guarded, and CI-lockable; bump the marketplace version for the fidelity + phase-model feature set.
affects: claude, codex
by: claude

## 2026-06-02T10:00-rename-fidelity-flag-to-fit
type: update
target: claude-plugins/mp-dev/commands/mp.md, templates/common/commands/{{PREFIX}}.md, claude-plugins/mp-dev/agents/mp-fidelity-android.md, claude-plugins/mp-dev/agents/mp-phase-planner.md, claude-plugins/mp-dev/agents/mp-tester-android.md, claude-plugins/mp-spec/agents/fidelity-checklist-author.md, claude-plugins/mp-spec/skills/mp-spec/SKILL.md, codex-plugins/mp-spec/skills/mp-spec/SKILL.md, templates/spec/**, templates/android/agents/**, templates/common/agents/{{PREFIX}}-phase-planner.md, templates/common/implementation_plan/README.md.tmpl, docs/CLONE-PLAYBOOK.md, eval/clone-fidelity/README.md, README.md
summary: Renamed the orchestrator clone-gate FLAG from --fidelity to --fit across all command specs, agent docs, skill prose, templates, playbook and README. Only the literal flag token changed; the "fidelity" CONCEPT is untouched — agent names (mp-fidelity-android, fidelity-checklist-author), bundle paths (spec/fidelity/, build/fidelity/), epic slug (fidelity), fidelity_score, Fidelity-gate phase, and section titles all keep "fidelity". Historical log entries left verbatim (append-only).
reason: user request — shorter, friendlier flag name for the reference-comparison gate.
affects: claude, codex
by: claude

## 2026-06-02T12:30-visual-device-gate
type: update
target: templates/common/commands/{{PREFIX}}.md, templates/android/agents/{{PREFIX}}-runner-instrumented-android.md, templates/android/agents/{{PREFIX}}-runner-android.md, templates/android/agents/{{PREFIX}}-tester-android.md, templates/android/agents/{{PREFIX}}-verifier-android.md, claude-plugins/mp-dev/
summary: Added a hard Android visual autotest device pre-flight for explicitly visual /mp work; generated mp-dev copies now stop before implementation/test execution when required connected-device visual evidence is unavailable, and agents no longer allow JVM screenshots/manual checklist text to substitute for device visual tests.
reason: MyMoney visual work exposed that correct visual development cannot proceed when the required Pixel 5/device is not booted; make the generic pipeline stop early instead of developing or reporting visual tests blind.
affects: claude, codex
by: codex

## 2026-06-02T20:00-device-run-helper-extras-discovery
type: update
target: templates/android/agents/{{PREFIX}}-runner-instrumented-android.md, claude-plugins/mp-dev/agents/mp-runner-instrumented-android.md
summary: Broadened the instrumented runner's Step 2 "project-specific device-run helper" override to also discover the helper in the project's per-agent extras (not only CLAUDE.md), and explicitly sanctioned invoking a PowerShell host-AVD helper from the Bash tool (e.g. powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/<helper>.ps1 -TestClass '<FQN>') as the documented exception to the Bash-only default. Still parse the report, never the exit code.
reason: MyMoney clone migration — its on-device flow runs through scripts/run_connected_test_on_host_avd.ps1 because AGP 8.7.3 UTP rejects the host-AVD remote serial on this Windows host; the generic --device path forbade PowerShell and only looked in CLAUDE.md, so the per-project helper was not first-class.
affects: claude, codex
by: claude

## 2026-06-03T10:00-codex-mp-dev-bridge
type: add
target: templates/dev/codex/, codex-plugins/mp-dev/, lib/build-marketplace.sh, .agents/plugins/marketplace.json, templates/common/agents/{{PREFIX}}-maintainer.md, docs/MARKETPLACE.md, README.md
summary: Added the Codex mp-dev marketplace skill bridge, UI metadata, per-project agent-shim reference/template/config fragment, generator wiring, and marketplace entry; updated the dev-agent Codex tier policy from future guidance to the active shim contract.
reason: MyMoney hard-switch migration proved Codex needs the same mp-dev entrypoint as Claude while keeping project behavior synchronized through .claude/mp/extras/* and native .codex/agents/mp-*.toml shims.
affects: codex
by: codex

## 2026-06-03T14:00-reference-crawler-phase1
type: add
target: templates/spec/skills/app-spec-creator/scripts/crawl/{_crawl-lib,device-preflight,app-control,screencap,ui-dump,input}.sh, templates/spec/agents/crawl-executor.md, templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/skills/app-spec-creator/prompts/questions/clone.crawl-setup.md, install-spec.sh, lib/build-marketplace.sh
summary: Phase 1 of the dynamic reference-APK crawler for /mp-spec clone intake. New optional Phase A.0 installs the reference APK on a connected device and drives it vision-first (crawl-executor, opus) to build a state graph with screenshots, dedup states, and fill input/screenshots/ with an observed corpus. Five cross-platform device primitives under scripts/crawl/ (one JSON line each, mirror mp-runner-android.sh conventions, target $ANDROID_SERIAL, no install-path assumptions). SKILL gains --crawl/--no-crawl + Step 2.0 + the input/crawl/ bundle slot; clone.crawl-setup prompt handles device/consent. install-spec.sh AGENTS table gains crawl-executor (gpt-5.5/high) and both installers + build-marketplace now copy scripts/ into the skill. Additive — auto-skips to static A-clone when no device or the APK won't run.
reason: static clone intake produces a shallow spec (inferred gestures, uncaptured states, guessed nav edges); observing the running reference yields real states + transitions. Phase 1 de-risks the core assumption (can we reliably drive an arbitrary APK) before the navigator/executor/reviewer trio (Phase 2), autonomous seeding (Phase 3), and fidelity wiring (Phase 4).
affects: claude, codex
by: claude

## 2026-06-03T15:00-reference-crawler-device-fixes
type: fix
target: templates/spec/skills/app-spec-creator/scripts/crawl/{ui-dump,input,app-control}.sh, templates/spec/agents/crawl-executor.md
summary: Device-validated the crawl primitives on a real emulator (emulator-5554, Android 34) and fixed three bugs the offline tests could not catch. (1) ui-dump.sh: Git Bash (MSYS) mangled the on-device /sdcard path before it reached adb.exe — now export MSYS_NO_PATHCONV=1 and stream via `adb exec-out cat "$DEV_PATH" > "$OUT"` (a bash redirect, so the LOCAL dest is not an adb path arg). (2) input.sh resolve_center: --clickable was too strict for Compose (the visible label sits on a non-clickable node while the clickable is an anonymous View) — now PREFER a clickable match, else fall back to any text match, so tapping the label's centre hits the parent. (3) app-control.sh launch: now CONFIRMS the target reached the foreground (poll + one retry) and reports ok:false honestly instead of a false success. Also: ui-dump now exposes clickable/clickable_labeled counts and flags compose_degenerate when clickables carry no label; crawl-executor.md documents the Compose label pattern. End-to-end proven: tap --text "Chrome" resolved+tapped → foreground became Chrome.
reason: a real device smoke (the user asked why it wasn't run) exposed Windows/MSYS path conversion, the Compose uiautomator pattern, and unverified launches — exactly the class of bug `bash -n` and synthetic-dump unit tests miss.
affects: claude, codex
by: claude

## 2026-06-03T16:00-reference-crawler-phase2
type: add
target: templates/spec/agents/{crawl-navigator,crawl-reviewer,crawl-executor,navigation-flow-analyzer}.md, templates/spec/skills/app-spec-creator/SKILL.md, install-spec.sh
summary: Phase 2 of the reference-APK crawler — split the single-agent crawler into a separate-session trio. New crawl-navigator (sonnet, read-only) plans the next affordance to explore + its replay path and decides done; new crawl-reviewer (opus, multimodal, read-only) classifies each edge (flow|cycle|error|dead_end), judges the success_test, scores coverage_confidence, and gates accept vs continue; crawl-executor refactored from whole-crawl to goal-scoped (relaunch → replay path → one affordance → capture+dedup → return). SKILL Step 2.0 rewritten: the orchestrator owns a file-persisted loop navigator→(executor⇄reviewer, max 2 retries — mirrors the Phase F evaluator-optimizer)→merge→coverage, stopping on done/plateau(K=4)/budget(40/25/60). navigation-flow-analyzer now accepts the optional observed state-graph.json and converts its edges to source:observed/confidence:1.0 (mapping crawl ST* → business S* via the shared screenshot_file), inferring only uncovered transitions. install-spec.sh AGENTS table gains crawl-navigator (gpt-5.4/medium) + crawl-reviewer (gpt-5.5/high); plugins regenerated, 0 leaks.
reason: the colleague's core advice — never reuse one session for multiple roles; navigator/executor/reviewer with a confidence-gated loop yields better decisions, classified edges, and a coverage stop, and lets observed transitions replace navigation guesses.
affects: claude, codex
by: claude

## 2026-06-03T17:00-reference-crawler-phase3
type: add
target: templates/spec/agents/{crawl-navigator,crawl-executor,crawl-reviewer}.md, templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/skills/app-spec-creator/prompts/questions/clone.crawl-setup.md
summary: Phase 3 of the reference-APK crawler — autonomous data-seeding + auth so populated states are actually observed. crawl-navigator now emits auth goals (get past a sign-in/onboarding wall — unblock before breadth) and seed goals (create entries to reveal an empty state's populated form), in addition to explore. crawl-executor branches on goal.type: auth = fill the form (user-provided credentials if any, else synthetic) + submit + detect verification walls; seed = open the create flow and create `count` entries with synthetic data, then capture the filled list/dashboard. Added a deterministic ASCII synthetic-data fixture set (reproducible corpus) and strengthened guardrails (synthetic only; no real-money/send/share; SMS/email-OTP/captcha → blocker:needs_human, no retry). crawl-reviewer judges auth/seed success from the after-shot (authenticated landing / populated list) and treats needs_human blockers as accept-and-prune. clone.crawl-setup gains a Phase-3 consent (seed | explore-only | decline) + an optional TEST-credentials question; credentials are runtime-only and MUST NOT be written to any artifact. SKILL Step 2.0 collects consent/creds up front and passes credentials to the executor for auth goals. No new agents/scripts; plugins regenerated, 0 leaks.
reason: the static and explore-only paths only ever see empty UI; the user specifically wanted populated/filled states, which require getting past auth and creating data — done autonomously with synthetic fixtures and graceful needs_human degradation on walls the crawl cannot pass.
affects: claude, codex
by: claude

## 2026-06-03T18:00-reference-crawler-phase4
type: add
target: templates/spec/agents/fidelity-checklist-author.md, templates/spec/skills/app-spec-creator/SKILL.md, docs/CLONE-PLAYBOOK.md, docs/REFERENCE-CRAWLER.md
summary: Phase 4 of the reference-APK crawler — close the clone loop. fidelity-checklist-author now consumes the optional crawl_graph + crawl_states_dir: it grounds per-screen must-match checklists in the OBSERVED per-state frames (incl. the data_state:"filled" states seeding produced), writes a visual block per state when a screen was captured empty AND filled, and emits a registry.csv row per (screen, captured state) with a data_state column — so the build-time --fit gate drives the built app into each state and compares it against its own real reference frame. SKILL Step 7 passes the crawl inputs to the fidelity author when A.0-crawl ran. CLONE-PLAYBOOK gains a Step 0 (the dynamic crawl front-door) + updated loop diagram + the auto-state-capture note; new docs/REFERENCE-CRAWLER.md consolidates the subsystem (trio, scripts, artifacts, seam, gotchas, phasing). Auto-enable on --depth reference was already wired (Phase 1). No new agents/scripts; plugins regenerated, 0 leaks. Crawler now feature-complete across all 4 phases.
reason: the dynamic crawl's payoff is only realized when its observed empty+filled frames become the fidelity contract the --fit gate checks against — otherwise the build still drifts on the empty-state class of divergence. This anchors fidelity to states the reference actually showed.
affects: claude, codex
by: claude

## 2026-06-03T19:00-rename-fidelity-concept-to-fit
type: update
target: templates/spec/agents/fit-checklist-author.md (was fidelity-checklist-author.md), templates/android/agents/{{PREFIX}}-fit-android.md (was {{PREFIX}}-fidelity-android.md), templates/common/commands/{{PREFIX}}.md, templates/common/agents/{{PREFIX}}-{phase-planner,maintainer}.md, templates/common/implementation_plan/*.tmpl, templates/android/agents/{{PREFIX}}-tester-android.md, templates/spec/skills/app-spec-creator/SKILL.md, templates/dev/codex/skills/mp-dev/references/codex-agent-shims.md, install-spec.sh, docs/{CLONE-PLAYBOOK,REFERENCE-CRAWLER}.md, eval/clone-fit/ (was eval/clone-fidelity/), README.md
summary: Completed the fidelity→fit rename repo-wide (the 1.5.0 rename was deliberately flag-only). Renamed via git mv: agents fidelity-checklist-author→fit-checklist-author and {{PREFIX}}-fidelity-android→{{PREFIX}}-fit-android, dir eval/clone-fidelity→eval/clone-fit; and the concept tokens in content: spec/fidelity→spec/fit, build/fidelity→build/fit, fidelity_score→fit_score, Fidelity-gate→Fit-gate, === FIDELITY ===→=== FIT ===. install-spec AGENTS table row updated; plugins regenerated (generated mp-fidelity-android→mp-fit-android, fidelity-checklist-author→fit-checklist-author). Released CHANGELOG [1.5.0] history + this append-only log's prior entries intentionally keep "fidelity" verbatim.
reason: user requested the full concept rename to fit (the earlier flag-only rename left the codebase half-named); one deliberate pass keeps the vocabulary consistent.
affects: claude, codex
by: claude

## 2026-06-05T10:30-grill-me-design-tree
type: add
target: templates/spec/skills/app-spec-creator/prompts/techniques/grill-me.md, templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/skills/app-spec-creator/prompts/questions/greenfield.stage1-vision.md, templates/spec/skills/app-spec-creator/prompts/README.md, docs/SPEC-PIPELINE.md
summary: Ported the grill-me technique (design-tree interrogation — "walk down each branch", one adversarial question at a time, a recommended answer each, actively poking holes) into /mp-spec intake as a reusable orchestrator technique (NOT an agent; model n/a). New prompt prompts/techniques/grill-me.md encodes the rule (roots before branches), ask-one-at-a-time funnel, recommended-answer convention, hole-poking (assumptions/contradictions/unhandled states/scope creep), stop conditions/budgets, and a decisions-ledger output. Greenfield gets a mandatory Stage 0 grill (escape hatch --no-grill) writing input/interview/grill.md, run right after the idea paragraph; the 5 stages + GATE 1 read the ledger (trace every row to a decision, honour Out-of-scope, carry deferred items as (assumption)). Clone grills the analyzers' ambiguities[]/state_gaps[] (upstream-first, one at a time) instead of a flat dynamic batch B, writing pipeline/grill.md. SKILL gains --no-grill, the A-green Stage 0 block, the A-clone ambiguity-grill block, GATE 1 ledger reconciliation, and the two bundle-layout slots. prompts/README + docs/SPEC-PIPELINE updated. Plugins regenerated; 0 leaks.
reason: user asked to add the grill-me skill to complement spec creation; greenfield's known weak spot is a thin idea answered by guessing — the grill establishes upstream decisions first (anti-hallucination), and clone ambiguities are better resolved as a dependency-ordered tree than a flat batch. Kept as a technique (no new agent) so it needs no installer/roster/openai.yaml change and propagates via the raw prompt-library copy. Authored marker-free because prompt-library files are not rendered (only SKILL.md is).
affects: claude, codex
by: claude

## 2026-06-11T05:30-loop-telemetry-feedback
type: add
target: templates/common/scripts/{{PREFIX}}-record-run.sh (new), templates/common/scripts/{{PREFIX}}-retro.sh (new), templates/common/commands/{{PREFIX}}.md, templates/common/agents/{{PREFIX}}-knowledge.md, selfimprove/{record-run,reflect}.sh
summary: Stage 1 of the goals-audit roadmap (claude-006: A1 A2 A3 A4 E8) — the self-improvement loop now FEEDS itself. New pipeline script {{PREFIX}}-record-run.sh (L1 capture, ships with the plugin): appends one JSON event to <repo>/selfimprove/runs/<YYYY-MM>.jsonl, accepts --tokens-in/--tokens-out/--cost estimates (E8), and reports events_since_retro + retro_due (>= $REFLECT_AFTER, default 10, events after the newest retro file). New {{PREFIX}}-retro.sh (L2, deterministic awk): per-agent pass-rate, user-feedback section (avg score, low-score events), token/cost totals, failure tail. Orchestrator gains a "Run telemetry (fire-and-forget)" section + record points after reviewer / final-runner / verifier / fit (A1) and a retro offer when retro_due fires (A2). The "Knowledge capture" section becomes "Post-ship: feedback → knowledge → nudges": ONE mandatory feedback question (score 1-5 + note) recorded as an agent=feedback event, score <=3 appends a bullet to selfimprove/lessons.md and feeds SESSION_RECAP (A4); plus a drain nudge when mp_repo/.ai/proposals holds >=3 queued patches (A3). {{PREFIX}}-knowledge input contract: SESSION_RECAP carries the feedback score/note; score <=3 = mine the note first. Root selfimprove kit updated for parity (record-run accepts the token/cost fields; reflect.sh gains the feedback + token sections). Telemetry is fire-and-forget by rule: never blocks, fails, or retries the pipeline. Scripts bash -n clean + functionally tested in a temp root (threshold fires at 11 events, counter resets after a retro, error paths emit ok:false and exit 0); plugins regenerated, 0 leaks; shellcheck not installed locally — CI covers it.
reason: the audit (docs/IMPROVEMENT-ROADMAP.md) found the learning loop only ~30% closed — record-run.sh was never invoked anywhere, runs/*.jsonl shipped empty, reflection and draining were flags the user had to remember, and the only signal was pass/fail with no user-satisfaction capture. Wiring capture into the orchestrator steps + nudging retro/drain when due + asking one post-ship feedback question closes the observe half of the loop automatically.
affects: claude, codex
by: claude

## 2026-06-11T06:30-cross-project-user-profile
type: add
target: templates/common/agents/{{PREFIX}}-knowledge.md, templates/common/commands/{{PREFIX}}.md, templates/android/agents/{{PREFIX}}-fit-android.md, templates/spec/skills/app-spec-creator/prompts/techniques/grill-me.md, templates/spec/skills/app-spec-creator/SKILL.md, docs/ARCHITECTURE.md
summary: Stage 2 of the goals-audit roadmap (claude-007: B1 B2 B3 B4) — a cross-project USER profile so the pipeline learns the user across pet projects instead of re-learning from zero. B1: {{PREFIX}}-knowledge gains a third routing category USER-PREFERENCE (durable facts about the user that transfer across projects) writing to $MP_USER_PROFILE / ~/.config/mobile-pipeline/user-profile.md; the agent owns the file skeleton (UI & design taste / Process preferences / Tech defaults / Anti-patterns; one fact per bullet with provenance) + merge rules (extend provenance instead of duplicating; contradictions rewrite the bullet keeping the old fact in the trail; keep <=80 lines); return contract gains kind:"user_profile". B2: /{{PREFIX}} Startup step 3 reads the profile; the grill protocol's recommended answers cite profile facts in a short parenthetical ("your usual choice") — bias only, never auto-decide, absence changes nothing. B3: grill-me.md v1.2.0 gains a neutral "user profile" rule (read once before the first question; bias recommendations; profile-informed deferrals logged as (assumption) citing the profile); SKILL.md Stage-0 block notes the rule applies in every grill mode (greenfield stages' defaults, clone ambiguity walk, feature variant). B4 taste journal: {{PREFIX}}-fit-android FIT payload gains optional taste_signals[] (cross-project preference candidates inferred ONLY from intended deviations, never from divergences); the --fit orchestrator shows them behind one y/N gate and appends accepted ones under "## UI & design taste" with provenance; the post-ship feedback note flags durable "always/never" statements as user_preference candidates in SESSION_RECAP. New Rules bullet pins the contract (read-at-startup, bias-only, two writers, the one file outside the project the pipeline may write). docs/ARCHITECTURE.md Memory section gains the "Cross-project user profile" layer. Plugins regenerated, 0 leaks (grill-me prompt stays marker-free/neutral per the prompt-library convention).
reason: the goals audit found NO user-centric memory anywhere — all memory is per-project and technical, so every new project re-learns the user and grill recommendations ignore history; goal 1 explicitly asks the system to "update memory across all my pet projects to understand me better". A single harness-neutral profile file with strict bias-only semantics adds that layer without changing behaviour for users who don't have one.
affects: claude, codex
by: claude

## 2026-06-11T07:30-orchestrator-continuity
type: add
target: templates/common/commands/{{PREFIX}}.md, templates/android/agents/{{PREFIX}}-tester-android.md, templates/android/agents/{{PREFIX}}-verifier-android.md, lib/build-marketplace.sh
summary: Stage 3 of the goals-audit roadmap (claude-008: A5 A6 A7 A8 E1) — conveyor continuity + stale-test integrity. A5: Phase 1 now ends with an INTENT ECHO-BACK at the SPEC gate (2-3 plain-language sentences — goal / the one behaviour that must become true / out of scope; never a SPEC paraphrase) so a misread idea is caught before any code; a corrected echo-back re-plans. A6: new `--continue` workflow — the single re-entry point: read-only inspection (active SPEC -> active phase tasks -> backlog -> clone fit state -> secondary signals retro_due/queued proposals), first-match-wins recommendation of ONE next command with a one-line why, gated y/N, then runs that workflow with all its own gates intact; argument-hint in build-marketplace gains --continue. A7 phase-exit hook: when a --phase run ticks the last task, --check runs AUTOMATICALLY (read-only) and on clones the orchestrator offers --fit (mandatory offer when the Fit-gate phase or screen-touching phase completed). A8 stale-test rule: orchestrator derives MODIFIED_EXISTING from the developer's commit (git show --name-status) and passes it to the tester; the tester gets a new "Stale-Test Update Rule" section (reconcile every modified pre-existing file's old tests with the new behaviour — update assertions, never weaken/delete; pure refactor -> record no-change-needed) and returns stale_tests_reviewed[]; the verifier gains Check 6 `stale_tests` (modified Mandatory-Coverage file's test must be in TEST_FILES or reviewed as no-change, else failed) — pass logic is now six checks, and the verifier prompt now explicitly carries MODIFIED_EXISTING/TEST_FILES/COVERAGE_EXCEPTIONS/STALE_TESTS_REVIEWED. E1: --fit resolves fit_threshold from .claude/mp/config.json `fitThreshold` (default 85) and ENFORCES it — report prints "vs threshold -> PASS|FAIL", FAIL means the clone may not be declared done; fit telemetry verdict/metric carry the threshold. Five new Rules bullets pin all of the above. Plugins regenerated, 0 leaks.
reason: the audit found (1) no round-trip confirmation of user intent — SPEC syntax was approved but not the understanding behind it; (2) the happy path was 4+ commands the user had to sequence by memory with nothing firing at phase exit; (3) the tester only wrote tests for new files, so changed behaviour left old tests silently asserting yesterday's contract with no gate catching it; (4) the fit score had no enforced pass bar anywhere, letting a mediocre clone ship.
affects: claude, codex
by: claude

## 2026-06-11T08:30-ci-propagation
type: add
target: .github/workflows/regen-plugins.yml (new), .github/workflows/validate-plugins.yml, selfimprove/README.md, docs/MARKETPLACE.md
summary: Stage 4 of the goals-audit roadmap (claude-009: A11 E5 A12) — propagation + validation run without a human remembering them. A11: new regen-plugins.yml — on push to main touching templates/** or lib/{build-marketplace,render}.sh, regenerate the plugin trees and auto-commit/push when drifted (contents:write; bot commit touches only the generated trees, which the paths filter excludes -> loop-guarded; normally a no-op because the PR drift gate keeps main in sync — it is the safety net for direct pushes). E5: validate-plugins.yml extended — bash -n now sweeps lib + claude-plugins + templates + selfimprove + eval + bootstrap.sh + install-spec.sh (existence-guarded per-dir loops, no fragile multi-dir find), and a new `shellcheck -S error` step (preinstalled on ubuntu-latest, apt fallback; error severity only so the retrofit doesn't block on legacy style warnings). A12: selfimprove/README.md gains "Scheduling the loop" (per-project retro is already nudged in-session by stage 1; weekly host-side `/mp --reflect` via cron / Task Scheduler examples — it needs a local harness, so not cloud CI; keep ~/.config/mobile-pipeline/projects.txt fresh) and docs/MARKETPLACE.md documents the auto-regen safety net, the extended CI gate, and the "append every newly wired project to projects.txt" setup step. Local checks: bash -n sweep over the new scope is clean; workflows are tab-free block YAML mirroring the proven validate-plugins structure (no local PyYAML — first CI run is the real validation; watch the first shellcheck pass for surfaced errors).
reason: the audit found the propagation half of the loop manual — a merged template improvement reached projects only after someone remembered build-marketplace + commit, validation ran only when remembered locally, and cross-project reflection depended on memory; goal 1 requires merged improvements to flow to all pet projects automatically.
affects: claude, codex
by: claude

## 2026-06-11T09:30-clone-completeness-gates
type: add
target: templates/spec/skills/app-spec-creator/scripts/crawl/element-manifest.sh (new), templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/agents/fit-checklist-author.md, templates/spec/agents/spec-evaluator.md, templates/spec/skills/app-spec-creator/prompts/rubrics/evaluator-rubric.md, templates/common/commands/{{PREFIX}}.md, templates/android/agents/{{PREFIX}}-fit-android.md, docs/{REFERENCE-CRAWLER,CLONE-PLAYBOOK}.md
summary: Stage 5 of the goals-audit roadmap (claude-010 authoring: C1 C2 C3 C5 C6 C7; C10 device run still pending) — three deterministic completeness gates so a visible button can no longer vanish silently. C1: new offline awk-only crawl script element-manifest.sh distils ST*.xml uiautomator dumps into input/crawl/elements/ST*.json (every clickable/long-clickable element: class/resource-id/text/content-desc/bounds; tested on a fixture incl. Cyrillic labels — extracts interactive nodes only); SKILL A.0 finalize runs it; fit-checklist-author gains crawl_elements_dir input and merges per-state manifests into per-screen spec/fit/elements/<Sxx>.json (union, deduped, expected:true unless deviations.md excludes; elements_files in return JSON). C2: evaluator-rubric v1.1.0 gains Class 5 "affordance coverage" — every user-meaningful element must map to an inventory feature/CTA, a US/AC, or an explicit decision (deviations/out-of-scope/assumption); unmatched = blocker unmatched_affordance (-> requirements-author, detail flags it as a GATE-1-level decision); spec-evaluator reads the manifests + reports coverage.unmatched_affordances[]. C6: clone-strict escalation — orphan_screen + state_coverage_gap warn->blocker when app.mode=clone. C7: GATE 2 now prints every coverage-gap list explicitly (evaluator coverage fields, user-story-writer coverage_gaps[], acceptance stories_without_scenario[]/untestable_stories[], fit author screens_uncovered[]/low_confidence_maps[]) as numbered lists the user must acknowledge. C3: --fit captures built element trees (uiautomator dump per screen, MSYS_NO_PATHCONV note, best-effort) and {{PREFIX}}-fit-android runs a deterministic structural element diff BEFORE the visual pass (reference manifest element with no built match = major/high-confidence divergence; extras = minor unless deviations explain). C5: --plan --phases runs a deterministic plan-coverage audit before its write gate — every registry.csv screen_id + traceability.csv FR/US id must appear in >=1 task; uncovered ids block until re-planned or explicitly acknowledged as deferred rows in 00_overview. Docs: REFERENCE-CRAWLER + CLONE-PLAYBOOK document the three gates. Plugins regenerated.
reason: the last clone iteration FORGOT buttons/features; the audit traced five lossy steps where none of the existing checks blocked (low-confidence CTAs decaying to risks, coverage gaps buried in JSON, warn-only orphan/state findings, planners never auditing FR/screen->task coverage, fit comparing only pixels). The crawl already captures exact element trees — turning them into spec-time, plan-time and build-time blockers makes completeness deterministic instead of hoping the multimodal eye notices.
affects: claude, codex
by: claude

## 2026-06-11T10:30-clone-fidelity-instrumentation
type: add
target: templates/spec/skills/app-spec-creator/scripts/crawl/bounds-to-dp.sh (new), templates/common/scripts/{{PREFIX}}-pixel-diff.sh (new), templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/agents/{fit-checklist-author,apk-analyzer}.md, templates/common/commands/{{PREFIX}}.md, templates/android/agents/{{PREFIX}}-{fit,ui-designer}-android.md, templates/android/snippets/material-theme-builder.md, docs/CLONE-PLAYBOOK.md
summary: Stage 6 of the goals-audit roadmap (claude-011: D1 D2 D3 D4+D7 D5 D9) — the visual pipeline becomes measurement-driven. D1: new bounds-to-dp.sh augments element manifests with bounds_dp/size_dp (dp = px*160/density; density recorded at crawl time via `adb shell wm density`, fixture-verified 880px@420dpi->335dp); fit-checklist-author quotes EXACT dp in must-match rows instead of density adjectives. D2: new {{PREFIX}}-pixel-diff.sh (ImageMagick IM7/IM6 autodetect, normalized RMSE -> similarity 0-100 + diff heatmap, auto-resize mismatched dims to reference, tool_missing graceful JSON exit 0); --fit gains Phase 2.5 (objective pixel pass per screen/state -> pixel_scores map + build/fit/diff/ heatmaps) and the fit agent ANCHORS fit_score to the pixel similarity (justify >15pt adjustments; lenient on resized:true). D3: capture normalization — both the crawl (SKILL A.0 step 3) and --fit Phase 2 enable Android demo mode (fixed clock/battery/wifi/no notifications) + font_scale 1.0, record the AVD profile/density in 00_meta.yaml so both comparison sides shoot the same canvas (mismatch -> explicit warning). D4+D7: apk-analyzer Pass 7.5 extracts assets into spec/assets/ — ALL fonts (res/font + assets/fonts; fonts_extracted[] replaces the "Roboto (guess)"), launcher icon, notable raster drawables (cap ~100/20MB, highest-density bucket) + extraction-manifest.md with a verbatim personal-use legal caveat; JSON gains assets_extracted_count/fonts_extracted. D5: Phase D writes machine-readable spec/design-tokens.json (style-analyzer JSON + APK exact overrides + provenance per group); Step 10 handoff says copy it to the dev project as .claude/mp/design-tokens.json; {{PREFIX}}-ui-designer-android gets a 3-tier token source resolution (design-tokens.json -> generate Color.kt/Type.kt directly with M3 role mapping + real font files; Theme Builder for greenfield seeds; Indigo default) — the manual Theme Builder seam is gone for clones; snippet updated ("NOT for clones"). D9: the fit agent walks every visual must-match row of spec/fit/<Sxx>.md and returns explicit per-row verdicts (pass/fail/uncheckable) in checklist_rows[]; every fail maps to a divergence; --fit report prints pixel avg + checklist pass counts. Both scripts bash -n clean + fixture-tested (dp math, tool_missing, arg errors); plugins regenerated, 0 leaks (mp-pixel-diff.sh ships in mp-dev, bounds-to-dp.sh in mp-spec skills/scripts).
reason: the last clone "didn't look like the original": the audit showed style tokens were eyeball guesses (±2sp, bucketed radii), exact pixel bounds in crawl dumps went unused, APK assets/fonts were inventoried but never extracted, the 03_style->ui/theme bridge was a manual Theme Builder step that replaced ground truth with a derived guess, and the fit gate was a free-form multimodal judgment with no objective number and no capture normalization. Measurement-first fixes each loss point while keeping the LLM for semantics.
affects: claude, codex
by: claude

## 2026-06-17T12:00-telegram-build-delivery
type: add
target: templates/common/scripts/{{PREFIX}}-deliver-telegram.sh (new), templates/common/commands/{{PREFIX}}.md, docs/TELEGRAM-DELIVERY.md (new), VERSION, CHANGELOG.md
summary: new /{{PREFIX}} --deliver step — send a built artifact to your own Telegram over an MTProto USER session (Telethon), default target "me" (Saved Messages), so the file cap is 2 GB not the bot API's 50 MB; no bot, no local Bot API server. New deterministic script {{PREFIX}}-deliver-telegram.sh: cross-platform bash wrapper delegating the MTProto call to python3 + telethon (external dep like adb/gradle); reads TG_API_ID/TG_API_HASH/TG_SESSION/TG_TARGET from env or a gitignored repo-root .env (TG_* keys only, never executed); auto-detects newest *.apk under */build/outputs/* when no path given; --login mode mints a StringSession interactively; emits exactly one JSON line and mirrors ok->exit code; 2 GB size guard. Wired into the orchestrator (Usage line, Deterministic-steps bullet, Workflow: --deliver with one-time-setup block + optional post-build send offer). build-marketplace common-scripts loop auto-ships it as claude-plugins/mp-dev/scripts/mp-deliver-telegram.sh (0 leaks, bash -n clean). VERSION 1.8.1->1.9.0 (MINOR, additive).
reason: user wanted to self-deliver <100 MB builds via Telegram without the bot API 50 MB cap or a local Bot API server; an MTProto user session is the simplest path to the 2 GB cap and integrates as one deterministic pipeline step.
affects: claude, codex
by: claude

## 2026-06-20T10:00-bugfix-repro-first-runtime
type: update
target: templates/common/commands/{{PREFIX}}.md
target: templates/android/agents/{{PREFIX}}-developer-android.md
target: templates/android/agents/{{PREFIX}}-tester-android.md
summary: --bugfix repro-first discipline for runtime/persistence/cold-start bugs
reason: Pipeline declared a cold-start bug fixed twice over because (1) Developer reproduced its own hypothesis instead of the user's literal steps, (2) a self-authored regression test that passed by construction was treated as proof, and (3) the test reused a single in-memory DataStore instance for write+read so the real disk round-trip was never exercised. The fix was only confirmed by driving the user's literal steps on a real device.
affects: claude, codex
by: mp-improve

## 2026-06-20T13:17-postship-deliver-before-feedback
type: fix
target: templates/common/commands/{{PREFIX}}.md, templates/common/scripts/{{PREFIX}}-deliver-telegram.sh
summary: deliver build to Telegram BEFORE asking feedback; exclude androidTest APKs from auto-pick
reason: user cannot meaningfully rate a shipped result until they have the built app in hand; auto-pick was sending the instrumentation test APK (app-debug-androidTest.apk, 3.6 MB) instead of the app APK (app-debug.apk, 82 MB) when connectedAndroidTest ran more recently than assembleDebug
affects: claude, codex
by: mp-improve

## 2026-06-25T14:00-developer-android-version-bump-on-commit
type: add
target: templates/android/agents/{{PREFIX}}-developer-android.md
summary: require developer to bump versionName PATCH (+1) and versionCode (+1) on every pipeline commit; MAJOR/MINOR are human-only
reason: every /mp commit should produce a unique, traceable versionName (MAJOR.MINOR.PATCH) so builds delivered via --deliver or side-loaded are unambiguously identified; without this rule the pipeline leaves versionName static across commits
affects: claude, codex
by: mp-improve

## 2026-06-27T12:00-version-bump-no-sed-i
type: fix
target: templates/android/agents/{{PREFIX}}-developer-android.md
summary: version-bump snippet replaced `sed -i` with the write-to-temp + mv pattern (versionName and versionCode edits)
reason: the merged version-bump-on-commit snippet used `sed -i`, which violates the golden rule (GNU vs BSD sed differ); rewrite to `sed ... > $TMP && mv $TMP $GRADLE` for cross-platform safety
affects: claude, codex
by: claude

## 2026-07-05T09:55-brain-level-routing-and-twins
type: add
target: templates/common/agents/{{PREFIX}}-knowledge.md, templates/common/agents/{{PREFIX}}-improve.md, templates/common/agents/{{PREFIX}}-reflect.md
summary: BRAIN-LEVEL routing class + brain_candidates[] in knowledge; optional twin_applicability in improve/reflect payloads; user-profile path now resolves $MP_USER_PROFILE -> $BRAIN/core/user-profile.md -> ~/.config/mobile-pipeline/user-profile.md
reason: a second-brain repo (github.com/desvingns/brain) now carries cross-project knowledge; lessons that generalize beyond mobile-pipeline projects route to $BRAIN/inbox (human-gated promotion via /brain promote), and improve/reflect proposals declare applicability to the twin me-dev pipeline so /brain sync-twins can stage ports on the other side
affects: claude, codex
by: claude

## 2026-07-10T16:00-gpt-5-6-model-tier
type: update
target: install-spec.sh, templates/spec/skills/app-spec-creator/SKILL.md, templates/dev/codex/skills/mp-dev/references/codex-agent-shims.md, templates/common/agents/{{PREFIX}}-maintainer.md
summary: promote all frontier MP Spec and MP Dev Codex subagent tiers from gpt-5.5 to gpt-5.6, preserving existing reasoning effort and sandbox assignments.
reason: GPT-5.6 is available in preview and the user requested the new model for the pipeline and MyMoney.
affects: claude, codex
by: codex

## 2026-07-10T16:10-mymoney-mp-spec-cache-path
type: fix
target: D:/Pet/MyMoney/.codex/agents/*.toml
summary: repoint MyMoney's MP Spec native subagents from the missing mobile-pipeline mp-spec 1.8.1 cache to the installed personal mp-spec 1.10.0 cache.
reason: the old cache directory no longer exists, so the subagents could not load their mandatory MP Spec skill body.
affects: codex
by: codex

## 2026-07-13T20:00-lazy-mp-runtime
type: update
target: templates/common/commands/{{PREFIX}}.md, templates/common/commands/runtime/*, lib/build-marketplace.sh, bootstrap.sh
summary: replace the 83k-character /mp monolith with a 3.5k compact router, 15 lazy mode runbooks, 14 shared contracts, validated heading/flag coverage, and self-contained Claude/Codex runtime packaging.
reason: fixed prompt context was paid on every mode even though most workflows use a small disjoint subset; lazy contracts reduce fixed context about 95 percent while retaining every gate and payload rule.
affects: claude, codex
by: codex

## 2026-07-13T20:10-risk-model-quality-routing
type: add
target: templates/common/scripts/{{PREFIX}}-risk-route.sh, templates/android/agents/{{PREFIX}}-{developer-standard,semantic-reviewer,verifier-lite}-android.md, templates/common/commands/runtime/contract-risk-routing.md, templates/dev/codex/skills/mp-dev/references/codex-agent-shims.md
summary: deterministic task-risk scoring now selects a standard or powerful Developer, focused semantic review, a full or lite Verifier, and a fresh independent critic for high-risk changes; invalid routing falls back to the strongest path.
reason: routine local changes can use cheaper execution without weakening the canonical contract, while migrations, security, payments, wiring, concurrency, broad diffs, and visual evidence benefit from additional independent judgment.
affects: claude, codex
by: codex

## 2026-07-13T20:20-mp-spec-cache-evidence-budget
type: update
target: templates/spec/skills/app-spec-creator/SKILL.md, templates/spec/skills/app-spec-creator/scripts/{spec-cache,spec-preflight,spec-usage}.sh
summary: add lean/balanced/max spend semantics, content-addressed phase cache, compact ID-based evidence packets, conditional quality fan-out with explicit skipped artifacts, deterministic evaluator preflight, targeted failed-rubric retries, and normalized agent usage telemetry.
reason: MP Spec repeatedly paid for unchanged inputs and sent oversized cross-phase context to every specialist; mechanical failures should be fixed before frontier evaluation and expensive calls should remain proportional to evidence/risk.
affects: claude, codex
by: codex

## 2026-07-13T20:30-inbox-only-brain-memory
type: update
target: templates/common/agents/{{PREFIX}}-knowledge.md, templates/common/scripts/{{PREFIX}}-brain-memory.sh, templates/common/commands/runtime/{fit,contract-post-ship}.md
summary: make second-brain curated layers read-only, route user/general lessons through fingerprinted inbox candidates, and retrieve only tag-selected context under a hard token budget; fit and post-ship taste capture use the same gateway.
reason: direct profile writes bypassed the human promotion gate and broad brain reads duplicated context; one asymmetric gateway improves provenance, deduplication, safety, and token economy across projects.
affects: claude, codex
by: codex

## 2026-07-13T20:40-learning-sync-eval-ci
type: add
target: lib/sync.sh, templates/common/scripts/{{PREFIX}}-{record-run,retro,improve-drain}.sh, selfimprove/*, eval/*, tests/*, .github/workflows/{validate-plugins,regen-plugins}.yml
summary: implement incremental adapter cursors, provider-vs-estimated usage telemetry with cache/reasoning/cost/duration/correlation fields, telemetry health, proposal lifecycle receipts, deterministic eval cases, property/fuzz tests, and Linux/macOS/Windows CI.
reason: the learning loop could not distinguish missing telemetry from cheap runs, proposal queues had no terminal state, and adapter/CI drift lacked deterministic cross-platform gates.
affects: claude, codex
by: codex

## 2026-07-13T20:50-render-session-graphify-boundaries
type: fix
target: lib/render.sh, AGENTS.md, .ai/README.md, .ai/tasks/INDEX.md, .graphifyignore, scripts/graphify-update-canonical.sh
summary: implement inline/multiline tool conditional rendering, load only active task files at session start, exclude generated plugin/history duplicates from Graphify, and preserve the previous graph before a canonical forced rebuild.
reason: the documented dual-tool marker contract was not executable, historical task/plugin duplication inflated every session/query, and Graphify's shrink guard prevented intentional corpus cleanup without an auditable archive.
affects: claude, codex
by: codex

## 2026-07-13T21:00-release-safety-hardening
type: fix
target: install-spec.sh, lib/sync.sh, scripts/graphify-update-canonical.sh, templates/common/scripts/{{PREFIX}}-{brain-memory,record-run,improve-drain}.sh, templates/spec/skills/app-spec-creator/scripts/spec-usage.sh, templates/common/commands/runtime/contract-startup.md, .gitattributes, tests/*
summary: archive all replaced installer/adapter state, abort proposal lifecycle transitions on regeneration failure, restore a known-good graph after partial failures, enforce strict JSON decimals and finite option parsing, route startup through the bounded brain gateway, and lock cross-platform LF semantics.
reason: final independent review found destructive force-install behavior, an unowned AGENTS.md overwrite, CRLF-sensitive runtime parsing, partial-failure state loss, malformed numeric JSON, an option-loop hang, and memory/heartbeat portability gaps that deterministic negative tests now cover.
affects: claude, codex
by: codex

## 2026-07-13T21:05-retained-temporary-evidence
type: fix
target: templates/common/scripts/{{PREFIX}}-{cross-reflect,pixel-diff}.sh, templates/spec/skills/app-spec-creator/scripts/crawl/bounds-to-dp.sh
summary: replace temporary-file deletion with collision-safe retained evidence under local cache/archive paths and expose the retained path in structured output where useful.
reason: the personal never-delete policy applies to deterministic helpers too; preserving bounded intermediate evidence also makes failed comparisons, reflection aggregation, and conversion errors diagnosable.
affects: claude, codex
by: codex

## 2026-07-13T21:10-bootstrap-no-git-contract
type: fix
target: bootstrap.sh, tests/test-bootstrap.sh, .github/workflows/validate-plugins.yml
summary: implement the documented --no-git switch so throwaway/non-git generation can suppress only the repository warning while retaining every other validation and preflight gate.
reason: final bootstrap smoke exposed a docs/parser mismatch; a dedicated regression now keeps the public CLI contract executable on every CI host.
affects: claude, codex
by: codex

## 2026-07-13T21:15-generic-personal-scope-policy
type: fix
target: templates/spec/skills/app-spec-creator/SKILL.md
summary: express the personal-project isolation rule generically without embedding organization-specific names in the shared skill or generated plugins.
reason: exclusion rules should block private work integrations by category while keeping the personal repository itself free of corporate content.
affects: claude, codex
by: codex

## 2026-07-18T18:29-backlog-consume-staleness-check
type: update
target: templates/common/commands/runtime/feature.md
summary: Add a cheap staleness pre-check before promoting a backlog SPEC to active, offering close-as-delivered or re-scope when the SPEC's described behaviour already substantially exists in code.
reason: Backlog-consume mode (--next / --backlog <slug>) skipped straight to Phase 2 Developer with no check that the SPEC's premise still matches current code, so a SPEC drafted ahead of consumption time could be fully or partially already built and get silently re-implemented — confirmed twice in one MyMoney epic (SPEC 23 CSV export/import fully pre-existing, SPEC 24 factory-reset partially pre-existing).
affects: claude, codex
by: claude

## 2026-07-18T00:00-runner-android-junit-xml-verdict
type: fix
target: templates/android/scripts/{{PREFIX}}-runner-android.sh
summary: derive the unit-test pass/fail verdict from JUnit XML (test-results/testDebugUnitTest/*.xml tests/failures/errors) instead of grepping the redirected console log for Gradle's rich-console-only "N tests completed" summary line.
reason: the summary line is rendered only by Gradle's interactive rich console and is absent once stdout is redirected to a file (as this script does), so the console-grep heuristic fell through to a hard-coded fail regardless of true pass/fail state; confirmed masking real test-compile failures across 3+ separate /mp runs in one downstream project. Console-grep is kept only for extracting failing test names/messages when a failure is already known.
affects: claude, codex
by: mp-improve

## 2026-07-18T18:30-tester-stale-list-count-assertions
type: update
target: templates/android/agents/{{PREFIX}}-tester-android.md
summary: add an explicit bullet to the Stale-Test Update Rule requiring a grep for count/exhaustiveness assertions (assertCountEquals, .size ==, "exactly N", "distinct") whenever the modified composable renders a list/section.
reason: on MyMoney, Verifier Check 6 bounced the same SPEC (factory-reset) back to Tester twice before a stale exhaustive section/row count assertion in SettingsRootContentTest was found — adding one row to a list-rendering composable reads as correct in isolation, so a behaviour-diff read alone misses a hard-coded count assertion on sibling elements. This is a generic Compose-testing blind spot, not project-specific.
affects: claude, codex
by: mp-improve

## 2026-07-28T11:38-board-move-stage-content-edits
type: update
target: templates/common/commands/runtime/contract-rules-board.md
summary: New board rule: after `git mv` of a just-edited SPEC, run `git add <destination>` and verify with `git status` that BOTH the rename and the content change are staged before committing.
reason: `git mv` with unstaged content edits stages a 100% rename only; the commit records the bare rename and silently drops the Status/front-matter re-scope (observed in MyMoney SPEC activation commit 4f0d2aaf, 2026-07-28).
affects: claude, codex
by: mp-improve

## 2026-07-28T11:37-semantic-reviewer-test-pinned-symbols
type: update
target: templates/android/agents/{{PREFIX}}-semantic-reviewer-android.md
summary: unused-symbol findings now require a unit/androidTest source sweep; test-pinned symbols downgrade to uncertainties[] with the test-reference count
reason: test-pinned symbols are legitimate API surface; dead-code findings without a test-source sweep are false-positive-prone and can wrongly satisfy or block removal preconditions (observed in MyMoney 2026-07-28: LockController.markUnlocked() flagged unused at 0 production call sites while 5 tests pinned it)
affects: claude, codex
by: mp-improve

## 2026-08-12T21:30-semantic-blocker-user-impact
type: update
target: templates/android/agents/{{PREFIX}}-semantic-reviewer-android.md, templates/common/commands/runtime/contract-risk-routing.md, templates/common/commands/runtime/contract-execution.md
summary: semantic blockers now require plain-language context, a concrete user case, shipping impact, exact correction direction, and preserved technical evidence
reason: technical-only blocker reports can stop the pipeline without explaining the release risk to the user; an entitlement state-machine review exposed this gap when a broken server record and whitelist expiry were only understandable after a separate explanation
affects: claude, codex
by: mp-improve

## 2026-08-13T20:10-retro-evidence-gates-v2
type: update
target: templates/common/scripts/{{PREFIX}}-retro.sh
summary: retro reports now enforce sample-size eligibility, cluster concrete failures, and surface low-feedback eval candidates before prompt changes
reason: the retro checklist was advisory and could overinterpret tiny samples, lose recurring failure structure, or change prompts before converting low feedback into reproducible evaluation cases
affects: claude, codex
by: {{PREFIX}}-improve

## 2026-08-14T18:40-reviewer-multimodule-layers
type: fix
target: templates/android/scripts/{{PREFIX}}-reviewer-android.sh, templates/android/agents/{{PREFIX}}-reviewer-android.md, templates/common/agents/{{PREFIX}}-reviewer-base.md, lib/build-marketplace.sh, tests/test-reviewer-android.sh
summary: reviewer resolves layers per file instead of one hard-coded source root, checks every source set, adds module dependency-direction/cycle/undeclared-import checks, and gains a --warn-only adoption mode
reason: gating every check on app/src/main/java/<pkg> made the gate a silent no-op on multi-module projects — it answered pass with zero violations for a change the semantic reviewer then rejected four times over the following hour, so all architectural findings were paid for at LLM prices
affects: claude, codex
by: claude

## 2026-08-14T18:41-risk-route-declared-signals
type: fix
target: templates/common/scripts/{{PREFIX}}-risk-route.sh, templates/common/agents/{{PREFIX}}-planner.md, templates/common/specs/README.md, templates/common/commands/runtime/contract-risk-routing.md
summary: router reads a declared Risk-signals line, matches non-English prose, counts each signal once, detects DI/persistence from file content, and escalates security work that also touches state/wiring/persistence
reason: the keyword lists were English-only and the file globs were lowercase, so a Russian-language SPEC crossing session auth, Hilt wiring, and bounded polling scored 4 and routed to the cheap developer with no independent critic; the one signal it did match came from the substring "Token" inside accessToken()
affects: claude, codex
by: claude

## 2026-08-14T18:42-semantic-repair-loop-contract
type: add
target: templates/common/commands/runtime/contract-risk-routing.md, templates/common/commands/runtime/contract-execution.md, templates/common/agents/{{PREFIX}}-architect.md
summary: stable finding IDs, one batched holistic re-audit, a resolved_findings payload, a two-cycle budget with architect PREFLIGHT escalation, and a ratchet that raises the route when the semantic reviewer reports high risk or a blocker
reason: the contract said only that a semantic failure blocks Tester, so the loop was improvised as fix-the-listed-lines then re-review; that rediscovers one facet of the same design problem per cycle and the reviewer's own repeated risk=high verdict was recorded in telemetry and then discarded
affects: claude, codex
by: claude

## 2026-08-14T18:43-test-clock-real-io-marker
type: fix
target: templates/android/agents/{{PREFIX}}-tester-android.md, templates/android/scripts/{{PREFIX}}-reviewer-android.sh, templates/android/agents/{{PREFIX}}-reviewer-android.md, templates/common/agents/{{PREFIX}}-reviewer-base.md
summary: runTest stays the default but real-I/O tests may use runBlocking with a "// {{PREFIX}}-real-io: <reason>" marker; adds the mixed-clock prohibition, an authenticated MockWebServer fixture pattern, and a stable-token rule for source-inspecting contract tests
reason: the blanket runBlocking ban made the tester wrap real MockWebServer calls in runTest, virtual time cancelled the production timeout before the real response landed, and the resulting six failures took about an hour to diagnose; the fix that made them pass violated the rule and survived only because the check was scoped to app/
affects: claude, codex
by: claude

## 2026-08-14T18:44-runner-scoped-mode
type: add
target: templates/android/scripts/{{PREFIX}}-runner-android.sh, templates/common/commands/runtime/contract-feature-implementation.md
summary: runner gains --scope for module-only unit tests with no lint/coverage/screenshots, and the feature contract iterates scoped then runs the full suite exactly once as the final gate
reason: every repair iteration re-ran the whole multi-module suite plus lint plus coverage to answer whether six tests in one module now pass, paying a release-gate price for a debugging question
affects: claude, codex
by: claude

## 2026-08-14T18:45-epic-design-capsule
type: add
target: templates/common/agents/{{PREFIX}}-planner.md, templates/common/commands/runtime/feature.md, templates/common/agents/{{PREFIX}}-architect.md
summary: the planner writes a Design capsule into the epic overview and backlog-consume mode injects it into the SPEC as DESIGN_CAPSULE before any Phase 2 agent; the architect gains a PREFLIGHT capsule mode as the escalation target
reason: backlog-consume deliberately skips Phase 0 and Phase 1, so no step of the pipeline ever performed a design pass on a planned slice and cross-cutting decisions were re-derived per SPEC by the semantic reviewer after the code existed; the planner already holds the design source, so the capsule costs no extra agent call
affects: claude, codex
by: claude

## 2026-08-14T18:46-telemetry-compliance
type: update
target: templates/common/commands/runtime/contract-telemetry.md, templates/common/scripts/{{PREFIX}}-retro.sh
summary: duration_ms and correlation_id are required at every record point, repair_cycle/finding_ids/route_escalated/mode join the metric strings, and the retro reports instrumentation compliance before any cost conclusion
reason: the schema already accepted duration and token fields but no recorded event carried them, so a multi-hour run could only be explained by inference from step boundaries — which is how review-cycle cost gets misattributed to the build system
affects: claude, codex
by: claude
