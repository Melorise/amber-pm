{
  description = "Amber Package Manager packaged for NixOS testing";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "loongarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          amber-pm = pkgs.callPackage ./nix/package.nix { };
          default = self.packages.${system}.amber-pm;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          amber-pm = self.packages.${system}.amber-pm;
          moduleTest = nixpkgs.lib.nixosSystem {
            modules = [
              self.nixosModules.default
              {
                nixpkgs.hostPlatform = system;
                programs.amber-pm = {
                  enable = true;
                  package = amber-pm;
                  initializeState = false;
                };
                fonts.packages = [ pkgs.dejavu_fonts ];
                system.stateVersion = "24.11";
              }
            ];
          };
          apmFontconfig = moduleTest.config.environment.etc."amber-pm/fonts.conf".source;
        in
        {
          cli-smoke =
            assert (pkgs.callPackage ./nix/package.nix {
              src = ./.;
              source = ./src;
            }).src == ./.;
            assert (pkgs.callPackage ./nix/package.nix { source = ./.; }).src == ./.;
            pkgs.runCommand "amber-pm-cli-smoke" { } ''
            ${amber-pm}/bin/apm --version
            ${amber-pm}/bin/apm --help >/dev/null
            ${amber-pm}/bin/amber-pm-init-state --help >/dev/null
            ! grep -Fq 'XCURSOR_PATH=' ${amber-pm}/bin/apm
            grep -Fq 'xsettingsd-' ${amber-pm}/bin/apm
            grep -Fq 'export FONTCONFIG_FILE="/host''${host_fontconfig_file}"' ${amber-pm}/usr/libexec/apm/apm-main
            grep -Fq 'dump_xsettings' ${amber-pm}/usr/libexec/apm/apm-main
            grep -Fq 'append_cursor_path "/host''${icon_root}"' ${amber-pm}/usr/libexec/apm/apm-main
            grep -Fq '<include ignore_missing="yes">/etc/fonts/fonts.conf</include>' ${apmFontconfig}
            grep -Fq '<dir>/host${pkgs.dejavu_fonts}</dir>' ${apmFontconfig}
            (
              # Load only helpers; never mount containers or initialize state.
              source <(sed '/^# 帮助信息函数/,$d' ${amber-pm}/usr/libexec/apm/apm-main)
              is_nixos() { [ "$mock_nixos" = 1 ]; }
              dump_xsettings() { printf 'Gtk/CursorThemeName "Test Theme"\nGtk/CursorThemeSize 48\n'; }
              mock_nixos=0
              unset FONTCONFIG_FILE XCURSOR_PATH XCURSOR_THEME XCURSOR_SIZE
              configure_host_fontconfig
              configure_host_cursor
              [ ! -v FONTCONFIG_FILE ]
              [ ! -v XCURSOR_PATH ]
              [ ! -v XCURSOR_THEME ]
              [ ! -v XCURSOR_SIZE ]
              for mock_nixos in 0 1; do
                export FONTCONFIG_FILE=/custom/fonts.conf XCURSOR_PATH=/custom/cursors
                export XCURSOR_THEME=Custom XCURSOR_SIZE=42
                configure_host_fontconfig
                configure_host_cursor
                [ "$FONTCONFIG_FILE" = /custom/fonts.conf ]
                [ "''${XCURSOR_PATH%%:*}" = /custom/cursors ]
                [ "$XCURSOR_THEME" = Custom ]
                [ "$XCURSOR_SIZE" = 42 ]
              done
              unset XCURSOR_THEME XCURSOR_SIZE
              configure_host_cursor
              [ "$XCURSOR_THEME" = 'Test Theme' ]
              [ "$XCURSOR_SIZE" = 48 ]
            )
            touch "$out"
          '';
        }
      );

      nixosModules.default = import ./nix/module.nix;

      overlays.default = final: prev: {
        amber-pm = final.callPackage ./nix/package.nix { };
      };
    };
}
