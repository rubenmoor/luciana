{ system ? builtins.currentSystem
, obelisk ? import ./.obelisk/impl {
    inherit system;
    iosSdkVersion = "16.1";

    # You must accept the Android Software Development Kit License Agreement at
    # https://developer.android.com/studio/terms in order to build Android apps.
    # Uncomment and set this to `true` to indicate your acceptance:
    # config.android_sdk.accept_license = false;

    # In order to use Let's Encrypt for HTTPS deployments you must accept
    # their terms of service at https://letsencrypt.org/repository/.
    # Uncomment and set this to `true` to indicate your acceptance:
    # terms.security.acme.acceptTerms = false;
  }
}:
with obelisk;
with obelisk.nixpkgs.haskell.lib;
project ./. ({ pkgs, ... }: {
  staticFiles = import ./static { inherit pkgs; };
  android.applicationId = "systems.obsidian.obelisk.examples.minimal";
  android.displayName = "Obelisk Minimal Example";
  ios.bundleIdentifier = "systems.obsidian.obelisk.examples.minimal";
  ios.bundleName = "Obelisk Minimal Example";
  overrides = self: super: {
    beam-core = self.callHackageDirect {
      pkg = "beam-core";
      ver = "0.10.3.0";
      sha256 = "0di4wi5wdbj8q728kq9q3s6vdj4vczzkv41nzzq0jfa4b7cma14p";
    } {};
    beam-migrate = self.callHackageDirect {
      pkg = "beam-migrate";
      ver = "0.5.3.0";
      sha256 = "0bqkqv0ip1sshxc98yc0gx1w8j7xv7yypd1gafz93glvmay2pxi9";
    } {};
    # servant-snap 0.9.0 in nixpkgs has tight bounds (servant <0.17) and
    # depends on a broken hspec-snap; we use rubenmoor's fork that
    # supports newer servant, and jailbreak/dontCheck both packages.
    servant-snap = dontCheck (doJailbreak (self.callCabal2nix "servant-snap" (pkgs.fetchFromGitHub {
      owner = "rubenmoor";
      repo = "servant-snap";
      rev = "4850305bd586e887229954ad9dfccb649c497f8e";
      sha256 = "1ins0j4vd3cmf2dgh601b4wjqky79myz1245v2b59m5zsp11am01";
    }) {}));
    servant-reflex = self.callCabal2nix "servant-reflex" (pkgs.fetchFromGitHub {
      owner = "rubenmoor";
      repo = "servant-reflex";
      rev = "9dae2cc37060ca5b7b647134b7bdd0bd871a1213";
      sha256 = "031kric5g8r2vp8vpva02c5fxyb65vivsc3bn474bnsgp55pisfz";
    }) {};
    servant = dontCheck (self.callHackage "servant" "0.19.1" {});
    # servant-auth pulls in quickcheck-instances, which fails to find text-short
    # in the GHCJS package set without explicit overrides.
    servant-auth = dontCheck (doJailbreak (self.callHackage "servant-auth" "0.4.1.0" {}));
    quickcheck-instances = doJailbreak (addBuildDepend (self.callHackage "quickcheck-instances" "0.3.28" {}) self.text-short);
    text-short = self.callHackage "text-short" "0.1.5" {};
  };
})
