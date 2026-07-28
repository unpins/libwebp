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
      # cwebp links libjpeg-turbo for JPEG input. On riscv64 the vanilla
      # libjpeg-turbo fails to build (its RVV SIMD coverage helper references
      # jsimd_can_* symbols the new RVV port never defines); apply the shared
      # nix-lib fix, gated to riscv so other arches keep the cached build. Same
      # one chafa/heif/avif use.
      # On non-riscv, return scope.libwebp DIRECTLY (no `.extend`): the engine
      # path overrides scope.pkgsStatic.libwebp's stdenv via a plain `//` merge,
      # and re-deriving libwebp from an extended scope would discard that override
      # (the engine stdenv) — the link-capture sidecars the self-fold reads would
      # never be written. Only riscv needs the overlay (its libjpeg fix), and the
      # engine path isn't exercised there in a way that conflicts.
      withWebp = scope:
        let host = scope.stdenv.hostPlatform; in
        if host.isRiscV
        then (scope.extend (final: prev: {
          libjpeg = ulib.nativeFixes."libjpeg-turbo" prev;
        })).libwebp
        else scope.libwebp;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "libwebp";
      # Canonical binary == package name (libwebp); see header. `libwebp
      # -version` reaches cwebp's main via the dispatcher fall-through and
      # prints the libwebp / libsharpyuv versions, exiting 0.
      smoke = [ "-version" ];
      smokePattern = "1\\.6";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. On
      # Linux the engine compiles libwebp (apps on by default) to bitcode and the
      # standalone self-folds the six CLIs into one `libwebp` binary; darwin (no
      # engine) keeps the objcopy fold in ./multicall.nix; windows via
      # windowsBuild. Pure C — no requires.cxx. The bare `libwebp -version` smoke
      # falls through to cwebp, so defaultProgram pins it.
      engine = "unpin-llvm";
      multicall = {
        defaultProgram = "cwebp";
        programs = [
          { name = "cwebp"; }
          { name = "dwebp"; }
          { name = "gif2webp"; }
          { name = "img2webp"; }
          { name = "webpinfo"; }
          { name = "webpmux"; }
        ];
      };
      build = pkgs:
        if pkgs.stdenv.hostPlatform.isLinux
        then withWebp pkgs.pkgsStatic        # engine path: apps → bitcode → selfFold
        else import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; webp = withWebp pkgs.pkgsStatic; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; webp = withWebp (ulib.mingwStaticCross pkgs); };
    };
}
