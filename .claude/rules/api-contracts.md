# API contracts

## Response shape

- Stable across every code path, errors included.
- One error envelope with defined codes. Do not invent a second shape for a new endpoint.
- Never return `undefined`, `NaN`, `"NA"`, or `"Infinity"`. Use `null` deliberately and say it can happen.

## Validation

- Validate at the boundary, once. Reject unknown fields rather than ignoring them.
- Reject deterministically, using the same error shape.

## Pagination

- Keyset over offset once the table is real. Offset walks the skipped rows and can repeat or skip
  records when data changes between pages.
- The sort key must be unique, or add a tiebreaker. Paginating on a timestamp alone breaks on a tie.
- Cursors are opaque, so the strategy can change without breaking clients.
- Cap the page size. An unbounded limit is a denial of service a well-meaning client will find.
- Allowlist sortable and filterable fields. Interpolating a column name from a query string is an injection.

## Change classification

State which one every change is:

- **Additive**: new endpoint, new optional field, new enum value a client may ignore.
- **Breaking**: removal, rename, type change, newly required field, tightened validation,
  changed default, changed error code.

A breaking change needs a version, a deprecation window, and a migration note.
Assume someone has hardcoded the current shape.
