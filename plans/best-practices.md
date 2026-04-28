# Best Practices

General conventions that apply across the codebase, independent of any
specific feature. These rules should be followed by default; deviations need
a justification recorded in the relevant feature plan.

## Labelled form controls

Every form control that has a visible label MUST be associated with that
label via the `for=` / `id=` pair. Implicit association (input nested inside
the `<label>`) is not used here; we always go explicit so the structure
survives layout/styling changes.

**Id convention:** human-readable and expressive, scoped to the page. The id
should read as documentation at the call site — a stranger glancing at the
DOM should know what the field is.

Examples:

- `login-email`, `login-password`
- `signup-email`, `signup-password`, `signup-password-confirm`
- `period-entry-start-date`, `period-entry-flow`

Avoid:

- Generic ids like `email`, `password`, `input1` — collide across pages and
  carry no meaning.
- Auto-generated ids (counters, UUIDs) — they're invisible at the call site,
  noisy in the DOM, and break test selectors on every render.

**Helper contract:** the `labelled` helper in
`frontend/src/Frontend/Auth/Widget.hs` takes the id as its first argument and
emits `<label for=...>`. The caller is responsible for putting the matching
`"id" =: fieldId` on the inner `inputElement`'s initial attributes — the
helper cannot enforce this because the inner widget is opaque.

```haskell
emailIn <- labelled "login-email" "Email" $ inputElement $ def
  & inputElementConfig_elementConfig . elementConfig_initialAttributes
    .~ ("type" =: "email" <> "id" =: "login-email" <> ...)
```

The id literal appears twice (once in `labelled`, once in the input's
attributes). That duplication is intentional: it keeps both ends visible at
the call site.

## Enter-to-submit on forms

Pressing Enter while focused on any text field in a form MUST submit that
form. This is HTML's **implicit submission** behaviour and comes for free
when three conditions are met:

1. The fields are wrapped in a `<form>` element.
2. The form contains a submit button — i.e. `<button type="submit">` (or
   `<button>` with no `type`, since submit is the default inside a form).
3. The form's `submit` event handler calls `preventDefault()` so the browser
   doesn't perform a full-page navigation.

The "default button" is the first submit button in tree order; that is the
button activated by Enter. If a form has no submit button at all but exactly
one single-line text input, Enter still submits — but don't rely on that
edge case, just always include a submit button.

**Reflex-DOM mapping:** wrap the widget body in `el "form" $ do ...`,
capture the form element with `el'` so the `submit` event can be observed,
and merge it with the click event of the submit button. The handler must
prevent default. The button's `type` attribute should be `"submit"`, not
`"button"`.

**Why this matters:** users — especially mobile users — expect the keyboard's
"Go"/"Done"/"return" key to commit the form. A `<button type="button">`
sitting next to bare `<input>` elements outside a `<form>` looks identical
visually but breaks this expectation silently.
