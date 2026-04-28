# daisyUI integration

Add the [daisyUI](https://daisyui.com) Tailwind plugin and apply its component
classes to the existing UI (top bar, login/signup forms, placeholder pages) so
the app renders with a coherent default look immediately after this plan is
implemented — no further design work required.

Stack note: we are on Tailwind v4 (`tailwindcss ^4.1.13`, see
`static/src/package.json`). daisyUI 5 is the version that supports Tailwind v4
via the `@plugin` CSS directive — *not* the legacy `plugins: [require('daisyui')]`
JS config style (which only works with Tailwind v3).

## Approach for the build

The Nix derivation in `static/default.nix` runs the `tailwindcss` CLI from
nixpkgs. It does not currently call `npm install`, and Nix builds are
sandboxed (no network), so we cannot just add `daisyui` to `package.json` and
expect it to resolve.

We will fetch the daisyUI npm tarball with `pkgs.fetchurl` (deterministic via
sha256), extract it into a `node_modules/daisyui` directory inside the build
sandbox, and reference it from CSS via `@plugin "daisyui";`. Tailwind v4
resolves `@plugin` names through `node_modules` relative to the CSS input file,
so this Just Works without npm itself.

`package.json` stays as a manifest only — it is never used to drive an install
in the build. We update it for human reference / future npm-based tooling.

## Files to modify

### `static/default.nix`

Add the daisyUI tarball as a fixed-output fetch, extract it into a
`node_modules/daisyui` sibling of the CSS, then run `tailwindcss` as before.

```nix
{ pkgs ? (import ../.obelisk/impl {}).nixpkgs }:
let
  nixpkgs = import ./src/nixpkgs.nix {};
  frontendSrcFiles = ../frontend;

  daisyuiVersion = "5.0.0";   # final value: latest stable 5.x at implementation time
  daisyuiTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/daisyui/-/daisyui-${daisyuiVersion}.tgz";
    sha256 = "";              # fill in via `nix-prefetch-url <url>` at implementation time
  };
in pkgs.stdenv.mkDerivation {
  name = "static";
  src = ./src;
  buildInputs = [ pkgs.nodejs nixpkgs.tailwindcss_4 ];
  installPhase = ''
    mkdir -p $out/images
    mkdir -p node_modules/daisyui
    tar -xzf ${daisyuiTarball} -C node_modules/daisyui --strip-components=1

    ln -s ${frontendSrcFiles} frontend

    tailwindcss -i css/styles.css -o $out/styles.css

    cp lib.js $out/lib.js
    cp -r images/* $out/images/ 2>/dev/null || true
  '';
}
```

Implementation note: the sha256 is filled in by running
`nix-prefetch-url https://registry.npmjs.org/daisyui/-/daisyui-<v>.tgz`
once and pasting the output. If the version changes later, re-prefetch.

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

### `static/src/package.json`

Add daisyUI for documentation / future tooling consistency:

```json
{
  "name": "styles",
  "version": "0.0.0",
  "dependencies": {
    "tailwindcss": "^4.1.13",
    "daisyui": "^5.0.0"
  }
}
```

This is *not* read by the build (the Nix derivation handles fetching), but
keeps the manifest truthful for editor tooling and for any future contributor
running `npm install` outside the Nix path.

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

### `frontend/src/Frontend/Auth/Widget.hs`

1. **Headings.** `el "h1"` → `elAttr "h1" ("class" =: "card-title text-2xl mb-2")`.

2. **`labelled` helper.** Restructure to emit daisyUI's `form-control` /
   `label` / `label-text` structure:
   ```haskell
   labelled lbl inner = elAttr "div" ("class" =: "form-control w-full mb-2") $ do
     elAttr "label" ("class" =: "label") $
       elAttr "span" ("class" =: "label-text") $ text lbl
     inner
   ```

3. **Inputs.** Add `class` to each `inputElement`'s initial attributes:
   ```haskell
   "type" =: "email" <> "autocomplete" =: "email"
     <> "class" =: "input input-bordered w-full"
   ```
   Same for the password inputs (`"class" =: "input input-bordered w-full"`).

4. **Submit buttons.** Replace `button "Sign in"` / `button "Create account"`
   with `buttonClass "btn btn-primary w-full mt-2" "Sign in"` (and likewise
   for signup). Move `buttonClass` into a shared module, or duplicate it here
   — see "open question" below.

5. **Error line.** `el "p"` → `elAttr "p" ("class" =: "text-error text-sm mt-2 min-h-[1.25rem]")`.
   The `min-h` keeps the layout from jumping when an error appears.

## Open question — where does `buttonClass` live?

Two reasonable options:

- **Keep it in `Frontend.hs`** and add a copy in `Frontend/Auth/Widget.hs`. Two
  ~6-line copies; no new module.
- **Add `frontend/src/Frontend/UI.hs`** (or similar) exporting `buttonClass`
  and `page`, imported from both call sites. Cleaner, but introduces a new
  module just for two helpers.

Recommendation: start with the duplication and lift to a shared module the
first time a third call site appears. Avoids premature abstraction; the
helpers are small. Decide before implementing.

## Verification

1. `nix-prefetch-url https://registry.npmjs.org/daisyui/-/daisyui-5.0.0.tgz`
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
  path; `package.json` is a manifest only.
- Component coverage beyond what is currently rendered. Future routes
  (Calendar, History, Settings) get styled when their content lands.
- Form validation styling (`input-error`, inline field errors). The current
  widget only surfaces a single bottom-of-form error string; that is enough
  for now.
