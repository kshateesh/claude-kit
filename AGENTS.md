# Working agreement

Read this before writing code. It is short on purpose.

## Defaults

- TypeScript. No `any`, and no `!` to silence the compiler.
- Small modules, one job each. Delete code rather than commenting it out.
- Do not add a dependency without asking first. Prefer the platform.
- Do not edit a file I did not name. If the change needs code outside that scope, stop and tell me.

## Verify, do not assert

- Failing test first, then the implementation.
- After each change run the test command and show me the real output, not a summary of it.
- "It works" means a command and its exit code.
- Never suppress an error, widen a type, or catch-and-ignore to make a symptom disappear.

## When you are unsure

- High confidence: proceed, no hedging.
- Medium: state the assumption in one line, then proceed.
- Low: stop and ask. Do not write code against a guess.
- Never invent an API, flag, path, or config key. If it was not verified, say that it was not.

## Correctness rules that are not negotiable

- Money is an integer in minor units. Never a float.
- Validate external input at the boundary, once. Reject unknown fields rather than ignoring them.
- Reject invalid input deterministically. No partial writes, no empty 200 standing in for an error.
- Anything that can be retried must be safe to retry.

## Style

- Match the surrounding code even where you would do it differently.
- No em dashes in prose. Plain hyphen.
