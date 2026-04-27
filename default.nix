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
  };
})
