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
- StrictMode double-invokes effects in development on purpose. If that breaks something,
  the effect is not idempotent or is not cleaning up. Fix the cleanup. Never remove StrictMode
  to silence it.

## React specifics worth getting right

- Key lists by a stable id. An index as a key breaks on reorder and delete, and the symptom is
  state appearing on the wrong row.
- Changing a `key` deliberately resets a component. Prefer `<Form key={recordId} />` over an
  effect that syncs props into state.
- `useState` is for values the user sees. `useRef` is for values the render does not depend on:
  a timeout handle, an abort controller, a request sequence number. Never read or write a ref
  during render.
- Uncontrolled inputs plus `FormData` at submit is the faster path when nothing outside the field
  needs the value as it is typed. Reach for controlled when it does.
- An error boundary catches errors during render, not in an event handler and not a rejected
  promise. Handle those where they happen.
- React 19: `ref` is a plain prop, so no `forwardRef`. `useActionState` removes the pending and
  error boilerplate around a form submit. Do not reach for `use` or Server Components in a
  Vite single-page app.

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
