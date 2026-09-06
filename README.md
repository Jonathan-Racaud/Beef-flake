# Beef-flake

A Nix flake that builds and packages the [Beef programming language](https://www.beeflang.org/) and IDE for NixOS/Linux.

Beef does not have an official NixOS package. This flake compiles Beef from source against the nightly development branch and wires up all the runtime dependencies so the toolchain and IDE work out of the box on NixOS.

## What it provides

| Output | Description |
|---|---|
| `packages.beef` | The full Beef toolchain: `BeefBuild` and `BeefIDE` |
| `apps.BeefBuild` | Run `BeefBuild` directly via `nix run` |
| `apps.BeefIDE` | Launch BeefIDE via `nix run` |
| `devShells.default` | A development shell for hacking on the flake itself (includes GDB and clang-tools) |

Supported systems: `x86_64-linux`.

## Installation

### Ad-hoc — run without installing

```sh
# Launch BeefIDE
nix run github:Jonathan-Racaud/Beef-flake#BeefIDE

# Run BeefBuild
nix run github:Jonathan-Racaud/Beef-flake#BeefBuild
```

### NixOS / Home Manager — add to your flake

1. Add the input to your `flake.nix`:

```nix
inputs.beef-flake.url = "github:Jonathan-Racaud/Beef-flake";
```

2. Add the package to your system or home packages:

```nix
# NixOS (configuration.nix or a module)
environment.systemPackages = with pkgs; [
  inputs.beef-flake.packages."${stdenv.hostPlatform.system}".default
];

# Home Manager
home.packages = with pkgs; [
  inputs.beef-flake.packages."${stdenv.hostPlatform.system}".default
];
```

### Installed commands

| Command | Description |
|---|---|
| `BeefBuild` | The Beef build system |
| `BeefIDE` | Launches BeefIDE (copies runtime files to `~/.local/share/beef/bin/` on first run) |

### Desktop entry

Installing the package also registers a launcher: **Beef IDE** appears in your application menu (GNOME Shell, KDE, etc.), with no extra configuration. The package ships:

- `share/applications/BeefIDE.desktop` — starts the same `BeefIDE` wrapper as the command above
- `share/icons/hicolor/128x128/apps/beeflang.png` — the app icon

Note: upstream Beef contains an `IDE/Resources/BeefIDE.desktop` file, but it targets the classic `/opt/BeefLang` layout (`Exec=beefide`, `Path=/opt/BeefLang/bin`) and is not installed by any of Beef's own scripts, so this flake generates its own entry pointing at the installed wrapper.

## Contributing

Contributions are welcome. Please keep the following rules in mind:

### Version updates

Beef version bumps must always target a **nightly commit** from the upstream [`beefytech/Beef`](https://github.com/beefytech/Beef) repository. Once a stable Linux release is made available, it will also be provided.

1. Find the commit hash of the nightly build you want to pin. You can find the list of nightly build at: [https://nightly.beeflang.org/index.html](https://nightly.beeflang.org/index.html)
2. Update the `beef-src` input in `flake.nix`:

```nix
beef-src = {
  url = "github:beefytech/Beef/<commit-hash>";
  flake = false;
};
```

3. Run `nix flake update` to refresh `flake.lock`.
4. Verify the build: `nix build`.

### Working on your own fork of Beef

If you want to use this flake to build your own fork of the Beef project, simply point the `url` of the input `beef-src` attribute set to the folder containing your forked Beef repo. The flake should be able to build it granted the build process between your fork and the official commit this flake targets are the same.

### What belongs here — and what does not

This flake only touches the **build and packaging layer**. It must never patch Beef's source code. Acceptable changes include:

- Updating the pinned Beef nightly commit
- Fixing CMake/Ninja build script invocations
- Adjusting Nix `buildInputs`, `nativeBuildInputs`, or `makeWrapper` flags
- Adding or fixing `postPatch` shebangs and hardcoded paths that are artefacts of the Nix sandbox (e.g. replacing `/usr/bin/clang++` with the Nix-provided compiler path)
- Updating LLVM version pins that reflect what nixpkgs ships
- IDE runtime dependency changes (SDL, Wayland, audio libraries, etc.)

Changes that modify Beef's own source logic, algorithms, or language semantics do not belong here. Open a PR on [`beefytech/Beef`](https://github.com/beefytech/Beef) instead.

Only official Beef nightly releases or stable release will be accepted in this flake. Personal forks will not.

### Development shell

```sh
nix develop
```

This drops you into a shell with CMake, Ninja, LLVM, GDB, and clang-tools available and `LLVM_DIR` pre-set that is meant to iterate on this flake. Using this flake as a development environment for the Beef project is out of the scope of this flake.
