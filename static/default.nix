{ pkgs ? (import ../.obelisk/impl {}).nixpkgs }:
let
  nixpkgs = import ./src/nixpkgs.nix {};

  # The frontend source files have to be passed in so that tailwind's purge option works.
  # See https://tailwindcss.com/docs/optimizing-for-production#removing-unused-css
  frontendSrcFiles = ../frontend;

  daisyuiVersion = "5.5.19";
  daisyuiTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/daisyui/-/daisyui-${daisyuiVersion}.tgz";
    sha256 = "1y2sdyn393d5b2gwm5krs6vc1g9y5ac3fzy5xkad4w87cv0547k0";
  };

in pkgs.stdenv.mkDerivation {
  name = "static";
  src = ./src;
  buildInputs = [ pkgs.nodejs nixpkgs.tailwindcss_4 ];
  installPhase = ''
    mkdir -p $out/images
    mkdir -p node_modules/daisyui
    tar -xzf ${daisyuiTarball} -C node_modules/daisyui --strip-components=1

    # Make the frontend Haskell source files available at the path declared in tailwind.config.js
    ln -s ${frontendSrcFiles} frontend

    tailwindcss -i css/styles.css -o $out/styles.css

    cp lib.js $out/lib.js
    cp -r images/* $out/images/
  '';
}
