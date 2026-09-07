{
  description = "the libwebp tools (cwebp, dwebp, gif2webp, img2webp, webpinfo, webpmux) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libwebp installs six CLIs (cwebp, dwebp, gif2webp, img2webp, webpinfo,
  # webpmux); nix-lib folds them into one `libwebp` dispatcher binary with all
  # six tool names as argv[0]-dispatch UNPIN_META aliases.
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

      # Upstream turns TIFF input off for every static build — one blanket
      # `continue()` in cmake/deps.cmake, whose comment says only "it is
      # failing on Ubuntu". Every target we ship is static, so cwebp lost an
      # input format that the distro builds of this same 1.6.0 all read.
      #
      # The Ubuntu failure is libtiff's transitive libraries going missing from
      # the link line, and that is exactly what has to be supplied here: the
      # imported targets nixpkgs' TiffConfig.cmake names (Deflate::Deflate and
      # friends) are never created by anything, so config mode cannot be used
      # at all. CMake's own FindTIFF delegates to it first, under the name
      # `Tiff` and not `TIFF`, so that is the search to disable; FindTIFF then
      # falls back to looking for the archive on its own, and the codecs
      # libtiff.a calls into are appended by hand. Its WebP codec resolves
      # against the libwebp objects already in this link, so the binary never
      # carries a second copy of the library it is built from.
      withTiff = pkgs: drv: drv.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ (with pkgs; [ libdeflate xz zstd zlib ]);
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_DISABLE_FIND_PACKAGE_Tiff=ON" ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace cmake/deps.cmake \
            --replace-fail 'if(WEBP_LINK_STATIC AND ''${I_LIB} STREQUAL "TIFF")' \
              'if(FALSE)' \
            --replace-fail 'if(WEBP_DEP_IMG_INCLUDE_DIRS)' \
              'if(WEBP_HAVE_TIFF)
    list(APPEND WEBP_DEP_IMG_LIBRARIES deflate lzma zstd z)
  endif()
  if(WEBP_DEP_IMG_INCLUDE_DIRS)'
        '';
      });

      # cwebp on Windows never reaches the readers it was built with. Its
      # ReadPicture there tries WIC and, failing that, only ReadWebP — so the
      # PNM family, which WIC does not know, cannot be read at all, while
      # -longhelp goes on listing it because that list is built from the
      # libraries that were linked. Our own `dwebp -pam`/`-ppm`/`-pgm` output
      # is precisely what could not be fed back in.
      #
      # PNM has a signature, so route just that one family to the built-in
      # reader and leave everything else exactly as it was: WIC still gets
      # every format it knows, and the WebP fallback still follows it. Testing
      # the signature first also keeps WIC from printing a failure for a file
      # it was never going to read.
      #
      # TIFF stays out of the Windows link for the same reason: WIC already
      # reads it there, so libtiff would only be shadowed, at ~0.8 MB.
      withWinPnm = drv: drv.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace examples/cwebp.c \
            --replace-fail '    // If no size specified, try to decode it using WIC.
              ok = ReadPictureWithWIC(filename, pic, keep_alpha, metadata);
              if (!ok) {
                ok = ImgIoUtilReadFile(filename, &data, &data_size);
                ok = ok && ReadWebP(data, data_size, pic, keep_alpha, metadata);
              }' \
              '    ok = ImgIoUtilReadFile(filename, &data, &data_size);
              if (ok && WebPGuessImageType(data, data_size) == WEBP_PNM_FORMAT) {
                // WIC has no PNM decoder; the one linked in here does.
                ok = WebPGuessImageReader(data, data_size)(data, data_size, pic,
                                                           keep_alpha, metadata);
              } else {
                // If no size specified, try to decode it using WIC.
                ok = ReadPictureWithWIC(filename, pic, keep_alpha, metadata);
                ok = ok || (data != NULL &&
                            ReadWebP(data, data_size, pic, keep_alpha, metadata));
              }'
        '';
      });

      # 24x16 RGBA gradient, half of it translucent, gzipped so the constant
      # stays short; plus the two formats nothing we ship can write, so they
      # have to be carried in: a JPEG and a two-frame GIF.
      probePamB64 = "H4sIAAAAAAAC/w3MrZOfRgCAYfTPxKB3TmIiyiStQfQ6d+QyuXZ2MtevNTWYGPTKDCYGjcbEoNE1MejVmBj+jfYRj3nFG3+6/fn+4eXprn1ze3p8/+7p5e6HH28Pj1F6c/v1/q8/7p/v2rdvby+/x+eXv+Pj3cd3v/xz/xyf7m+Pvz08PXy8VdXn/27UBBpaOnoiiYGRzMTMwsrGXn3++V8OCicX1St/agINLR09kcTASGZiZmFlY3/lz0Hh5KIK/tQEGlo6eiKJgZHMxMzCysYe/DkonFxUr/2pCTS0dPREEgMjmYmZhZWN/bU/B4WTi6rzpybQ0NLRE0kMjGQmZhZWNvbOn4PCyUX1wZ+aQENLR08kMTCSmZhZWNnYP/hzUDi5qJI/NYGGlo6eSGJgJDMxs7CysSd/DgonF9Unf2oCDS0dPZHEwEhmYmZhZWP/5M9B4eSiyv7UBBpaOnoiiYGRzMTMwsrGnv05KJxcVF/8qQk0tHT0RBIDI5mJmYWVjf2LPweFk4tq8acm0NDS0RNJDIxkJmYWVjb2xZ+DwslF9dWfmkBDS0dPJDEwkpmYWVjZ2L/6c1A4uah2f2oCDS0dPZHEwEhmYmZhZWPf/TkonFxU3/ypCTS0dPREEgMjmYmZhZWN/Zs/B4WTi6r4UxNoaOnoiSQGRjITMwsrG3vx56BwclF996cm0NDS0RNJDIxkJmYWVjb27/4cFE4u/geIOYd+QwYAAA==";
      probeJpgB64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8lJCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIoOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAARCAAQABgDASIAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABgAF/8QAGBAAAgMAAAAAAAAAAAAAAAAAAAQFIjH/xAAWAQEBAQAAAAAAAAAAAAAAAAAFBAb/xAAcEQACAgIDAAAAAAAAAAAAAAAABSExAgMEImH/2gAMAwEAAhEDEQA/AAq8RlTTXiMqJl4jKmmvEZUr3MPQ9c1qQyvEZUhyvEZUg3NhNm347XpZ/9k=";
      probeGifB64 = "R0lGODlhCAAIAPAAAAAAAP9QFCH5BAAKAAAALAAAAAAIAAgAAAIxBEMwBEMwDMEQDMEQBEMwBEMwDMEQDMEQBEMwBEMwDMEQDMEQBEMwBEMwDMEQDMEQLAAh+QQACgAAACwAAAAACAAIAAACMQzBEAzBEARDMARDMAzBEAzBEARDMARDMAzBEAzBEARDMARDMAzBEAzBEARDMARDMCwAOw==";

      # Encode/decode guard. -lossless makes the round trip exact, so every
      # leg is a byte comparison against the original pixels rather than a
      # quality threshold, and each leg adds one library to the path: PAM is
      # libwebp alone, PNG brings in libpng, TIFF brings in libtiff.
      #
      # The TIFF leg drops the alpha first (through PPM). Not to dodge a
      # defect of ours: libtiff hands cwebp premultiplied samples whatever the
      # ExtraSamples tag says, so the translucent half comes back changed —
      # byte for byte the same change the dynamic nixpkgs cwebp makes, which
      # is the control that says it is libtiff's behaviour and not the fold's.
      #
      # This sits on the libwebp derivation, where the six tools are still six
      # programs in $out/bin; the fold into one `libwebp` happens later and is
      # what the smoke covers. So the guard tests the codecs and the smoke
      # tests the dispatch.
      withRoundTrip = pkgs: drv: drv.overrideAttrs (old: {
        doInstallCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
        installCheckPhase = ''
          runHook preInstallCheck
          b=$out/bin
          echo '${probePamB64}' | base64 -d | gzip -d > p.pam
          echo '${probeJpgB64}' | base64 -d > p.jpg
          echo '${probeGifB64}' | base64 -d > p.gif

          "$b/cwebp" -quiet -lossless p.pam -o a.webp
          "$b/dwebp" -quiet a.webp -pam -o a.pam
          cmp p.pam a.pam || { echo "the lossless round trip changed the pixels"; exit 1; }

          "$b/dwebp" -quiet a.webp -o a.png
          "$b/cwebp" -quiet -lossless a.png -o b.webp
          "$b/dwebp" -quiet b.webp -pam -o b.pam
          cmp p.pam b.pam || { echo "the PNG round trip changed the pixels"; exit 1; }

          "$b/dwebp" -quiet a.webp -ppm -o o.ppm
          "$b/cwebp" -quiet -lossless o.ppm -o o.webp
          "$b/dwebp" -quiet o.webp -tiff -o o.tif
          "$b/cwebp" -quiet -lossless o.tif -o t.webp
          "$b/dwebp" -quiet t.webp -ppm -o t.ppm
          cmp o.ppm t.ppm || { echo "the TIFF round trip changed the pixels"; exit 1; }

          "$b/cwebp" -quiet p.jpg -o j.webp
          "$b/webpinfo" j.webp | grep -q "Width: 24" || { echo "JPEG input did not decode"; exit 1; }

          "$b/gif2webp" -quiet p.gif -o anim.webp
          "$b/webpinfo" anim.webp | grep -q ANMF || { echo "gif2webp lost the animation"; exit 1; }
          "$b/webpmux" -get frame 1 anim.webp -o f1.webp
          test -s f1.webp || { echo "webpmux could not extract a frame"; exit 1; }
          "$b/img2webp" -o anim2.webp a.webp o.webp
          "$b/webpinfo" anim2.webp | grep -q ANMF || { echo "img2webp built no animation"; exit 1; }

          "$b/cwebp" -quiet -lossless p.pam -o - > s.webp
          cmp a.webp s.webp || { echo "stdout output differs from the file"; exit 1; }

          echo "installCheck: lossless round trip exact through PAM, PNG and TIFF; JPEG and GIF read; stdout clean"
          runHook postInstallCheck
        '';
      });

    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "libwebp";
      # Canonical binary == package name (libwebp); see header. A bare
      # `libwebp` names the six programs and asks for one, so the smoke has to
      # pick a program. The usage line is a literal in cwebp.c and names the
      # program, so it says which applet answered — a bare "Usage:" would also
      # match dwebp, and match what an unknown option prints. -longhelp has a
      # usage line of its own, not the one -h prints, so the pattern is that
      # one. Formats are the installCheck's job: the list differs by platform,
      # since Windows reads images through WIC.
      smoke = [ "--unpin-program=cwebp" "-longhelp" ];
      smokePattern = "^ cwebp \\[-preset";

      # Build via the unpin-llvm engine + emit a bitcode multicall module: the
      # engine compiles libwebp (apps on by default) to bitcode and the
      # standalone self-folds the six CLIs into one `libwebp` binary on every
      # target, windows included. Pure C — no requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [
          { name = "cwebp"; }
          { name = "dwebp"; }
          { name = "gif2webp"; }
          { name = "img2webp"; }
          { name = "webpinfo"; }
          { name = "webpmux"; }
        ];
      };
      build = pkgs: withRoundTrip pkgs (withTiff pkgs.pkgsStatic pkgs.pkgsStatic.libwebp);  # engine: apps → bitcode → selfFold
      windowsBuild = pkgs: withWinPnm (ulib.mingwStaticCross pkgs).libwebp;
    };
}
