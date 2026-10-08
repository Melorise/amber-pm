{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.amber-pm;
  apmXdgDataDir = "/var/lib/apm/apm/files/ace-env/amber-ce-tools/data-dir";
  apmFontconfig = pkgs.writeText "amber-pm-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <!-- Keep the container's own fonts and per-user font directories. -->
      <include ignore_missing="yes">/etc/fonts/fonts.conf</include>

      <!-- The host root is mounted at /host by every APM runner. -->
      ${lib.concatMapStringsSep "\n" (
        font: "      <dir>${lib.escapeXML "/host${font}"}</dir>"
      ) config.fonts.packages}
    </fontconfig>
  '';
in
{
  options.programs.amber-pm = {
    enable = lib.mkEnableOption "Amber Package Manager";

    package = lib.mkPackageOption pkgs "amber-pm" { };

    initializeState = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create /var/lib/apm/apm on first activation and refresh APM-managed files on later activations.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    # Generated from the final, merged NixOS fonts.packages value for this host.
    environment.etc."amber-pm/fonts.conf".source = apmFontconfig;
    environment.sessionVariables.XDG_DATA_DIRS = lib.mkAfter [ apmXdgDataDir ];
    environment.etc."systemd/user-environment-generators/60-apm".source =
      pkgs.writeShellScript "60-apm" ''
        apm_xdg_data_dir=${lib.escapeShellArg apmXdgDataDir}
        xdg_data_dirs="''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

        case ":$xdg_data_dirs:" in
          *":$apm_xdg_data_dir:"*) ;;
          *) xdg_data_dirs="$xdg_data_dirs:$apm_xdg_data_dir" ;;
        esac

        printf 'XDG_DATA_DIRS=%s\n' "$xdg_data_dirs"
      '';

    programs.nix-ld.enable = lib.mkDefault true;

    boot.kernel.sysctl."kernel.apparmor_restrict_unprivileged_userns" = lib.mkDefault 0;

    system.activationScripts.amber-pm-state = lib.mkIf cfg.initializeState ''
      target="/var/lib/apm/apm"

      if [ ! -e "$target" ]; then
        echo "APM state directory not found, initializing..."
        ${cfg.package}/bin/amber-pm-init-state
        echo "Running ace-init for first-time setup..."
        ${cfg.package}/bin/amber-pm-ace-init
      else
        echo "Refreshing APM-managed files from the current Nix generation..."
        ${cfg.package}/bin/amber-pm-init-state --force
      fi
    '';
  };
}
