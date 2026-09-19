{
  description = "Beef programming language and IDE for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    beef-src = {
      url = "github:beefytech/Beef/1cd7cf8687d86c447872c32fdf8c7a2ea7b699f1";
      
      # Use an absolute path to your own fork of Beef if you want to use this flake to build it.
      # url = "path:/path/to/the/forked/Beef";
      flake = false;
    };

    # If you want to use this flake to build a fork of the Beef project
    # comment the above `beef-src` and uncomment the one below.
    # Replace the path by the actual path to your fork

    #beef-src = {
    #  
    #  flake = false;
    #};
  };

  outputs = { self, nixpkgs, flake-utils, beef-src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        llvmPkgs = pkgs.llvmPackages_22 or pkgs.llvmPackages_latest;

        ideRuntimeDeps = with pkgs; [
          sdl3
          systemd
          curl
          freetype
          fontconfig
          fribidi
          dbus
          ibus
          libthai
          liburing
          libdrm
          libGL
          libGLU
          mesa
          alsa-lib
          libpulseaudio
          libjack2
          sndio
          pipewire
          wayland
          libdecor
          libxkbcommon
          udev
          libX11
          libXext
          libXrandr
          libXcursor
          libXfixes
          libXi
          libXScrnSaver
          libXtst
        ];

        compilerDeps = with pkgs; [
          llvmPkgs.llvm.dev
          llvmPkgs.llvm.lib
          llvmPkgs.lldb.dev
          llvmPkgs.lldb
          libffi
          zlib
          libxml2
          ncurses
        ];

        # Desktop entry for the app launcher. Upstream ships
        # IDE/Resources/BeefIDE.desktop but it targets the /opt/BeefLang
        # layout (Exec=beefide, Path=/opt/BeefLang/bin) and nothing installs
        # it, so we generate our own entry pointing at the installed wrapper.
        desktopItem = pkgs.makeDesktopItem {
          name = "BeefIDE";
          desktopName = "Beef IDE";
          comment = "IDE for the Beef programming language";
          exec = "BeefIDE";
          icon = "beeflang";
          categories = [ "Development" "IDE" ];
          terminal = false;
          startupWMClass = "BeefIDE";
        };

        beef = pkgs.stdenv.mkDerivation {
          pname = "beef";
          version = "unstable-${builtins.substring 0 7 (beef-src.rev or "unknown")}";

          src = beef-src;

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            python3
            autoPatchelfHook
            makeWrapper
          ];

          buildInputs = compilerDeps ++ ideRuntimeDeps;

          dontUseCmakeConfigure = true;
          dontConfigure = true;

          postUnpack = ''
            chmod -R u+w "$sourceRoot"
          '';

          postPatch = ''
            patchShebangs BeefySysLib/third_party/libffi || true
          '';

          buildPhase = ''
            runHook preBuild

            export LLVM_DIR=${llvmPkgs.llvm.dev}/lib/cmake/llvm
            echo "Using LLVM_DIR=$LLVM_DIR"

            # 1. Bundled libffi (matches build.sh behavior).
            (
              cd BeefySysLib/third_party/libffi
              ./configure --disable-docs
              make -j$NIX_BUILD_CORES
            )

            # 2. Release CMake build (Debug skipped to keep build time reasonable).
            mkdir -p jbuild
            (
              cd jbuild
              cmake -GNinja \
                -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                -DLLVM_DIR="$LLVM_DIR" \
                -DLLDB_INCLUDE_DIR=${llvmPkgs.lldb.dev}/include \
                -DLLDB_LIBRARY=${llvmPkgs.lldb}/lib/liblldb.so \
                -DBF_ENABLE_SDL=1 \
                -DBUILD_IMGCREATE=1 \
                ..
              ninja -j$NIX_BUILD_CORES
            )

            # 3. Wire up expected symlinks in IDE/dist and BeefLibs/Beefy2D/dist.
            ROOT=$PWD
            cd IDE/dist
            for lib in libBeefRT libBeefySysLib libIDEHelper; do
              ln -sf $ROOT/jbuild/Release/bin/$lib.a $lib.a
              ln -sf $ROOT/jbuild/Release/bin/$lib.a $ROOT/BeefLibs/Beefy2D/dist/$lib.a
            done
            ln -sf $ROOT/jbuild/Release/bin/libhunspell.so libhunspell.so

            # IDE/BeefProj.toml on Linux reads IDEHelper_libs_d.txt for BOTH
            # Debug and Release configs. CMake only writes the non-_d file
            # when built without Debug config, so mirror it.
            if [ -f IDEHelper_libs.txt ] && [ ! -f IDEHelper_libs_d.txt ]; then
              ln -sf IDEHelper_libs.txt IDEHelper_libs_d.txt
            fi

            LINKOPTS="-ldl -lpthread -Wl,-rpath -Wl,\$ORIGIN"

            # Beef tries to create ~/.config/beeflang/BeefManaged; the Nix
            # sandbox sets HOME=/homeless-shelter which is not writable.
            export HOME=$TMPDIR

            # BeefBoot's DoLinkGNU scans $PATH for `c++` and keeps the LAST
            # match, which would pick the unwrapped gcc over the cc-wrapper and
            # lose the glibc -B flag (ld can't find crt1.o). Append a `c++`
            # symlink to the cc-wrapper at the END of PATH so the scan resolves
            # the wrapper. BuildContext.bf uses a first-match scan, which already
            # resolves the wrapper, so this does not disturb it.
            mkdir -p "$TMPDIR/beef-cxx"
            ln -sfn ${pkgs.stdenv.cc}/bin/c++ "$TMPDIR/beef-cxx/c++"
            export PATH="$PATH:$TMPDIR/beef-cxx"

            # 4. Bootstrap BeefBuild via BeefBoot.
            echo "Building BeefBuild_boot..."
            $ROOT/jbuild/Release/bin/BeefBoot \
              --out=BeefBuild_boot \
              --src=../src \
              --src=../../BeefBuild/src \
              --src=../../BeefLibs/corlib/src \
              --src=../../BeefLibs/Beefy2D/src \
              --define=CLI \
              --define=LINUX_PACKAGE \
              --startup=BeefBuild.Program \
              --linkparams="./libBeefRT.a ./libIDEHelper.a ./libBeefySysLib.a ./libhunspell.so $(< IDEHelper_libs.txt) $LINKOPTS"

            echo "Building BeefBuild (Release)..."
            ./BeefBuild_boot -clean -proddir=../../BeefBuild -config=Release -define=LINUX_PACKAGE

            # 5. Build BeefIDE with the freshly-built BeefBuild.
            echo "Building BeefIDE (Release)..."
            ./BeefBuild -clean -proddir=../ -config=Release -define=LINUX_PACKAGE

            # ImgCreate's CMakeLists uses EXECUTABLE_OUTPUT_PATH which Ninja
            # ignores in this configuration; the binary ends up at
            # jbuild/BeefTools/ImgCreate/ImgCreate. Normalize the location.
            if [ ! -f $ROOT/jbuild/Release/bin/ImgCreate ] && \
               [ -f $ROOT/jbuild/BeefTools/ImgCreate/ImgCreate ]; then
              cp $ROOT/jbuild/BeefTools/ImgCreate/ImgCreate \
                 $ROOT/jbuild/Release/bin/ImgCreate
            fi
            ln -sf $ROOT/jbuild/Release/bin/ImgCreate images/ImgCreate

            cd $ROOT
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            share=$out/share/beef
            mkdir -p $share/bin $share/BeefLibs $out/bin

            install -Dm755 IDE/dist/BeefBuild       $share/bin/BeefBuild
            install -Dm755 IDE/dist/BeefIDE         $share/bin/BeefIDE
            install -Dm755 jbuild/Release/bin/ImgCreate      $share/bin/ImgCreate
            install -Dm755 jbuild/Release/bin/libhunspell.so $share/bin/libhunspell.so

            # The IDE copies libBeefRT.a into each project's build dir at link
            # time (and links against libBeefySysLib.a / libIDEHelper.a itself),
            # so these static libs must sit next to the BeefIDE binary.
            for lib in libBeefRT libBeefySysLib libIDEHelper; do
              install -Dm644 jbuild/Release/bin/$lib.a $share/bin/$lib.a
            done

            # BeefConfig_install.toml uses ../BeefLibs relative to the binary.
            if [ -f IDE/dist/BeefConfig_install.toml ]; then
              install -Dm644 IDE/dist/BeefConfig_install.toml $share/bin/BeefConfig.toml
            fi
            for f in BeefDbgVis.toml en_US.aff en_US.dic; do
              if [ -f IDE/dist/$f ]; then
                install -Dm644 IDE/dist/$f $share/bin/$f
              fi
            done
            for d in fonts images shaders; do
              if [ -d IDE/dist/$d ]; then
                cp -r IDE/dist/$d $share/bin/$d
              fi
            done

            cp -r BeefLibs/. $share/BeefLibs/

            # These symlinks pointed at /build/... for the boot step;
            # nixpkgs' noBrokenSymlinks check rejects any /build refs.
            rm -f $share/BeefLibs/Beefy2D/dist/libBeefRT.a \
                  $share/BeefLibs/Beefy2D/dist/libBeefySysLib.a \
                  $share/BeefLibs/Beefy2D/dist/libIDEHelper.a
            rm -f $share/bin/images/ImgCreate
            ln -sf ../ImgCreate $share/bin/images/ImgCreate

            libpath="${lib.makeLibraryPath ideRuntimeDeps}"
            makeWrapper $share/bin/BeefBuild $out/bin/BeefBuild \
              --prefix LD_LIBRARY_PATH : "$libpath"
            # BeefIDE writes DefaultLayout.toml relative to its own binary
            # (/proc/self/exe resolves symlinks, so only the binary itself must
            # be a real copy in a user-writable dir; everything else symlinks).
            cat > $share/bin/beef-ide-launcher << LAUNCHER_SCRIPT
#!${pkgs.bash}/bin/bash
set -euo pipefail
STORE_BIN="$share/bin"
BEEFLIBS="$share/BeefLibs"
USER_BEEF_DIR="\''${XDG_DATA_HOME:-\$HOME/.local/share}/beef"
VERSION_FILE="\$USER_BEEF_DIR/bin/.store-path"
if [ ! -f "\$VERSION_FILE" ] || [ "\$(cat "\$VERSION_FILE")" != "\$STORE_BIN" ]; then
    mkdir -p "\$USER_BEEF_DIR/bin"
    cp "\$STORE_BIN/BeefIDE" "\$USER_BEEF_DIR/bin/BeefIDE"
    chmod u+w "\$USER_BEEF_DIR/bin/BeefIDE"
    for f in "\$STORE_BIN"/*; do
        name="\$(basename "\$f")"
        [ "\$name" = "BeefIDE" ] && continue
        ln -sf "\$f" "\$USER_BEEF_DIR/bin/\$name"
    done
    ln -sfn "\$BEEFLIBS" "\$USER_BEEF_DIR/BeefLibs"
    echo "\$STORE_BIN" > "\$VERSION_FILE"
fi

# SDL 3.4.x falls back to XWayland on COSMIC because cosmic-comp
# currently does not advertise fifo-v1. BeefIDE's SDL popups have
# significant UI lag through XWayland, while native Wayland works
# correctly. Respect an explicit user override.
if [ -z "''${SDL_VIDEO_DRIVER:-}" ] &&
   [ "''${XDG_CURRENT_DESKTOP:-}" = "COSMIC" ]; then
    export SDL_VIDEO_DRIVER=wayland
fi

exec "\$USER_BEEF_DIR/bin/BeefIDE" "\$@"
LAUNCHER_SCRIPT
            chmod +x $share/bin/beef-ide-launcher

            makeWrapper $share/bin/beef-ide-launcher $out/bin/BeefIDE \
              --prefix LD_LIBRARY_PATH : "$libpath" \
              --prefix PATH : "${pkgs.gdb}/bin" \
              --prefix PATH : "${llvmPkgs.lldb}/bin"

            # Desktop entry + icon so the IDE shows up in the app launcher
            # (picked up automatically via environment.systemPackages /
            # home.packages, which merge share/applications and share/icons).
            install -Dm644 ${desktopItem}/share/applications/BeefIDE.desktop \
              $out/share/applications/BeefIDE.desktop
            install -Dm644 $src/IDE/Resources/beeflang.png \
              $out/share/icons/hicolor/128x128/apps/beeflang.png

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Beef programming language and IDE";
            homepage = "https://www.beeflang.org/";
            license = licenses.mit;
            platforms = [ "x86_64-linux" ];
            mainProgram = "BeefIDE";
          };
        };
      in {
        packages = {
          default = beef;
          beef = beef;
        };

        apps = {
          default = {
            type = "app";
            program = "${beef}/bin/BeefIDE";
          };
          BeefBuild = {
            type = "app";
            program = "${beef}/bin/BeefBuild";
          };
          BeefIDE = {
            type = "app";
            program = "${beef}/bin/BeefIDE";
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ beef ];
          packages = with pkgs; [
            gdb
            clang-tools
          ];
          shellHook = ''
            export LLVM_DIR=${llvmPkgs.llvm.dev}/lib/cmake/llvm
            echo "Beef dev shell ready (flake packaging)."
            echo "Build: nix build .#beef   |   Run IDE: nix run .#BeefIDE"
          '';
        };
      });
}
