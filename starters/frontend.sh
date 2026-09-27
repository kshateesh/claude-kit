#!/bin/bash
# frontend.sh - React + TypeScript + Vitest + Testing Library.
#
# This is a toolchain, not a template. It scaffolds with the official Vite
# starter, wires the test harness, and leaves exactly one smoke test behind to
# prove the suite runs. Delete src/Hello.* in your first minute.
#
# Deliberately absent: router, state library, component library, CSS framework,
# auth, Docker. Add what the problem needs, so every dependency has a reason you
# can give out loud.
#
#   ./starters/frontend.sh my-app

set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-app}"
[ -e "$APP" ] && { echo "$APP already exists" >&2; exit 2; }

npm create vite@latest "$APP" -- --template react-ts >/dev/null
cd "$APP"
npm i --silent

# @testing-library/dom is a PEER dependency of React Testing Library from v16.
# Leave it out and screen breaks at runtime with a confusing error.
npm i -D --silent vitest jsdom @testing-library/react @testing-library/dom \
  @testing-library/user-event @testing-library/jest-dom

cat > vite.config.ts <<'CONF'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    // Keep globals on. Testing Library registers its between-test cleanup by
    // hooking the global afterEach; with globals off it never registers, and
    // the second test querying the same element fails with "found multiple".
    globals: true,
    setupFiles: './src/setupTests.ts',
  },
})
CONF

# The /vitest entry point, not the bare package. It extends Vitest's expect.
echo "import '@testing-library/jest-dom/vitest'" > src/setupTests.ts

cat > src/Hello.tsx <<'TSX'
export default function Hello({ name }: { name: string }) {
  return <h1>Hello, {name}</h1>
}
TSX

cat > src/Hello.test.tsx <<'TSX'
import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import Hello from './Hello'

describe('Hello', () => {
  it('renders the name', () => {
    render(<Hello name="Pune" />)
    expect(screen.getByRole('heading', { name: /hello, pune/i })).toBeInTheDocument()
  })
})
TSX

npm pkg set scripts.test="vitest run" scripts."test:watch"="vitest" scripts.typecheck="tsc --noEmit"

echo
echo "== proving the harness runs =="
npm test
echo
"$KIT/install.sh" .
echo
echo "ready. 'npm run dev' to start, 'npm test' to check. Delete src/Hello.* when you begin."
