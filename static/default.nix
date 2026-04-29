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
