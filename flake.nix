{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # This pins requirements.txt provided by zephyr-nix.pythonEnv.
    # Keep in sync with the Zephyr version that the ZMK revision in your
    # config's west.yml requires (see zmk/app/west.yml).
    zephyr.url = "github:zmkfirmware/zephyr/v4.1.0+zmk-fixes";
    zephyr.flake = false;

    # Zephyr sdk and toolchain.
    zephyr-nix.url = "github:nix-community/zephyr-nix";
    zephyr-nix.inputs.zephyr.follows = "zephyr";
    zephyr-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, zephyr-nix, ... }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        zephyr = zephyr-nix.packages.${system};
        keymap_drawer = pkgs.python3Packages.callPackage ./nix/keymap-drawer.nix {};

        # protoc + protobuf runtime for nanopb, used when building ZMK Studio
        # (the studio-rpc-usb-uart snippet). Must be the same interpreter as
        # zephyr.pythonEnv so it can be exposed via PYTHONPATH.
        nanopb_python = pkgs.python3.withPackages (ps: [ps.grpcio-tools ps.protobuf]);
      in {
        default = pkgs.mkShellNoCC {
          packages =
            [
              zephyr.pythonEnv
              # Match the SDK that ZMK's own CI uses for this Zephyr version
              # (see zephyr-sdk-version in zmk-docker's <major>.<minor>-branch).
              # Zephyr 4.1 needs 0.16.9: with 0.17.2+ the newer picolibc
              # conflicts with Zephyr 4.1's lib/libc/picolibc/locks.c.
              (zephyr.sdk-0_16.override {targets = ["arm-zephyr-eabi"];})

              pkgs.cmake
              pkgs.dtc
              pkgs.gcc
              pkgs.ninja

              pkgs.just
              pkgs.yq # Make sure yq resolves to python-yq.
              pkgs.fzf

              keymap_drawer

              # -- Used by just_recipes and west_commands. Most systems already have them. --
              # pkgs.gawk
              # pkgs.unixtools.column
              # pkgs.coreutils # cp, cut, echo, mkdir, sort, tail, tee, uniq, wc
              # pkgs.diffutils
              # pkgs.findutils # find, xargs
              # pkgs.gnugrep
              # pkgs.gnused
            ];

          shellHook = ''
            export ZMK_BUILD_DIR=$(pwd)/.build;
            export ZMK_SRC_DIR=$(pwd)/zmk/app;

            # Let nanopb's generator find protoc (ZMK Studio builds).
            export PYTHONPATH="${nanopb_python}/${nanopb_python.sitePackages}''${PYTHONPATH:+:$PYTHONPATH}";

            source _just_completion.bash
          '';
        };
      }
    );
  };
}
