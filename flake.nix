{
  description = "the libwebp tools (cwebp, dwebp, gif2webp, img2webp, webpinfo, webpmux) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libwebp installs six CLIs (cwebp, dwebp, gif2webp, img2webp, webpinfo,
  # webpmux); ./multicall.nix post-links them into one `libwebp` dispatcher
  # binary with all six tool names as argv[0]-dispatch UNPIN_META aliases.
  # Windows goes through mingw — libwebp is portable CMake C that cross-compiles
  # cleanly (like brotli), and on Windows the tools use native Win32 threads, so
  # no pthread/winpthread runtime is dragged in.
  #
  # The canonical binary is named `libwebp` (= the package name) per the unpins
  # convention — the CI portability/smoke checks resolve `result/bin/<name>`, so
  # the dispatcher must carry the package name; the six tools are its aliases.
  # All six upstream man pages ship, matching nixpkgs' libwebp man output (no
  # winManRoot curation needed).
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "libwebp";
      # Canonical binary == package name (libwebp); see header. `libwebp
      # -version` reaches cwebp's main via the dispatcher fall-through and
      # prints the libwebp / libsharpyuv versions, exiting 0.
      smoke = [ "--unpin-program=cwebp" "-version" ];
      smokePattern = "1\\.6";

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles libwebp (apps on by default) to bitcode and the standalone
      # self-folds the six CLIs into one `libwebp` binary, on Linux and darwin
      # alike. Windows (mingw, no engine → native objects) goes through
      # windowsBuild's objcopy fold instead — objcopy cannot rewrite bitcode, so
      # ./multicall.nix must NOT run over an engine build. Pure C — no
      # requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        programs = [
          { name = "cwebp"; }
          { name = "dwebp"; }
          { name = "gif2webp"; }
          { name = "img2webp"; }
          { name = "webpinfo"; }
          { name = "webpmux"; }
        ];
      };
      build = pkgs: pkgs.pkgsStatic.libwebp;   # engine: apps → bitcode → selfFold
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; webp = (ulib.mingwStaticCross pkgs).libwebp; };
    };
}
