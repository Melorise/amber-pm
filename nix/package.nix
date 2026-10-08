{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  bubblewrap,
  coreutils,
  curl,
  desktop-file-utils,
  dpkg,
  fakeroot,
  file,
  findutils,
  fuse-overlayfs,
  gawk,
  glib,
  gnugrep,
  gnused,
  gzip,
  libnotify,
  procps,
  sudo,
  systemd,
  gnutar,
  util-linux,
  which,
  xdg-user-dirs,
  xsettingsd,
  xz,
  zenity,
  version ? "1.3.4.0",
  sourceRoot ? ../.,
  source ? lib.cleanSourceWith {
    src = sourceRoot;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      ! lib.elem base [
        ".git"
        "result"
      ];
  },
  # Accept explicit src overrides without callPackage auto-injecting pkgs.src,
  # an unrelated package name in nixpkgs. source remains an alias.
  ...
}@args:

let
  runtimePath = lib.makeBinPath [
    bash
    bubblewrap
    coreutils
    curl
    desktop-file-utils
    dpkg
    fakeroot
    file
    findutils
    fuse-overlayfs
    gawk
    glib
    gnugrep
    gnused
    gzip
    libnotify
    procps
    sudo
    systemd
    gnutar
    util-linux
    which
    xdg-user-dirs
    xsettingsd
    xz
    zenity
  ];
in
stdenvNoCC.mkDerivation {
  pname = "amber-pm";
  inherit version;

  src = if args ? src then args.src else source;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    echo "copying Debian-style install tree"
    mkdir -p "$out"
    cp -a src/* "$out"/

    rm -f "$out/usr/bin/apm" \
      "$out/usr/bin/amber-pm-debug" \
      "$out/usr/bin/amber-pm-configure-nvidia"

    echo "substituting version and store paths"
    substituteInPlace "$out/usr/libexec/apm/apm-main" \
      --replace-fail '@VERSION@' '${version}' \
      --replace-fail '/usr/libexec/apm/apm-eggs' "$out/usr/libexec/apm/apm-eggs"

    while IFS= read -r -d "" file; do
      if grep -Iq '@VERSION@' "$file" && grep -q '@VERSION@' "$file"; then
        sed -i 's|@VERSION@|${version}|g' "$file"
      fi
    done < <(find "$out/usr" "$out/etc" -type f -print0)

    echo "patching host script shebangs"
    patchShebangs "$out/usr/bin" "$out/usr/libexec"
    patchShebangs \
      "$out/var/lib/apm/apm/files/ace-run" \
      "$out/var/lib/apm/apm/files/ace-run-pkg" \
      "$out/var/lib/apm/apm/files/bin/ace-init" \
      "$out/var/lib/apm/apm/files/bin/ace-run" \
      "$out/var/lib/apm/apm/files/bin/amber-ce-configure-nvidia" \
      "$out/var/lib/apm/apm/files/build-container.sh" \
      "$out/var/lib/apm/apm/files/feedback.sh" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/ace-upgrader/ace-upgrader" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/container-init/init.sh" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/apm-debug" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/bwrap" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/gio" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/pkexec" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/sudo" \
      "$out/var/lib/apm/apm/files/amber-ce-tools/bin-override/xdg-open"

    echo "installing wrappers"
    mkdir -p "$out/bin" "$out/share/amber-pm/var-lib-apm"
    ln -s /var/lib/apm/apm/files/bin/ace-run "$out/bin/amber-pm-debug"
    ln -s /var/lib/apm/apm/files/bin/amber-ce-configure-nvidia "$out/bin/amber-pm-configure-nvidia"

    for prog in "$out"/usr/bin/*; do
      if [ -f "$prog" ] || [ -L "$prog" ]; then
        name="$(basename "$prog")"
        if [ "$name" != apm ] \
          && [ "$name" != amber-pm-debug ] \
          && [ "$name" != amber-pm-configure-nvidia ]; then
          makeWrapper "$prog" "$out/bin/$name" \
            --prefix PATH : "$out/bin:${runtimePath}"
        fi
      fi
    done

    cp -a "$out/var/lib/apm/apm" "$out/share/amber-pm/var-lib-apm/apm"
    rm -rf "$out/var"

    makeWrapper "$out/usr/libexec/apm/apm-main" "$out/bin/apm" \
      --prefix PATH : "$out/bin:${runtimePath}"

    cat > "$out/bin/amber-pm-ace-init" <<EOF
#!${bash}/bin/bash
set -euo pipefail
export PATH="${runtimePath}:\$PATH"
exec /var/lib/apm/apm/files/bin/ace-init "\$@"
EOF
    chmod +x "$out/bin/amber-pm-ace-init"

    cat > "$out/bin/amber-pm-init-state" <<'EOF'
#!@bash@/bin/bash
set -euo pipefail

if [ "''${1:-}" = "--help" ]; then
  echo "Usage: amber-pm-init-state [--force]"
  echo "Initializes /var/lib/apm/apm from the Nix store seed."
  exit 0
fi

if [ "$(id -u)" != 0 ]; then
  echo "amber-pm-init-state must be run as root because it writes /var/lib/apm" >&2
  exit 1
fi

seed="@out@/share/amber-pm/var-lib-apm/apm"
target="/var/lib/apm/apm"
container_tools="$target/files/ace-env/amber-ce-tools"

mkdir -p /var/lib/apm
if [ -e "$target" ] && [ "''${1:-}" != "--force" ]; then
  echo "$target already exists; leaving it untouched."
  echo "Run 'amber-pm-init-state --force' to refresh APM's own files."
  exit 0
fi

mkdir -p "$target"
cp -a "$seed"/. "$target"/

# ace-init copies these tools into the persistent Debian environment.  Refresh
# that copy as well so it cannot retain interpreter paths from an old Nix
# generation.  Keep the rest of ace-env, including installed packages, intact.
if [ -d "$target/files/ace-env" ]; then
  mkdir -p "$container_tools"
  cp -a "$seed/files/amber-ce-tools"/. "$container_tools"/
  chmod -R u+rwX "$container_tools"
fi

echo '@version@' > "$target/.amber-pm-version"
# Do not traverse the potentially large persistent Debian environment on every
# system activation.  Only make the seed-managed files writable here.
find "$target" -path "$target/files/ace-env" -prune -o -exec chmod u+rwX {} +
echo "Initialized $target"
echo "Next step: run '@out@/bin/amber-pm-ace-init' as root, or run 'apm --help' for CLI smoke testing."
EOF
    substituteInPlace "$out/bin/amber-pm-init-state" \
      --replace-fail '@bash@' '${bash}' \
      --replace-fail '@out@' "$out" \
      --replace-fail '@version@' '${version}'
    chmod +x "$out/bin/amber-pm-init-state"

    runHook postInstall
  '';

  meta = {
    description = "bwrap and fuse-overlayfs based package manager for Debian-style application containers";
    homepage = "https://gitee.com/amber-ce/amber-pm/";
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "loongarch64-linux"
    ];
    maintainers = [ ];
  };
}
