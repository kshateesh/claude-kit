# Operability

A service is not done when it works. It is done when someone who did not write it
can deploy it, tell whether it is healthy, and turn it off safely.

## Liveness and readiness are different questions

- **Liveness** asks "is this process wedged". If it fails, the platform restarts the pod.
  It must not depend on the database, or a database blip restarts the whole fleet and turns
  a degradation into an outage.
- **Readiness** asks "should this instance receive traffic right now". It may check
  dependencies, and it must flip to unhealthy the moment shutdown begins.

Two endpoints, two meanings. Collapsing them into one is the most common mistake in this area.

## Shutdown has an order, and getting it wrong causes 502s on every deploy

On SIGTERM:

1. Fail readiness immediately, but **keep serving**.
2. Wait a few seconds for the load balancer to notice and stop sending new requests.
   Removing an endpoint is eventually consistent; the pod usually learns before the router does.
3. Stop accepting new connections, let in-flight requests finish.
4. Close the database pool and anything else with a socket.
5. Exit 0. Keep a hard timeout so a stuck request cannot block the deploy forever.

Exiting at step 1 is the bug. The pod disappears while traffic is still being routed to it,
and every rolling deploy produces a burst of errors that nobody can reproduce afterwards.

## Configuration

- Read config from the environment, validate it at boot, and **fail fast** with a message
  naming the missing variable. A service that starts and then fails on the first request
  has moved a deploy-time error to a customer-facing one.
- No secrets in the image, in the repo, or in logs. Injected at runtime.
- The same artifact runs in every environment. Only the config differs.

## Logs, metrics, traces

- Structured logs, one JSON object per line. A request id on every line, propagated from
  an inbound header if present so a trace survives a service hop.
- Never log a secret, a card number, a token, or a whole request body.
- The metrics worth having on day one are the RED set: rate, errors, and duration at a high
  percentile. Averages hide everything that matters.
- Alert on symptoms a user would feel, not on causes. High CPU is not an incident.
  Failed payments is an incident.

## Images

- Multi-stage build. Build dependencies do not ship.
- Pin the base image, run as a non-root user, and keep it minimal.
- `.dockerignore` at least as strict as `.gitignore`, or the build context carries
  `node_modules` and any local `.env` straight into the image.

## Schema migrations

- Expand and contract, never a rename in place. Add the new column, backfill, write to both,
  switch reads, then drop the old one in a later release.
- Every migration must be safe to run while the previous version of the code is still serving,
  because during a rolling deploy it will be.
- Nothing destructive in the same release as the code that stops using it.

## Pipelines

- The pipeline typechecks, tests, and builds the image. If those pass locally but not in CI,
  CI is right.
- A change to the pipeline is a change to production access. Review what permissions and
  secrets it gains.
