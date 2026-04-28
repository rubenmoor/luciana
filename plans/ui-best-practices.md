# UI Best Practices

Status: reference

## Labelled form controls

Every visible-label control gets explicit `for` / `id` association — never the nested-input shorthand. Use human-readable, page-scoped ids (`login-email`, `signup-password-confirm`, `period-entry-start-date`); avoid generic (`email`, `input1`) or auto-generated ones. The `labelled` helper in `frontend/src/Frontend/Auth/Widget.hs` emits `<label for=...>` from its first argument; the caller must repeat the same id in the input's initial attributes — the helper can't reach inside the opaque inner widget, and keeping both ends visible at the call site is intentional.

## Enter-to-submit on forms

Pressing Enter in a text field must submit the form. This works automatically when (1) fields are wrapped in a `<form>`, (2) the form contains a `<button type="submit">`, and (3) the submit handler calls `preventDefault()` so the browser does not navigate. In Reflex-DOM: wrap the body in `el "form"`, capture the form element with `el'`, merge its `submit` event with the submit button's click, and prevent default in the handler. Users — especially on mobile — expect this; a `<button type="button">` next to bare inputs outside a `<form>` looks identical but breaks the expectation silently.
