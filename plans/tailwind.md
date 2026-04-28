# Tailwind CSS Integration

Status: reference

Mirrors [obsidiansystems/obelisk-tailwind-example](https://github.com/obsidiansystems/obelisk-tailwind-example).

The Tailwind CLI is run inside a Nix derivation that is wired into Obelisk via
`staticFiles`. The compiled CSS becomes a normal static asset, referenced from
`Frontend._frontend_head` with `$(static "styles.css")`. Frontend `.hs` files
are scanned by Tailwind's content/purge step so only used utilities ship.

## Files to add

### `static/src/package.json`
```json
{
  "name": "styles",
  "version": "0.0.0",
  "dependencies": {
    "tailwindcss": "^4.1.13"
  }
}
```

### `static/src/tailwind.config.js`
```js
module.exports = {
  purge: {
    enabled: true,
    content: ['./frontend/**/*.hs']
  },
  darkMode: false,
  theme: { extend: {} },
  variants: {},
  plugins: [],
}
```

### `static/src/css/styles.css`
```css
@import "tailwindcss";
```

### `static/src/nixpkgs.nix`
Pins a nixpkgs that ships `tailwindcss_4` (the Obelisk thunk's pinned nixpkgs
is too old). Same revision as the example:
```nix
import (builtins.fetchTarball {
  name = "nixos-25.05";
  url = "https://github.com/nixos/nixpkgs/archive/9d1fa9fa266631335618373f8faad570df6f9ede.tar.gz";
  sha256 = "sha256:1pn90y4nw8c3gdz9c2chpy75hiay3872zhgfkmxc1mhgpkwx66bx";
})
```

### `static/default.nix`
```nix
{ pkgs ? (import ../.obelisk/impl {}).nixpkgs }:
let
  nixpkgs = import ./src/nixpkgs.nix {};
  frontendSrcFiles = ../frontend;
in pkgs.stdenv.mkDerivation {
  name = "static";
  src = ./src;
  buildInputs = [ pkgs.nodejs nixpkgs.tailwindcss_4 ];
  installPhase = ''
    mkdir -p $out/css
    mkdir -p $out/images
    ln -s ${frontendSrcFiles} frontend
    tailwindcss -i css/styles.css -o $out/styles.css
    cp -r images/* $out/images/ 2>/dev/null || true
  '';
}
```
Note: the example unconditionally `cp -r images/*`. We add `|| true` because
we have no images yet; remove once `static/src/images/` has content.

## Files to modify

### `default.nix` (project root)
Add `pkgs` to the args of the inner function and add `staticFiles` to the
project record:
```nix
project ./. ({ pkgs, ... }: {
  staticFiles = import ./static { inherit pkgs; };
  android.applicationId = ...;
  ...
  overrides = ...;
})
```

### `frontend/src/Frontend.hs`
Replace the `main.css` link in `_frontend_head` with the Tailwind output:
```haskell
elAttr "link"
  ( "href" =: $(static "styles.css")
 <> "type" =: "text/css"
 <> "rel"  =: "stylesheet"
  ) blank
```
Drop something visibly Tailwind-y in `_frontend_body` (e.g. `class` =:
`"text-3xl font-bold text-blue-600"` on the `h1`) so we can confirm styles
load end-to-end.

### `static/` (existing top-level dir)
The current `static/` holds raw assets (`lib.js`, etc.). Once `staticFiles`
points at the derivation, those assets must be served from there too. Move
`static/lib.js` (and any other assets currently referenced by `$(static ...)`)
into `static/src/` and copy them through in `installPhase`, e.g.:
```
cp lib.js $out/lib.js
```
Audit `git grep '\$(static '` first to enumerate every asset that needs
relocating before flipping `staticFiles`.

## Build / verification

1. `ob run` — Obelisk rebuilds the static derivation on changes; expect
   "Static assets being built..." / "Static assets built and symlinked to
   static.out".
2. Inspect `static.out/styles.css` to confirm Tailwind compiled.
3. Load `http://localhost:8000`, confirm the test class renders.
4. Add a class to a frontend file, confirm `static.out/styles.css` regenerates
   and the new utility appears.

## Out of scope

- `node2nix`-managed dependencies. `tailwindcss_4` from nixpkgs is enough; we
  do not need a `package-lock.json` / `node-packages.nix` pipeline unless we
  later add Tailwind plugins from npm.
- PostCSS pipeline.
- Production minification beyond Tailwind defaults.
