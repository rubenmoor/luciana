# Tailwind CSS Integration

Status: reference

Mirrors [obsidiansystems/obelisk-tailwind-example](https://github.com/obsidiansystems/obelisk-tailwind-example),
with one deviation: the example pulls `tailwindcss_4` from a recent nixpkgs
(nixos-25.05). That nixpkgs requires Nix ≥ 2.18, but `obelisk-command` 0.9.0.1
hard-codes calls to a bundled Nix 2.11. So instead of bringing in a modern
nixpkgs, we fetch the **Tailwind v4 standalone CLI binary** from upstream
GitHub releases and stay entirely on Obelisk's pinned (old) nixpkgs.

The Tailwind CLI is run inside a Nix derivation that is wired into Obelisk via
`staticFiles`. The compiled CSS becomes a normal static asset, referenced from
`Frontend._frontend_head` with `$(static "styles.css")`. Frontend `.hs` files
are scanned by Tailwind's content/purge step so only used utilities ship.

## Files to add

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

### `static/default.nix`
The standalone CLI is platform-specific; `tailwindcssAsset` selects the right
release artifact, and `tailwindcssBin` fetches it as a bare executable. The
binary is a Bun-compiled single-file executable, but on NixOS it needs two
fix-ups before it runs:
1. **`patchelf --set-interpreter`** — the binary's ELF header points at
   `/lib64/ld-linux-x86-64.so.2`, which doesn't exist on NixOS. We rewrite
   it to the `stdenv.cc` dynamic linker.
2. **`LD_LIBRARY_PATH`** — Bun unpacks an embedded native module
   (`@tailwindcss/oxide`) at runtime which `dlopen`s `libstdc++.so.6`. We
   put `stdenv.cc.cc.lib` on the loader path so that succeeds.

daisyui is consumed via `node_modules/`; tailwind v4 picks it up through
`@plugin` directives in `styles.css`. No `nodejs` runtime is involved.

```nix
{ pkgs ? (import ../.obelisk/impl {}).nixpkgs }:
let
  frontendSrcFiles = ../frontend;

  tailwindcssVersion = "4.1.13";
  tailwindcssAsset =
    if pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64 then "tailwindcss-linux-x64"
    else if pkgs.stdenv.isLinux && pkgs.stdenv.isAarch64 then "tailwindcss-linux-arm64"
    else if pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 then "tailwindcss-macos-arm64"
    else if pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64 then "tailwindcss-macos-x64"
    else throw "Unsupported platform for tailwindcss standalone CLI";
  tailwindcssBin = pkgs.fetchurl {
    url = "https://github.com/tailwindlabs/tailwindcss/releases/download/v${tailwindcssVersion}/${tailwindcssAsset}";
    sha256 = "04dyffwhkl52iv1ngs22pjnz7pv6la560s4z3xqj6cqdcj7rzvdr";
  };

  daisyuiVersion = "5.5.19";
  daisyuiTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/daisyui/-/daisyui-${daisyuiVersion}.tgz";
    sha256 = "1y2sdyn393d5b2gwm5krs6vc1g9y5ac3fzy5xkad4w87cv0547k0";
  };
in pkgs.stdenv.mkDerivation {
  name = "static";
  src = ./src;
  nativeBuildInputs = [ pkgs.patchelf ];
  installPhase = ''
    mkdir -p $out/images
    mkdir -p node_modules/daisyui
    tar -xzf ${daisyuiTarball} -C node_modules/daisyui --strip-components=1

    install -m755 ${tailwindcssBin} ./tailwindcss
    patchelf --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" ./tailwindcss
    ln -s ${frontendSrcFiles} frontend

    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib"
    ./tailwindcss -i css/styles.css -o $out/styles.css

    cp lib.js $out/lib.js
    cp -r images/* $out/images/
  '';
}
```

Computing the sha256 for `tailwindcssBin` (one-time, per version bump):
```bash
nix-prefetch-url --type sha256 \
  https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.13/tailwindcss-linux-x64
```

## Files to remove

- `static/src/nixpkgs.nix` — no longer needed; we no longer pull anything from
  a modern nixpkgs.
- `static/src/package.json` — was never read (no `npm install` step); existed
  only as documentation. Tailwind v4 uses CSS `@import`/`@plugin` directives
  rather than a JS-side dependency manifest.

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

- `node2nix`-managed dependencies. The standalone Tailwind CLI plus
  fixed-output npm tarballs are enough; we do not need a `package-lock.json` /
  `node-packages.nix` pipeline unless we later add enough npm packages to make
  manual tarball fetching painful.
- PostCSS pipeline.
- Production minification beyond Tailwind defaults.
