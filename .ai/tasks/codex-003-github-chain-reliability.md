# codex-003 — GitHub push and Codex chain reliability

STATUS: complete
OWNER: codex

## Objective

Make the standard `--feature --next --chain` path reliable when GitHub credentials are provided by
the machine's normal Git credential helper rather than a `GITHUB_TOKEN` environment variable, and
make the Codex successor-task hand-off match the current `create_thread` prompt contract.

## Acceptance

- Runtime push uses `origin` first with non-interactive prompts; an explicit token is optional.
- Chain creates a new local task with no inherited context and passes the exact command as its only
  initial prompt; it never attempts an empty prompt or a second message.
- Canonical templates, generated marketplace trees, installed Codex skill, tests, and release notes
  agree.
