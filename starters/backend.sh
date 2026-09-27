#!/bin/bash
# backend.sh - Express + TypeScript + Vitest + supertest.
#
# Express over Nest or similar on purpose: in a time-boxed build the framework's
# own boilerplate is code you did not write and will be asked to explain.
# Fastify is a fine swap if you prefer its schema validation.
#
# The app is exported as a factory rather than a module that listens, so every
# test gets a clean instance and nothing binds a port.
#
#   ./starters/backend.sh my-api

set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-api}"
[ -e "$APP" ] && { echo "$APP already exists" >&2; exit 2; }

mkdir -p "$APP/src" && cd "$APP"
npm init -y >/dev/null
npm pkg set type="module"
npm i --silent express
npm i -D --silent vitest supertest typescript tsx @types/express @types/supertest @types/node

cat > tsconfig.json <<'CONF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["node"]
  },
  "include": ["src"]
}
CONF

cat > src/app.ts <<'TS'
import express from 'express'

/**
 * Exported as a factory, not a listening server: each test gets a clean
 * instance and nothing binds a port.
 */
export function createApp() {
  const app = express()
  app.use(express.json())

  app.get('/health', (_req, res) => res.json({ status: 'ok' }))

  return app
}
TS

cat > src/server.ts <<'TS'
import { createApp } from './app.js'

const port = Number(process.env.PORT ?? 3000)
createApp().listen(port, () => console.log(`listening on ${port}`))
TS

cat > src/app.test.ts <<'TS'
import request from 'supertest'
import { describe, it, expect } from 'vitest'
import { createApp } from './app.js'

describe('GET /health', () => {
  it('reports ok', async () => {
    const res = await request(createApp()).get('/health')
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ status: 'ok' })
  })
})
TS

npm pkg set scripts.dev="tsx watch src/server.ts" scripts.test="vitest run" \
  scripts."test:watch"="vitest" scripts.typecheck="tsc --noEmit"

echo
echo "== proving the harness runs =="
npm test
echo
"$KIT/install.sh" .
echo
echo "ready. 'npm run dev' to start, 'npm test' to check."
