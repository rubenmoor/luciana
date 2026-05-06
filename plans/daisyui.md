# daisyUI integration

Status: reference

Add the [daisyUI](https://daisyui.com) Tailwind plugin and apply its component
classes to the existing UI (top bar, login/signup forms, placeholder pages) so
the app renders with a coherent default look immediately after this plan is
implemented — no further design work required.

Stack note: we are on Tailwind v4 via the standalone Tailwind CLI described in
[`tailwind.md`](tailwind.md). daisyUI 5 is the version that supports Tailwind
v4 via the `@plugin` CSS directive — *not* the legacy
`plugins: [require('daisyui')]` JS config style (which only works with
Tailwind v3).

## Approach for the build

The Nix derivation in `static/default.nix` runs the standalone Tailwind CLI
fetched from upstream GitHub releases. It does not call `npm install`, and Nix
builds are sandboxed (no network), so daisyUI is fetched separately as a
fixed-output npm tarball.

We will fetch the daisyUI npm tarball with `pkgs.fetchurl` (deterministic via
sha256), extract it into a `node_modules/daisyui` directory inside the build
sandbox, and reference it from CSS via `@plugin "daisyui";`. Tailwind v4
resolves `@plugin` names through `node_modules` relative to the CSS input file,
so this Just Works without npm itself.

There is no `static/src/package.json` in the current build path; the Nix
derivation is the source of truth for Tailwind and daisyUI versions.

## Files to modify

### `static/default.nix`

Add the daisyUI tarball as a fixed-output fetch, extract it into a
`node_modules/daisyui` sibling of the CSS, then run `tailwindcss` as before.

See [`tailwind.md`](tailwind.md) for the complete derivation. The daisyUI part
is:

```nix
daisyuiVersion = "5.5.19";
daisyuiTarball = pkgs.fetchurl {
  url = "https://registry.npmjs.org/daisyui/-/daisyui-${daisyuiVersion}.tgz";
  sha256 = "1y2sdyn393d5b2gwm5krs6vc1g9y5ac3fzy5xkad4w87cv0547k0";
};
```

and the install phase extracts it into `node_modules/daisyui` before running
`./tailwindcss -i css/styles.css -o $out/styles.css`.

### `static/src/css/styles.css`

Replace the single `@import` line with the import + plugin block:

```css
@import "tailwindcss";

@plugin "daisyui" {
  themes: light --default, dark --prefersdark;
}
```

Theme choice rationale: shipping `light` as default + `dark` triggered by the
OS `prefers-color-scheme: dark` media query gives automatic dark mode with no
user-facing toggle to design yet. Both are first-party daisyUI themes so the
component classes look correct out of the box.

## Files to modify — frontend UI

The goal of the frontend changes is "immediately usable default style". We
keep the changes minimal: apply daisyUI component classes at the existing
seams; do not refactor structure.

### `frontend/src/Frontend.hs`

1. **Page wrapper for routed content.** Introduce a small helper in this file:
   ```haskell
   page :: DomBuilder t m => Text -> m a -> m a
   page title inner = elAttr "main" ("class" =: "container mx-auto p-6") $ do
     elAttr "h1" ("class" =: "text-3xl font-bold mb-4") $ text title
     inner
   ```
   Replace the existing `placeholder name = el "h1" $ text $ name <> " (TODO)"`
   with `placeholder name = page name $ text "TODO"`.

2. **`topBar`.** Replace the current bare `<header><span>…</span><button>…</button></header>`
   with a daisyUI navbar:
   ```haskell
   elAttr "div" ("class" =: "navbar bg-base-200 shadow-sm") $ do
     elAttr "div" ("class" =: "flex-1 px-2 text-lg font-semibold") $ text "Luciana"
     elAttr "div" ("class" =: "flex-none gap-2") $ do
       elAttr "span" ("class" =: "text-sm opacity-70") $ text (urEmail u)
       buttonClass "btn btn-sm btn-ghost" "Log out"
   ```
   `buttonClass` is a tiny helper added in this file (Reflex's `button` does
   not accept attributes):
   ```haskell
   buttonClass
     :: DomBuilder t m => Text -> Text -> m (Event t ())
   buttonClass cls label = do
     (e, _) <- elAttr' "button"
       ("type" =: "button" <> "class" =: cls)
       (text label)
     pure $ domEvent Click e
   ```
   Imports to add: `elAttr'`, `domEvent`, and the `Click` constructor (from
   `Reflex.Dom.Core`).

3. **`loginPage` / `signupPage`.** Wrap their bodies in a centered card:
   ```haskell
   elAttr "div" ("class" =: "min-h-[calc(100vh-4rem)] flex items-center justify-center p-6") $
     elAttr "div" ("class" =: "card w-full max-w-sm bg-base-100 shadow-md") $
       elAttr "div" ("class" =: "card-body") $ do
         <existing widget call>
   ```
   The page handlers themselves don't change otherwise — they still call
   `loginWidget` / `signupWidget` and wire the events the same way.

### `frontend/src/Frontend/Widget/Form.hs`

1. **Headings.** `el "h1"` → `elAttr "h1" ("class" =: "card-title text-2xl mb-2")`.

2. **`labelled` helper.** Restructure to emit daisyUI's `form-control` /
   `label` / `label-text` structure. The signature also takes a caller-supplied
   id so the `<label>` is associated with its input via `for=` — see
   [ui-best-practices.md](ui-best-practices.md#labelled-form-controls):
   ```haskell
   labelled fieldId lbl inner = elAttr "div" ("class" =: "form-control w-full mb-2") $ do
     elAttr "label" ("class" =: "label" <> "for" =: fieldId) $
       elAttr "span" ("class" =: "label-text") $ text lbl
     inner
   ```

3. **Inputs.** Add `class` to each `inputElement`'s initial attributes:
   ```haskell
   "type" =: "email" <> "autocomplete" =: "email"
     <> "class" =: "input input-bordered w-full"
   ```
   Same for the password inputs (`"class" =: "input input-bordered w-full"`).

4. **Form wrapper + submit button.** The fields and submit button are
   wrapped in a `<form>` via the `formEl` helper, which sets
   `preventDefault` on the submit event so the browser does not navigate.
   The submit button is rendered with `submitButtonClass` (emits
   `type="submit"`) — no separate click event is captured because the form's
   submit event covers both Enter-to-submit and click. See
   [ui-best-practices.md](ui-best-practices.md#enter-to-submit-on-forms).

5. **Error line.** `el "p"` → `elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]")`.
   The `min-h` keeps the layout from jumping when an error appears.

## Where button helpers live

- `Frontend.hs` keeps `buttonClass` (`type="button"`) for navbar / non-form
  buttons (e.g. "Log out").
- `Frontend.Widget.Form` has `submitButtonClass` (`type="submit"`) for
  buttons inside a `<form>`. The two helpers are intentionally separate
  because the button `type` carries semantics: `"submit"` triggers form
  submission (and Enter-to-submit), `"button"` does not.

If a third call site appears for either helper, lift it to a shared module
(`Frontend/UI.hs`). Until then, the duplication is cheaper than the module.

## Verification

1. `nix-prefetch-url https://registry.npmjs.org/daisyui/-/daisyui-5.5.19.tgz`
   to obtain the sha256; paste into `static/default.nix`.
2. `ob run`. Watch for "Static assets being built…" then the dev server boot
   line.
3. `cat static.out/styles.css | grep -c '\.btn'` — confirms daisyUI's
   component CSS is in the bundle (non-zero hit).
4. Browser smoke test:
   - `/login` shows a centered card with bordered email/password inputs and a
     primary-coloured "Sign in" button.
   - `/signup` looks the same with "Create account".
   - After login, the navbar shows "Luciana" + email + a ghost "Log out" button
     on a `bg-base-200` strip.
   - Placeholder routes (`/`, `/calendar`, `/history`, `/settings`) render a
     centered container with a large bold title and "TODO".
   - Toggling OS dark mode flips colours without reload (CSS-only via
     `prefers-color-scheme`).
5. `nix-build -A ghcjs.frontend --no-out-link` to confirm no GHCJS regressions
   from the new imports / helpers.

## Out of scope

- Theme picker UI (multi-theme switching). One theme each for light / dark is
  enough for now.
- Custom theme tokens / brand colour. Switch from `light` / `dark` to a custom
  daisyUI theme later when there is a brand decision to encode.
- npm-based local dev workflow (`package-lock.json`, `node_modules/` checked
  in or generated outside Nix). The Nix derivation remains the only build
  path.
- Component coverage beyond what is currently rendered. Future routes
  (Calendar, History, Settings) get styled when their content lands.
- Form validation styling (`input-error`, inline field errors). The current
  widget only surfaces a single bottom-of-form error string; that is enough
  for now.
