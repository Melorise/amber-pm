# NixOS 构建与本地测试

本仓库提供了实验性的 Nix 打包文件，可用于在 NixOS 上本地构建和测试 APM。

## 本地构建

在仓库根目录执行：

```bash
nix-build default.nix
```

构建成功后会生成 `result` 符号链接，可先做基础命令测试：

```bash
./result/bin/apm --version
./result/bin/apm --help
./result/bin/amber-pm-init-state --help
```

如果使用 Flake，也可以执行：

```bash
nix build .#amber-pm
nix flake check
```

## 初始化本地状态目录

APM 需要可写的 `/var/lib/apm` 目录保存自身运行环境和已安装应用。Nix 包中的文件位于只读 Nix store，因此首次测试前需要初始化状态目录：

```bash
sudo ./result/bin/amber-pm-init-state
```

如需用新构建结果覆盖 APM 自身文件，可执行：

```bash
sudo ./result/bin/amber-pm-init-state --force
```

`--force` 会原地覆盖 `/var/lib/apm/apm` 中的 APM 自身文件，不会移动、备份或删除整个 `/var/lib/apm/apm` 目录，以免影响已经安装在该目录下的 APM 应用。

随后初始化内置 AmberCE 环境：

```bash
sudo ./result/bin/amber-pm-ace-init
```

完成后可继续测试：

```bash
./result/bin/apm debug
./result/bin/apm update
./result/bin/apm search amber-pm-
```

## 作为 NixOS Module 使用

可在 NixOS 配置中引入本仓库的 module：

```nix
{ pkgs, ... }:
{
  imports = [
    /path/to/amber-pm/nix/module.nix
  ];

  nixpkgs.overlays = [
    (final: prev: {
      amber-pm = final.callPackage /path/to/amber-pm/nix/package.nix { };
    })
  ];

  programs.amber-pm.enable = true;
}
```

然后执行：

```bash
sudo nixos-rebuild switch
```

该 module 会将 `amber-pm` 加入 `environment.systemPackages`，并在系统激活时初始化 `/var/lib/apm/apm`。APM 使用 bwrap 与 fuse-overlayfs，module 默认会设置 `kernel.apparmor_restrict_unprivileged_userns = 0`，并启用 `nix-ld` 以提高兼容性。

在 NixOS 上，APM 不会向 `/usr/share` 或 `/usr/local/share` 写入应用入口和图标。module 会将 `/var/lib/apm/apm/files/ace-env/amber-ce-tools/data-dir` 加入 `XDG_DATA_DIRS`，由桌面环境直接发现 APM 管理的应用。启用或更新该配置后需要重新登录桌面会话。

仅在 NixOS 宿主上，应用运行入口和调试入口会在容器的 `XDG_DATA_DIRS` 中，将 `/usr/local/share:/usr/share` 放到继承的宿主目录之前，确保 Debian 运行时能找到自己的 MIME 数据库、GSettings schema 和图标，避免 GTK 文件选择器因无法识别 PNG 而崩溃。其他发行版保持原有的数据目录传递逻辑。更新包后，module 在下一次系统激活时会自动刷新持久化的运行脚本。

module 还会根据 NixOS 合并后的 `fonts.packages` 生成 `/etc/amber-pm/fonts.conf`。仅在 NixOS 宿主且未显式指定 `FONTCONFIG_FILE` 时，APM 才启用该配置；已有的用户或应用配置优先。APM 容器通过已挂载的 `/host` 只读访问这些 Nix store 字体，同时保留容器自身字体以及 `~/.local/share/fonts`、`~/.fonts` 中的用户字体。字体包应加入 `fonts.packages`；仅加入 `environment.systemPackages` 不代表该字体已注册到系统 fontconfig。

仅在 NixOS 宿主上，启动应用时 APM 会保留显式的 `XCURSOR_PATH`，在宿主解析主题文件的真实路径，并补充容器可访问的 `/host/nix/store/...`。在 X11/XWayland 会话中，未显式指定的光标主题名和尺寸通过标准 XSettings 动态读取，因此图形设置中的调整无需写入 Nix 或 Home Manager，也无需重新构建系统。其他发行版不启用上述字体或光标桥接，也不强制替换初始化的 Shell、locale 流程或失败处理策略。

## NUR/nixpkgs 打包复用

`nix/package.nix` 支持外部传入 `version` 和 `src`，并保留 `source` 别名，因此 NUR 或 nixpkgs 中可以复用同一个表达式，不必依赖本地源码路径。同时传入时以 `src` 为准。

NUR 仓库中的示例：

```nix
{ pkgs ? import <nixpkgs> { } }:

{
  amber-pm = pkgs.callPackage ./pkgs/amber-pm {
    version = "1.3.4.0";
    src = pkgs.fetchFromGitHub {
      owner = "amber-ce";
      repo = "amber-pm";
      rev = "v1.3.4.0";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
}
```

nixpkgs 中的包通常应放在类似路径：

```text
pkgs/by-name/am/amber-pm/package.nix
```

提交 nixpkgs 前建议先满足以下条件：

- 使用正式 tag 或 release，不使用本地路径作为源码。
- 固定 `src.hash`。
- 本地通过 `nix-build -A amber-pm` 或 `nix build .#amber-pm`。
- 确认 `apm --version`、`apm --help`、`amber-pm-init-state --help` 正常。
- `meta` 中填写 license、homepage、platforms 和 maintainers。

当前 NixOS 适配仍偏测试用途。建议先发布到 NUR 收集测试反馈，再投 nixpkgs。
