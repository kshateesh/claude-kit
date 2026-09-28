#!/bin/bash
# backend-ops.sh - Express API that is actually operable.
#
# Everything backend.sh gives you, plus the things a platform engineer looks for:
# separate liveness and readiness, a correct shutdown sequence, config validated
# at boot, structured logs with a request id, a multi-stage image, a CI workflow
# and a Kubernetes manifest whose probe timings match the application's.
#
# The readiness behaviour is tested, not asserted. That is the point: "readiness
# flips before the drain" is a claim until there is a test for it.
#
#   ./starters/backend-ops.sh my-api

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
APP="${1:-api}"
[ -e "$APP" ] && { echo "$APP already exists" >&2; exit 2; }

"$HERE/backend.sh" "$APP" >/dev/null
cd "$APP"

# NodeNext so tsc emits runnable output for the production image stage.
cat > tsconfig.json <<'CONF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["src"],
  "exclude": ["src/**/*.test.ts"]
}
CONF

cat > src/config.ts <<'CONF'
/**
 * Config is read and validated once, at boot. A service that starts and then
 * fails on the first request has turned a deploy-time error into a customer one.
 */
export type Config = { port: number; logLevel: string; shutdownGraceMs: number }

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const problems: string[] = []

  const port = Number(env.PORT ?? 3000)
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    problems.push(`PORT must be an integer between 1 and 65535, got "${env.PORT}"`)
  }

  const logLevel = env.LOG_LEVEL ?? 'info'
  if (!['debug', 'info', 'warn', 'error'].includes(logLevel)) {
    problems.push(`LOG_LEVEL must be debug|info|warn|error, got "${logLevel}"`)
  }

  const shutdownGraceMs = Number(env.SHUTDOWN_GRACE_MS ?? 5000)
  if (!Number.isInteger(shutdownGraceMs) || shutdownGraceMs < 0) {
    problems.push(`SHUTDOWN_GRACE_MS must be a non-negative integer`)
  }

  // Fail with every problem at once. Fixing one variable per restart is miserable.
  if (problems.length) throw new Error(`Invalid configuration:\n  - ${problems.join('\n  - ')}`)
  return { port, logLevel, shutdownGraceMs }
}
CONF

cat > src/logger.ts <<'LOG'
/**
 * One JSON object per line. Machines parse it, humans grep it, and a request id
 * on every line means a single request can be reassembled after the fact.
 *
 * Never log a secret, a token, a card number, or a whole request body.
 */
export type Log = (level: string, msg: string, fields?: Record<string, unknown>) => void

export function createLogger(stream: { write(s: string): void } = process.stdout): Log {
  return (level, msg, fields = {}) => {
    stream.write(JSON.stringify({ ts: new Date().toISOString(), level, msg, ...fields }) + '\n')
  }
}
LOG

cat > src/lifecycle.ts <<'LIFE'
/**
 * Readiness state, kept out of the HTTP layer so it can be tested directly.
 *
 * Liveness answers "is this process wedged" and must not depend on the database,
 * or one database blip restarts the entire fleet. Readiness answers "should this
 * instance receive traffic", and goes false the instant shutdown begins.
 */
