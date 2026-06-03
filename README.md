# libwebp

Standalone build of the [libwebp](https://chromium.googlesource.com/webm/libwebp)
command-line tools — Google's WebP image format encoder, decoder and utilities.

[![CI](https://github.com/unpins/libwebp/actions/workflows/libwebp.yml/badge.svg)](https://github.com/unpins/libwebp/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Tools

One binary provides all six libwebp CLIs:

| command    | what it does                          |
| ---------- | ------------------------------------- |
| `cwebp`    | encode PNG/JPEG → WebP                 |
| `dwebp`    | decode WebP → PNG/PNM                  |
| `gif2webp` | convert an (animated) GIF to WebP      |
| `img2webp` | build an animated WebP from frames     |
| `webpinfo` | print a WebP file's structure          |
| `webpmux`  | assemble / inspect WebP containers     |

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin libwebp cwebp in.png -o out.webp
unpin libwebp dwebp in.webp -o out.png
```

To install the programs onto your PATH:

```bash
unpin install libwebp
```

`unpin install libwebp` creates the `cwebp`, `dwebp`, `gif2webp`, `img2webp`, `webpinfo`, and `webpmux` commands.

## Build locally

```bash
nix build github:unpins/libwebp
./result/bin/cwebp -version
```

Or run directly:

```bash
nix run github:unpins/libwebp
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/libwebp/releases) page has standalone binaries for manual download.

## Build notes

- One multicall binary holds all six tools. Each tool's only unique object is
  its own `examples/<tool>.c.o`; everything else (libwebp / libwebpmux /
  libwebpdemux / libsharpyuv plus the png/jpeg/gif/zlib codecs) is a shared
  static archive linked once, so the binary carries a single copy of libwebp.
  `cwebp` is the canonical name; the others dispatch on `argv[0]`.
- The tools are folded together with the post-link `ld -r` + `objcopy
  --redefine-sym` recipe (rename each tool's `main` → `<tool>_main`), with the
  exact archive/codec link list read from CMake's per-tool `link.txt`.
- **Windows** is built with mingw: libwebp is portable CMake C and
  cross-compiles cleanly. The tools use native Win32 threads, so the `.exe`
  drags no pthread/winpthread runtime.
- PNG and JPEG input/output are linked in; GIF support (`gif2webp`) uses
  giflib. All codecs are static — there are no sidecar DLLs or shared objects.
