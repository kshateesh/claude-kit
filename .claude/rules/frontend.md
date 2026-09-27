# Front end

## Before writing a component

1. Name its one job in a sentence. If it takes two, it is two components.
2. Decide what it owns and what it receives. Default to receiving.
3. Write the contract first: props in, events out.
4. List the states before the markup: loading, empty, error, partial, success, disabled. The list is the design.
5. Decide the keyboard and the accessible role now. Retrofitting means rewriting the markup.

## Where state lives

- Local if only this component reads it.
- Lifted to the nearest common parent if two siblings need it.
- In the URL if the user would bookmark, share, or refresh into it. Filters, tabs, pagination, selection.
- Context only for ambient, rarely changing values. Memoise the provider value.
- A store only when many unrelated parts read and write the same client state.
- Server data is a cache, not state. Key it by request, dedupe in flight, invalidate after a mutation.

## Effects

- An effect synchronises with something outside the component. It is not a watcher.
- If it only derives state from other state, delete it and compute during render.
- If it responds to a user action, it belongs in the event handler.
- Anything an effect starts, it cleans up. Timers, subscriptions, in-flight requests.

## Always build these

- Loading, empty with a next action, and error with a working retry.
- Submit disabled while pending, so a slow network cannot create two records.
- Debounced input, and discard responses for a query the user has moved on from.

## Testing

- Query by role, then label, then text. A test id is a last resort and a finding.
- Test behaviour through the DOM, not implementation. Renaming a state variable must not break a test.
- Fake timers: `vi.useFakeTimers({ shouldAdvanceTime: true })` with a plain `userEvent.setup()`.
  Passing `advanceTimers` to `setup()` alongside `useFakeTimers()` hangs.
- Keep `globals: true` in the Vitest config, or Testing Library never registers its cleanup
  and the second test that queries the same element fails with "found multiple elements".

## Accessibility

- Real elements before ARIA. A `button` before a `div` with a click handler.
- A combobox needs `aria-activedescendant` on the input, or the roles are decoration.
- Errors announced, labels tied to inputs, never colour alone to signal state.
