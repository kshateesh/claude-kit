# Back end

## Scope

- Edit only what the request demands. Every changed line traces to the ask.
- Remove only imports your own change orphaned. Mention pre-existing dead code, do not delete it.
- No speculative features, no abstraction for a single call site.

## Correctness

- Treat external input as malformed until validated. Guard null, undefined, empty, NaN, wrong type.
- Handle the boring ones: missing fields, empty result sets, upstream timeouts, unknown enum values,
  cache misses, pagination boundaries.
- Never introduce silent data loss or a swallowed failure.

## Anything that touches money or state

- An idempotency key from the caller, enforced by a unique constraint. The database is the guarantee,
  not application code. Two instances checking before inserting is a race that loses money.
- Guarded state transitions: update only from the states you are allowed to leave.
  Then duplicates, out-of-order events and replays all collapse into zero rows updated.
- Return an acknowledgement when the outcome is not yet known. A 202 with an id, not a 200 with a lie.
- Write the state change and the event that announces it in one transaction, via an outbox.
  There is no two-phase commit between a queue and a database, so the database is the commit point.

## Hot paths

- No blocking I/O in a request handler.
- Watch allocation in loops and serialisation on the request path. Parallelise independent work.

## Tests

- Failing test first. Assert behaviour, not implementation. Include the negative and boundary cases.
- For an HTTP handler, export a factory that builds the app. Tests get a clean instance and nothing binds a port.
- If the code cannot be tested, refactor until it can.

## Persistence in a time-boxed build

Put it behind a repository interface with an in-memory implementation, and say so out loud.
Name the real schema and its constraints, because that is where the guarantee actually lives.
