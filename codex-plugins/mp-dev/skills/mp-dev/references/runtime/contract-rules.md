<!-- mp-runtime-contract: rules -->

## Rules

- Orchestrator NEVER writes mobile production code (Kotlin/Swift/Compose/Gradle/Xcode build scripts) or tests.
- Orchestrator NEVER modifies application source files directly. (Writing markdown artifacts to `.claude/specs/` during `--discuss` is allowed — these are planning documents, not code.)
- All code changes happen inside spawned agents.
- If a spawned agent fails — stop the chain and report immediately.
- LLM agent output is validated as JSON (or BRAINSTORM block for architect). On parse failure, retry the same agent ONCE with an explicit "JSON only, no prose" preface. Second failure → stop.
- The **cross-project user profile** resolved by `mp-brain-memory.sh` at Startup is read-only curated context and only ever BIASES recommended answers — it never auto-decides, and its absence changes nothing. `mp-knowledge` and the gated `--fit` taste journal route preference candidates through the same gateway's `append-candidate` command into the brain inbox/operational layer; they never write `brain/core/*` or the curated profile directly.
