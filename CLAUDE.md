# Project instructions

@AGENTS.md

@.claude/rules/frontend.md

@.claude/rules/backend.md

@.claude/rules/api-contracts.md

@.claude/rules/scaffolding.md

## How I want you to work

- Plan before editing anything non-trivial. Show me the plan and wait.
- Scope each task tightly. A diff I cannot read in one screen is a diff I will not review properly.
- Run the `code-reviewer` subagent on your own diff before calling something done.
- Use the `debugger` subagent when something fails. Reproduce before fixing.
- Run `/ship-check` before handing anything over.

## What is enforced rather than requested

Three hooks wired in `.claude/settings.json` enforce what the text above only asks for.
They have tests: `./verify.sh`.

| Hook | Event | Does |
|---|---|---|
| `guard-secrets.sh` | PreToolUse, Edit and Write | Blocks writes to `.env`, private keys, state and credential files |
| `guard-dangerous-commands.sh` | PreToolUse, Bash | Blocks `rm -rf` on wide targets, force-push to main, shell redirects into secrets |
| `format-after-edit.sh` | PostToolUse, Edit and Write | Formats the file just touched, so style never reaches a diff |
