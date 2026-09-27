# Scaffolding

## The rule

Scaffold the toolchain, never the solution.

An official scaffold plus a test harness is a starting point I can explain line by line.
A feature-rich template is code I did not write and will be asked about. Every dependency
present must have a reason I can give out loud, so nothing arrives "just in case".

Deliberately absent from every starter here: router, state library, component library,
CSS framework, auth, Docker, monorepo tooling. Add what the problem needs, when it needs it.

## The stacks

| Shape | Stack | Why this one |
|---|---|---|
| Front end | Vite, React, TypeScript, Vitest, Testing Library | The official scaffold, so the files are recognisable and standard |
| Back end | Express, TypeScript, tsx, Vitest, supertest | Minimal surface. A heavier framework's own boilerplate is code I did not write |
| Front and back | The two above, `web/` and `api/`, Vite proxying `/api` | Same origin in dev, so no CORS setup and no base URL to switch |
| Back end with persistence | The back end plus a repository interface | The seam is the point, not the engine |

## Setup details that cost time when you get them wrong

- `@testing-library/dom` is a **peer** dependency of React Testing Library from v16. Install it
  explicitly or `screen` fails at runtime.
- The Vitest setup file imports `@testing-library/jest-dom/vitest`, not the bare package.
- Keep `globals: true` in the Vitest config. Testing Library registers its between-test cleanup
  through the global `afterEach`; with globals off it never registers, and the second test that
  queries the same element fails with "found multiple elements".
- Fake timers: `vi.useFakeTimers({ shouldAdvanceTime: true })` with a plain `userEvent.setup()`.
  Passing `advanceTimers` to `setup()` alongside `useFakeTimers()` hangs with no useful error.
- Export the HTTP app as a factory, not a module that listens. Tests get a clean instance and
  nothing binds a port.

## Persistence

Default to a repository interface with an in-memory implementation, and say so out loud:
the logic stays testable in a short build, and the real schema and its constraints are named
rather than implied.

When persistence has to be real, `node:sqlite` is built into Node 22.5 and later: no native
build, no daemon, no Docker. Run one contract test against every implementation so the
in-memory version and the real one cannot drift.

Reach for Postgres when the task genuinely needs it. Twenty minutes of Docker is twenty
minutes not spent on the problem.
