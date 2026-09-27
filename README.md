# claude-kit

A portable agent setup I drop into a project. Working agreement, four toolchain starters,
three tested guardrails, two subagents, one pre-handover checklist.
Installs into the project, not into your machine.

Tool-agnostic where it can be: `AGENTS.md` is the open convention and is read by several
coding agents. `CLAUDE.md` imports it and adds the Claude Code specifics.

## Install

```bash
git clone https://github.com/kshateesh/claude-kit.git
./claude-kit/install.sh /path/to/your/project
```

That writes `CLAUDE.md`, `AGENTS.md`, and `.claude/` into the target directory and touches
nothing else. No global state, no dotfiles, no package installs.

```bash
./install.sh --dry-run  DIR   # print what would change, write nothing
./install.sh --check    DIR   # report drift, exit 1 if any
./install.sh --uninstall DIR  # remove exactly what it installed
```

## What is in it

| Path | What it does |
|---|---|
| `AGENTS.md` | The working agreement. Defaults, verification, confidence, correctness rules. |
| `CLAUDE.md` | Imports `AGENTS.md` and the rules, adds Claude Code workflow. |
| `.claude/rules/frontend.md` | Component design, where state lives, effects, testing, accessibility. |
| `.claude/rules/backend.md` | Scope, correctness, idempotency and money, tests. |
| `.claude/rules/api-contracts.md` | Response shape, validation, pagination, breaking-change rules. |
| `.claude/rules/scaffolding.md` | Which stack for which shape, and the setup details that cost time. |
| `.claude/agents/code-reviewer.md` | Reviews a diff. Sonnet. Verdict, not prose. |
| `.claude/agents/debugger.md` | Reproduces before fixing. Opus. Stops after two failed attempts. |
| `.claude/skills/ship-check/SKILL.md` | `/ship-check` before handing anything over. |
| `.claude/hooks/*.sh` | The three guardrails below. |
| `.claude/settings.json` | Permissions, and the hook wiring. |
| `verify.sh` | Tests for the guardrails. |
| `starters/*.sh` | Bootstrap a toolchain and prove its test suite runs. |

## Starters

Scaffold the toolchain, never the solution. Each script runs the official scaffold, wires the
test harness, installs this kit, and runs the suite so you see it green before you write a line.
One smoke test is left behind to prove the wiring; delete it in your first minute.

```bash
./starters/frontend.sh    my-app   # Vite, React, TS, Vitest, Testing Library
./starters/backend.sh     my-api   # Express, TS, tsx, Vitest, supertest
./starters/fullstack.sh   my-app   # both, web/ and api/, Vite proxies /api
./starters/backend-db.sh  my-api   # back end plus a repository seam, node:sqlite
```

Measured on a warm npm cache: 14s, 9s, 10s, 5s. Budget a minute on a cold one.

Deliberately absent from all of them: router, state library, component library, CSS framework,
auth, Docker, monorepo tooling. Every dependency present has a reason you can say out loud.

`backend-db.sh` is the interesting one. It ships a repository interface with an in-memory
implementation and a `node:sqlite` implementation, and runs **one contract test against both**,
so they cannot drift. SQLite is built into Node 22.5 and later, so there is no native build step
and no daemon. The suite detects it at runtime and skips that half on an older Node rather than
failing.

`.claude/rules/scaffolding.md` carries the same decisions into the project, so the agent follows
them when extending an existing codebase rather than only when starting a new one.

## Guardrails, in three layers

The text in `AGENTS.md` is a request the model can talk itself out of. These are not.

| Layer | Mechanism | Covers |
|---|---|---|
| Read | `deny` rules in `settings.json` | Reading `.env`, keys, anything under `secrets/` |
| Write | `guard-secrets.sh` on PreToolUse | Editing credential, key, or state files |
| Shell | `guard-dangerous-commands.sh` on PreToolUse | `rm -rf` outside the project, force-push to main, redirects into secrets |

Plus `format-after-edit.sh` on PostToolUse, so formatting never reaches a diff.

The `rm -rf` rule is one sentence: **allowed on a relative path inside the project, nowhere else.**
`rm -rf node_modules` works. `rm -rf ~/Documents`, an absolute path, a parent directory and a bare
glob are all refused. That rule exists because the machine is not always mine.

`npm install` is on `ask`, matching the line in `AGENTS.md` that says not to add a dependency
without asking. A rule the config does not enforce is a rule that decays.

## Verify

```bash
./verify.sh
```

27 cases. Each one feeds a real hook payload to a real hook and asserts the exit code.
The allow cases matter as much as the block cases, because a guard that blocks ordinary
work gets switched off within a day. Exit 0 means every case passed.

Two bugs were found by this suite rather than in use: a redirect parser that kept a trailing
`)` and so misread `.env.example` as a secret, and an unquoted variable that let the shell
expand `*` before the bare-glob check could reject it.

## Explaining it in two minutes

1. **`AGENTS.md` is the agreement.** Failing test first, show real output, never invent an API,
   money is an integer in minor units. It is short so it is actually read.
2. **The starters scaffold a toolchain, not a solution.** Official Vite or a bare Express, plus
   the test harness, green before I write anything. Nothing arrives that I cannot explain.
3. **The rules are split by concern** and imported from `CLAUDE.md`, so front-end and back-end
   guidance are separate files rather than one wall of text.
4. **The guardrails are enforcement, not advice.** Three layers: reads denied by config, writes
   blocked by a hook, shell redirects blocked by another. `rm -rf` is scoped to the project.
5. **The guardrails have tests.** `./verify.sh`, 27 cases, and it has already caught two real bugs.
6. **Two subagents with deliberate model choices.** Review on Sonnet because it is a bounded
   read-only pass. Debugging on Opus because root-causing is the part worth paying for.
7. **It installs into the project and uninstalls cleanly.** Nothing global, nothing left behind.

## Design notes

**Copies, not symlinks.** Some contexts skip a symlinked `CLAUDE.md`, which would silently
disable the kit. A copy is boring and always loads. `--check` reports drift so the copy does
not quietly diverge.

**Hooks fail open.** They read their JSON payload with `jq`, fall back to `python3`, and if
neither exists the guard is simply off. These protect against an agent mistake, not against an
adversary; blocking all work because `jq` is missing trades a small risk for a larger one.
Where that trade would be wrong, the mechanism is a `deny` rule in config instead, which cannot
fail open.

**Stated limitation.** The shell guard sees a command before the shell expands it, so a path
that arrives through a variable is invisible to it. Defence in depth, not a seal.

**Nothing personal in here.** No profile, no employer, no project names. It is a working
agreement and a set of guards, so it is safe to share and safe to read.
