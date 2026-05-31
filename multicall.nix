# libwebp ships six command-line tools — cwebp (encode), dwebp (decode),
# gif2webp / img2webp (animation), webpinfo and webpmux (container). To honour
# the unpins one-pkg-one-bin rule we post-link them into a single multicall
# binary at $out/bin/cwebp; `lib.withAliases` then embeds the other five names
# as an UNPIN_META block so unpin's installer recreates the argv[0] shims.
#
# Why a post-link route (no source patch): each tool is a separate CMake
# executable, but the only object unique to a tool is its own examples/<tool>.c.o
# (gif2webp adds gifdec.c.o). Everything else — libwebp / libwebpmux /
# libwebpdemux / libsharpyuv plus the imageio + example helper archives, plus
# the external image libs (png/jpeg/gif/z) — is a STATIC ARCHIVE shared by all
# six. So the multicall is the cheapest variant of the ld-r + prefix-rename
# recipe (cf. zip/util-linux): per tool, `ld -r` its unique object(s) into one
# relocatable object, then `objcopy --redefine-sym` renames `main` →
# <tool>_main and any other strong defined global → <tool>__foo so the six
# `main`s no longer collide. The shared archives are linked ONCE at the end, so
# the binary carries one copy of libwebp, not six. A dispatcher.c
# (basename(argv[0]) → <tool>_main) drives the final link.
#
# The archive + -l link list is read straight out of each tool's CMake
# link.txt at build time, so the exact store paths, threading libs and image
# codecs the build actually configured are reused verbatim on every platform
# (musl ELF / Mach-O / mingw) — no hard-coded dependency set to drift.
#
# Shared by the native `build` (pkgsStatic) and the `windowsBuild`
# (mingwStaticCross) paths; isDarwin/isWindows come from the INPUT derivation's
# stdenv (under windowsBuild `pkgs` is the x86_64-linux root — the cross lives
# inside mingwStaticCross — so `pkgs.stdenv` would wrongly say "not Windows").
{ lib }:
{ pkgs, webp }:
let
  isDarwin = webp.stdenv.hostPlatform.isDarwin or false;
  isWindows = webp.stdenv.hostPlatform.isWindows or false;

  multicall = webp.overrideAttrs (old: {
    pname = "libwebp-multi";
    outputs = [ "out" ];

    # Build the static archives (and the six CLIs) rather than the shared libs
    # the nixpkgs expr asks for — we re-link the tools ourselves. Appended last
    # so it wins over the expr's BUILD_SHARED_LIBS=TRUE.
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_SHARED_LIBS:BOOL=FALSE" ];

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p mc
      TOOLS="cwebp dwebp gif2webp img2webp webpinfo webpmux"

      # The source(s) unique to each tool; everything else is a shared archive.
      # CMake names objects <src>.c.o on ELF/Mach-O but <src>.c.obj on MinGW —
      # detect which from cwebp's object.
      declare -A TSRC
      TSRC[cwebp]="cwebp"
      TSRC[dwebp]="dwebp"
      TSRC[gif2webp]="gif2webp gifdec"
      TSRC[img2webp]="img2webp"
      TSRC[webpinfo]="webpinfo"
      TSRC[webpmux]="webpmux"
      oext=o
      [ -f "CMakeFiles/cwebp.dir/examples/cwebp.c.obj" ] && oext=obj
      declare -A TOBJ
      for t in $TOOLS; do
        o=""
        for s in ''${TSRC[$t]}; do o="$o CMakeFiles/$t.dir/examples/$s.c.$oext"; done
        TOBJ[$t]="$o"
      done

      # Harvest the link list from the tools' CMake link.txt. Internal archives
      # are the relative lib*.a tokens; external are absolute *.a paths and -l*
      # flags. MinGW CMake puts the libraries in an `@…linkLibs.rsp` response
      # file (and quotes absolute paths), so expand any `@file` token and strip
      # surrounding quotes. Skip the per-tool `objects.a` bundle (its objects
      # are already in MCOBJS, renamed) and `*.dll.a` import libs. Dedup,
      # first-seen order (dependency-correct: a consumer precedes its provider).
      INT=""; EXT=""
      classify() {
        local tok="$1"
        tok="''${tok%\"}"; tok="''${tok#\"}"
        case "$tok" in
          *objects.a | *.dll.a) ;;
          lib*.a)     case " $INT " in *" $tok "*) ;; *) INT="$INT $tok" ;; esac ;;
          -l*)        case " $EXT " in *" $tok "*) ;; *) EXT="$EXT $tok" ;; esac ;;
          /*.a|*/*.a) case " $EXT " in *" $tok "*) ;; *) EXT="$EXT $tok" ;; esac ;;
        esac
      }
      for t in $TOOLS; do
        for tok in $(tr ' ' '\n' < "CMakeFiles/$t.dir/link.txt"); do
          case "$tok" in
            @*) rf="''${tok#@}"
                [ -f "$rf" ] && for rt in $(tr ' ' '\n' < "$rf"); do classify "$rt"; done ;;
            *)  classify "$tok" ;;
          esac
        done
      done

      # Mach-O leads C symbols with '_'; detect once from cwebp's object.
      if $NM --defined-only ''${TOBJ[cwebp]} 2>/dev/null | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      # Per tool, build ONE redef map (main → <t>_main, every other strong
      # defined global foo → <t>__foo; skip weak/COMDAT W/V and names with a
      # '.') from the tool's raw object(s), then apply it to each raw object —
      # objcopy rewrites the definition AND every relocation, so a multi-object
      # tool (gif2webp's gifdec helpers) stays internally consistent and the
      # six `main`s no longer collide. The renamed raw objects, not an `ld -r`
      # partial, go into the final link: ld64's `-r` demotes a `main` that owns
      # function-local statics from global (T) to local (t), which would make
      # the map empty and leave <t>_main undefined on darwin.
      MCOBJS=""
      for t in $TOOLS; do
        $NM --defined-only ''${TOBJ[$t]} 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3; core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "mc/$t.redef"
        for o in ''${TOBJ[$t]}; do
          d="mc/$t.$(basename "$o")"
          cp "$o" "$d"
          [ -s "mc/$t.redef" ] && $OBJCOPY --redefine-syms="mc/$t.redef" "$d"
          MCOBJS="$MCOBJS $d"
        done
      done

      # Dispatcher: basename(argv[0]) → <tool>_main. The canonical name (cwebp)
      # and any unknown argv[0] fall through to a `cwebp <applet> …` form and
      # finally to cwebp_main, so the bare binary stays callable and survives a
      # rename (CI smoke copies it to smoke.exe).
      {
        echo '#include <string.h>'
        for t in $TOOLS; do echo "int ''${t}_main(int, char **);"; done
        echo 'struct ap { const char *n; int (*f)(int, char **); };'
        echo 'static const struct ap aps[] = {'
        for t in $TOOLS; do echo "    {\"$t\", ''${t}_main},"; done
        cat <<'CBODY'
    {0, 0}
};
static void base_of(char *d, size_t cap, const char *s) {
    const char *p = s, *x;
    x = strrchr(p, '/'); if (x) p = x + 1;
#ifdef _WIN32
    x = strrchr(p, '\\'); if (x) p = x + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(d, p, n); d[n] = 0;
    if (n > 4 && strcmp(d + n - 4, ".exe") == 0) d[n - 4] = 0;
}
int main(int argc, char **argv) {
    char b[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "cwebp";
    base_of(b, sizeof b, a0);
    for (const struct ap *a = aps; a->n; a++)
        if (strcmp(b, a->n) == 0) return a->f(argc, argv);
    /* canonical/unknown argv[0]: allow `cwebp <applet> [args]`, else cwebp. */
    if (argc >= 2) {
        char c[64]; base_of(c, sizeof c, argv[1]);
        for (const struct ap *a = aps; a->n; a++)
            if (strcmp(c, a->n) == 0) return a->f(argc - 1, argv + 1);
    }
    return cwebp_main(argc, argv);
}
CBODY
      } > mc/dispatcher.c
      $CC -O2 -c -o mc/dispatcher.o mc/dispatcher.c

      # Final link: shared archives + image-codec libs, once. On GNU-ld targets
      # wrap the archives in a group to absorb any back-reference; ld64 (darwin)
      # rejects --start-group but re-scans archives on its own, so list them
      # plain there. -pthread is intentionally dropped: every target pulls its
      # thread primitives from libc (musl) / libSystem / win32, never a separate
      # pthread lib, and -pthread would drag libwinpthread on mingw.
      if ${if isDarwin then "true" else "false"}; then
        GO=""; GC=""
      else
        GO="-Wl,--start-group"; GC="-Wl,--end-group"
      fi
      # mingw: this manual link bypasses the `-static` the normal
      # mingwStaticCross build applies, so the gcc `mcf` thread model
      # (pulled by libwebp's encoder worker threads) imports libmcfgthread-2.dll
      # next to the .exe — breaking the single-binary promise. Link the runtime
      # fully static so every -l (incl. the driver's implicit -lmcfgthread)
      # resolves to its .a; the only imports left are real Windows system DLLs.
      MCF=""
      ${lib.optionalString isWindows ''MCF="-static"''}
      $CC -O2 \
        $MCOBJS mc/dispatcher.o \
        $GO $INT $EXT $GC -lm $MCF \
        -o mc/cwebp
      [ -f mc/cwebp ] || mv mc/cwebp.exe mc/cwebp
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 mc/cwebp "$out/bin/cwebp"
      for a in dwebp gif2webp img2webp webpinfo webpmux; do ln -s cwebp "$out/bin/$a"; done

      # Man pages live in the source tree (man/<tool>.1); ship all six so the
      # set matches nixpkgs' libwebp man output (no winManRoot needed).
      mandir=""
      for d in ../man man "$src/man"; do [ -f "$d/cwebp.1" ] && mandir="$d" && break; done
      if [ -n "$mandir" ]; then
        for m in cwebp dwebp gif2webp img2webp webpinfo webpmux; do
          [ -f "$mandir/$m.1" ] && cp "$mandir/$m.1" "$out/share/man/man1/$m.1"
        done
      fi
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "cwebp";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/cwebp" ] && mv "$out/bin/cwebp" "$out/bin/cwebp.exe"
  '';
})
else aliased
