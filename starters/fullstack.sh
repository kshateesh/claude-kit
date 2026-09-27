#!/bin/bash
# fullstack.sh - React front end and an Express API in one repo.
#
# Two folders, web/ and api/, and a root package.json with no dependencies of
# its own. No monorepo tooling on purpose: a workspace manager is one more thing
# to explain and it buys nothing at this size.
#
# The front end talks to /api and Vite proxies that to the API in dev, so there
# is no CORS setup and no base-URL switching to get wrong.
#
#   ./starters/fullstack.sh my-app

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
APP="${1:-app}"
[ -e "$APP" ] && { echo "$APP already exists" >&2; exit 2; }

mkdir -p "$APP" && cd "$APP"

# Reuse the single-stack bootstraps so there is one definition of each toolchain.
"$HERE/frontend.sh" web >/dev/null
"$HERE/backend.sh"  api >/dev/null

# Point the dev server at the API. Everything under /api is proxied, so the
# browser only ever talks to one origin.
python3 - <<'PY'
import re, pathlib
p = pathlib.Path('web/vite.config.ts')
s = p.read_text()
s = s.replace(
    "  plugins: [react()],",
    "  plugins: [react()],\n"
    "  server: {\n"
    "    // Same-origin in dev: no CORS config, no base URL to switch per env.\n"
    "    proxy: { '/api': { target: 'http://localhost:3000', changeOrigin: true } },\n"
    "  },"
)
p.write_text(s)
PY

cat > package.json <<'JSON'
{
  "name": "app",
  "private": true,
  "type": "module",
  "scripts": {
    "dev:web": "npm --prefix web run dev",
    "dev:api": "npm --prefix api run dev",
    "test": "npm --prefix api test && npm --prefix web test",
    "typecheck": "npm --prefix api run typecheck && npm --prefix web run typecheck"
  }
}
JSON

cat > README.md <<'MD'
# app

| Folder | What |
|---|---|
| `web/` | React, TypeScript, Vite, Vitest, Testing Library |
| `api/` | Express, TypeScript, Vitest, supertest |

Two terminals:

```
npm run dev:api     # http://localhost:3000
npm run dev:web     # http://localhost:5173, proxies /api to the API
```

`npm test` runs both suites. `npm run typecheck` typechecks both.
MD

echo
echo "== proving both harnesses run =="
npm test
echo
"$KIT/install.sh" .
echo
echo "ready. Two terminals: 'npm run dev:api' and 'npm run dev:web'."
