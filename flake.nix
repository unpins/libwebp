{
  description = "Standalone build of the libwebp tools";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libwebp installs six CLIs (cwebp, dwebp, gif2webp, img2webp, webpinfo,
  # webpmux); ./multicall.nix post-links them into one `cwebp` binary with the
  # other five as argv[0]-dispatch UNPIN_META aliases. Windows goes through
  # mingw — libwebp is portable CMake C that cross-compiles cleanly (like
  # brotli), and on Windows the tools use native Win32 threads, so no
  # pthread/winpthread runtime is dragged in.
  #
  # `cwebp` is the canonical binary because it is the flagship tool and matches
  # a real upstream man page, so the shipped man set (all six pages) equals
  # nixpkgs' libwebp man output and no winManRoot curation is needed.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # cwebp links libjpeg-turbo for JPEG input. On riscv64 the vanilla
      # libjpeg-turbo fails to build (its RVV SIMD coverage helper references
      # jsimd_can_* symbols the new RVV port never defines); apply the shared
      # nix-lib fix, gated to riscv so other arches keep the cached build. Same
      # one chafa/heif/avif use.
      withWebp = scope:
        let host = scope.stdenv.hostPlatform; in
        (scope.extend (final: prev:
          scope.lib.optionalAttrs host.isRiscV {
            libjpeg = ulib.nativeFixes."libjpeg-turbo" prev;
          })).libwebp;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "libwebp";
      binName = "cwebp";
      # `cwebp -version` prints the libwebp / libsharpyuv versions and exits 0.
      smoke = [ "-version" ];
      smokePattern = "1\\.6";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; webp = withWebp pkgs.pkgsStatic; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; webp = withWebp (ulib.mingwStaticCross pkgs); };
    };
}
