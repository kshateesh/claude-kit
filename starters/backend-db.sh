#!/bin/bash
# backend-db.sh - Express API with a persistence seam.
#
# The point of this one is the seam, not the database. A repository interface
# with an in-memory implementation keeps the logic testable inside a short
# build, and the SQLite implementation proves the seam is real rather than
# theoretical. One contract test runs against both, so neither can drift.
#
# SQLite via node:sqlite, which is built into Node 22.5 and later: no native
# build step, no daemon, no Docker. The suite detects it at runtime and skips
# that half on an older Node rather than failing.
#
# Reach for Postgres only when the task actually needs it. Twenty minutes of
# Docker is twenty minutes not spent on the problem.
#
#   ./starters/backend-db.sh my-api

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
APP="${1:-api}"
[ -e "$APP" ] && { echo "$APP already exists" >&2; exit 2; }

"$HERE/backend.sh" "$APP" >/dev/null
cd "$APP"

cat > src/repository.ts <<'TS'
export type Item = { id: string; name: string; amountMinor: number }

/**
 * The seam. Business logic depends on this, never on a driver.
 * Swapping the implementation must not change a single test in app.test.ts.
 */
export interface ItemRepository {
  add(item: Item): void
  get(id: string): Item | undefined
  list(): Item[]
}

export class InMemoryItemRepository implements ItemRepository {
  #items = new Map<string, Item>()
  add(item: Item) { this.#items.set(item.id, item) }
  get(id: string) { return this.#items.get(id) }
  list() { return [...this.#items.values()] }
}
TS

cat > src/repository.sqlite.ts <<'TS'
import { DatabaseSync } from 'node:sqlite'
import type { Item, ItemRepository } from './repository.js'

/**
 * amount_minor is an INTEGER. Money is never stored as a float, in any engine.
 */
export class SqliteItemRepository implements ItemRepository {
  #db: DatabaseSync
  constructor(path = ':memory:') {
    this.#db = new DatabaseSync(path)
    this.#db.exec(`
      CREATE TABLE IF NOT EXISTS items (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        amount_minor INTEGER NOT NULL
      )
    `)
  }
  add(item: Item) {
    this.#db
      .prepare('INSERT OR REPLACE INTO items (id, name, amount_minor) VALUES (?, ?, ?)')
      .run(item.id, item.name, item.amountMinor)
  }
  get(id: string): Item | undefined {
    const row = this.#db.prepare('SELECT * FROM items WHERE id = ?').get(id) as
      | { id: string; name: string; amount_minor: number }
      | undefined
    return row && { id: row.id, name: row.name, amountMinor: row.amount_minor }
  }
  list(): Item[] {
    const rows = this.#db.prepare('SELECT * FROM items ORDER BY id').all() as
      { id: string; name: string; amount_minor: number }[]
    return rows.map(r => ({ id: r.id, name: r.name, amountMinor: r.amount_minor }))
  }
}
TS

cat > src/repository.test.ts <<'TS'
import { describe, it, expect } from 'vitest'
import { InMemoryItemRepository, type ItemRepository } from './repository.js'

let hasSqlite = true
try { await import('node:sqlite') } catch { hasSqlite = false }

/**
 * One contract, run against every implementation. This is what stops the
 * in-memory version and the real one from quietly diverging.
 */
function contract(name: string, make: () => ItemRepository) {
  describe(name, () => {
    it('round-trips an item', () => {
      const repo = make()
      repo.add({ id: 'i1', name: 'Water bill', amountMinor: 12500 })
      expect(repo.get('i1')).toEqual({ id: 'i1', name: 'Water bill', amountMinor: 12500 })
    })

    it('returns undefined for an unknown id rather than throwing', () => {
      expect(make().get('nope')).toBeUndefined()
    })

    it('keeps the amount an integer in minor units', () => {
      const repo = make()
      repo.add({ id: 'i2', name: 'Permit', amountMinor: 999 })
      expect(Number.isInteger(repo.get('i2')!.amountMinor)).toBe(true)
    })

    it('lists what was added', () => {
      const repo = make()
      repo.add({ id: 'a', name: 'one', amountMinor: 1 })
      repo.add({ id: 'b', name: 'two', amountMinor: 2 })
      expect(repo.list().map(i => i.id).sort()).toEqual(['a', 'b'])
    })
  })
}

contract('InMemoryItemRepository', () => new InMemoryItemRepository())

describe.skipIf(!hasSqlite)('SqliteItemRepository', async () => {
  const { SqliteItemRepository } = await import('./repository.sqlite.js')
  contract('SqliteItemRepository', () => new SqliteItemRepository(':memory:'))
})
TS

echo
echo "== proving the harness runs, both implementations =="
npm test
echo
"$KIT/install.sh" .
echo
echo "ready. The seam is src/repository.ts. Swap the implementation, not the tests."