export class Lifecycle {
  #shuttingDown = false
  get isShuttingDown() { return this.#shuttingDown }
  /** Ready to receive traffic. False from the first moment of shutdown. */
  get isReady() { return !this.#shuttingDown }
  beginShutdown() { this.#shuttingDown = true }
}
LIFE

cat > src/app.ts <<'APP'
import express from 'express'
import { randomUUID } from 'node:crypto'
import { Lifecycle } from './lifecycle.js'
import { createLogger, type Log } from './logger.js'

export function createApp(lifecycle = new Lifecycle(), log: Log = createLogger()) {
  const app = express()
  app.use(express.json())

  // Propagate an inbound request id so a trace survives a service hop.
  app.use((req, res, next) => {
    const id = (req.header('x-request-id') ?? randomUUID()).slice(0, 128)
    res.setHeader('x-request-id', id)
    res.locals.requestId = id
    next()
  })

  // Liveness: is the process wedged. No dependency checks on purpose.
  app.get('/health', (_req, res) => res.json({ status: 'ok' }))

  // Readiness: should this instance receive traffic. 503 while draining, so the
  // load balancer stops routing here before the process stops answering.
  app.get('/ready', (_req, res) => {
    if (!lifecycle.isReady) return res.status(503).json({ status: 'shutting_down' })
    return res.json({ status: 'ready' })
  })

  app.get('/items', (_req, res) => res.json({ items: [] }))

  app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    log('error', 'unhandled', { error: err.message, requestId: res.locals.requestId })
    res.status(500).json({ error: 'internal_error' })
  })

  return app
}
APP

cat > src/server.ts <<'SRV'
import { loadConfig } from './config.js'
import { createApp } from './app.js'
import { Lifecycle } from './lifecycle.js'
import { createLogger } from './logger.js'

const log = createLogger()
const config = loadConfig()          // throws and exits non-zero on bad config
const lifecycle = new Lifecycle()
const server = createApp(lifecycle, log).listen(config.port, () =>
  log('info', 'listening', { port: config.port }))

/**
 * Shutdown order matters. Exiting at step 1 is what produces a burst of 502s on
 * every rolling deploy: the pod stops answering while the router is still
 * sending it traffic, because endpoint removal is eventually consistent.
 */
async function shutdown(signal: string) {
  log('info', 'shutdown_begin', { signal })

  lifecycle.beginShutdown()                                   // 1. fail readiness, keep serving
  await new Promise(r => setTimeout(r, config.shutdownGraceMs)) // 2. let the router notice

  const forced = setTimeout(() => {                           // hard stop, never block a deploy
    log('warn', 'shutdown_forced')
    process.exit(1)
  }, 10_000)
  forced.unref()

  server.close(() => {                                        // 3. drain in-flight requests
    log('info', 'shutdown_complete')                          // 4. close pools here in a real service
    process.exit(0)
  })
}

process.on('SIGTERM', () => void shutdown('SIGTERM'))
process.on('SIGINT', () => void shutdown('SIGINT'))
SRV

cat > src/ops.test.ts <<'TEST'
import request from 'supertest'
import { describe, it, expect } from 'vitest'
import { createApp } from './app.js'
import { Lifecycle } from './lifecycle.js'
import { loadConfig } from './config.js'
import { createLogger } from './logger.js'

describe('liveness and readiness are different questions', () => {
  it('both pass while healthy', async () => {
    const app = createApp(new Lifecycle())
    expect((await request(app).get('/health')).status).toBe(200)
    expect((await request(app).get('/ready')).status).toBe(200)
  })

  it('readiness fails during shutdown while liveness still passes', async () => {
    const lifecycle = new Lifecycle()
    const app = createApp(lifecycle)

    lifecycle.beginShutdown()

    // 503 tells the load balancer to stop routing here.
    const ready = await request(app).get('/ready')
    expect(ready.status).toBe(503)
    expect(ready.body).toEqual({ status: 'shutting_down' })

    // Liveness must stay green, or the platform kills the pod mid-drain.
    expect((await request(app).get('/health')).status).toBe(200)
  })

  it('keeps serving real traffic during the drain window', async () => {
    const lifecycle = new Lifecycle()
    const app = createApp(lifecycle)
    lifecycle.beginShutdown()
    expect((await request(app).get('/items')).status).toBe(200)
  })
})

describe('request id', () => {
  it('echoes an inbound id so a trace survives the hop', async () => {
    const res = await request(createApp()).get('/health').set('x-request-id', 'abc-123')
    expect(res.headers['x-request-id']).toBe('abc-123')
  })

  it('generates one when absent', async () => {
    const res = await request(createApp()).get('/health')
    expect(res.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/)
  })
})

describe('config is validated at boot', () => {
  it('rejects a bad port and names the variable', () => {
    expect(() => loadConfig({ PORT: 'not-a-port' })).toThrow(/PORT/)
  })

  it('reports every problem at once', () => {
    try {
      loadConfig({ PORT: '0', LOG_LEVEL: 'shout' })
      throw new Error('should have thrown')
    } catch (e) {
      expect((e as Error).message).toMatch(/PORT/)
      expect((e as Error).message).toMatch(/LOG_LEVEL/)
    }
  })

  it('applies defaults when the environment is empty', () => {
    expect(loadConfig({})).toEqual({ port: 3000, logLevel: 'info', shutdownGraceMs: 5000 })
  })
})

describe('logs are structured', () => {
  it('writes one parseable JSON object per line', () => {
    const lines: string[] = []
    const log = createLogger({ write: (s: string) => { lines.push(s) } })
    log('info', 'payment_succeeded', { paymentId: 'pay_1' })
    expect(lines).toHaveLength(1)
    const parsed = JSON.parse(lines[0]!)
    expect(parsed).toMatchObject({ level: 'info', msg: 'payment_succeeded', paymentId: 'pay_1' })
    expect(typeof parsed.ts).toBe('string')
  })
})
TEST

cat > Dockerfile <<'DOCK'
# Multi-stage: build dependencies do not ship. Base image pinned, not :latest.
FROM node:22.20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22.20-alpine AS run
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist

# node:alpine ships an unprivileged `node` user. Use it.
USER node
EXPOSE 3000

# Kubernetes uses the probes in deploy/deployment.yaml; this is for a plain
# `docker run`, so the two ways of running it behave the same.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Exec form, so the process is PID 1 and receives SIGTERM directly. The shell
# form would swallow it and every shutdown would be a 10 second kill.
CMD ["node", "dist/server.js"]
DOCK

cat > .dockerignore <<'IGN'
node_modules
dist
.git
.env
.env.*
*.log
.claude
IGN

mkdir -p deploy .github/workflows

cat > deploy/deployment.yaml <<'K8S'
# The probe timings and the grace period are matched to the application on
# purpose. If terminationGracePeriodSeconds is shorter than the app's own drain,
# Kubernetes sends SIGKILL mid-request and the drain never completes.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0        # never go below capacity during a deploy
      maxSurge: 1
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      # App drains for SHUTDOWN_GRACE_MS (5s) then closes connections.
      # This must be comfortably longer than that.
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: api
          image: api:0.1.0          # a tag, never :latest, so a rollback is a real thing
          ports: [{ containerPort: 3000 }]
          env:
            - name: PORT
              value: "3000"
            - name: SHUTDOWN_GRACE_MS
              value: "5000"
          # Liveness must not check the database. If it did, one database blip
          # would restart every pod at once and turn a degradation into an outage.
          livenessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
          # Readiness may check dependencies, and goes 503 the moment shutdown starts.
          readinessProbe:
            httpGet: { path: /ready, port: 3000 }
            periodSeconds: 5
            failureThreshold: 2
          resources:
            requests: { cpu: 50m, memory: 128Mi }
            limits:   { memory: 256Mi }   # no CPU limit on purpose: throttling a
                                          # latency-sensitive service hurts p99
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
K8S

cat > .github/workflows/ci.yml <<'CI'
name: ci
on:
  push: { branches: [main] }
  pull_request:

# Least privilege by default. Add a scope only where a job proves it needs one.
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: npm
      - run: npm ci
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
      # The image builds in CI so a broken Dockerfile fails here rather than at
      # deploy time. No push: publishing is a separate job with its own secrets.
      - run: docker build -t api:${{ github.sha }} .
CI

npm pkg set scripts.build="tsc"

echo
echo "== typecheck =="
npm run typecheck
echo
echo "== proving the harness runs =="
npm test
echo
echo "== proving the build emits runnable output =="
npm run build && node -e "import('./dist/app.js').then(m => { if (typeof m.createApp !== 'function') throw new Error('createApp missing'); console.log('dist/app.js loads, createApp exported'); })"
echo
"$KIT/install.sh" .
echo
echo "ready. /health is liveness, /ready is readiness, SIGTERM drains before it exits."
