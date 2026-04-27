{ pkgs ? (import ../.obelisk/impl {}).nixpkgs }:
let
  nixpkgs = import ./src/nixpkgs.nix {};

  # The frontend source files have to be passed in so that tailwind's purge option works.
  # See https://tailwindcss.com/docs/optimizing-for-production#removing-unused-css
  frontendSrcFiles = ../frontend;

in pkgs.stdenv.mkDerivation {
  name = "static";
  src = ./src;
  buildInputs = [ pkgs.nodejs nixpkgs.tailwindcss_4 ];
  installPhase = ''
    mkdir -p $out/images

    # Make the frontend Haskell source files available at the path declared in tailwind.config.js
    ln -s ${frontendSrcFiles} frontend

    tailwindcss -i css/styles.css -o $out/styles.css

    cp lib.js $out/lib.js
    cp -r images/* $out/images/
  '';
}
