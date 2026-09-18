# libwebp

The [libwebp](https://chromium.googlesource.com/webm/libwebp) command-line programs — Google's WebP image format encoder, decoder and supporting programs. A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/libwebp/actions/workflows/libwebp.yml/badge.svg)](https://github.com/unpins/libwebp/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install libwebp`.

Encode, decode and inspect WebP images.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin libwebp --unpin-program=cwebp in.png -o out.webp
unpin libwebp --unpin-program=dwebp in.webp -o out.png
```

Or install them and call each by name, which is usually what you want:

```bash
unpin install libwebp
cwebp in.png -o out.webp
```

`unpin install libwebp` creates all six commands.

## Programs

| program | what it does |
|---|---|
| `cwebp` | encode a PNG, JPEG, TIFF or PNM image to WebP |
| `dwebp` | decode a WebP image to PNG, PAM, PPM, PGM, BMP, TIFF or raw YUV |
| `gif2webp` | convert a GIF, animation included, to an animated WebP |
| `img2webp` | build an animated WebP from a sequence of still images |
| `webpinfo` | print the chunk structure of a WebP file |
| `webpmux` | assemble, split and edit WebP containers and their metadata |

Each prints its version with `-version` and its options with `-h`, one dash.

## Build locally

```bash
nix build github:unpins/libwebp
./result/bin/libwebp --unpin-program=cwebp -version
```

Or run directly:

```bash
nix run github:unpins/libwebp
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/libwebp/releases) page has standalone binaries for manual download.

## Build notes

- One binary holds all six tools. Each tool's only unique object is its own
  `examples/<tool>.c.o`; everything else — libwebp, libwebpmux, libwebpdemux
  and libsharpyuv, plus the png/jpeg/tiff/gif/zlib codecs — is linked once, so
  the binary carries a single copy of libwebp. The binary is named `libwebp`
  and each tool answers to its own name.
- TIFF input is compiled in on Linux and macOS. Upstream turns it off for
  every static build, and that left `cwebp` unable to read a file `dwebp
  -tiff` had just written; the build here supplies libtiff's own compression
  libraries so the format works as it does in the distro packages. It is what
  the extra size buys.
- **Windows** is built with mingw. Image input there goes through the
  Windows Imaging Component, which already reads TIFF but knows nothing of
  PNM, which is routed to the reader built in alongside it.
- All codecs are static — there are no sidecar DLLs or shared objects.
