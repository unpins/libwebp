# Changelog

## [Unreleased]

## [1.6.0-2] - 2026-09-26

### Fixed

- On Linux and macOS, `cwebp` could not read TIFF files, including the ones
  `dwebp -tiff` writes: upstream turns the format off in every static build, so
  every binary released so far answers `TIFF support not compiled`. It is
  compiled in now, with the same compression support the distro packages have,
  and those binaries grow by about two thirds because of it. Windows was never
  affected — it reads TIFF through the system image decoder — and does not
  grow.

- On Windows, `cwebp` could not read the PNM family at all — `.pam`, `.ppm`
  and `.pgm`, which is to say the files `dwebp -pam`, `-ppm` and `-pgm` write —
  even though `-longhelp` listed the format as supported. Image input there
  goes through the Windows Imaging Component, which has no PNM decoder, and
  nothing fell back to the decoder that was linked in. It does now.

- The README showed `unpin libwebp cwebp …`, which does not work — the program
  name goes in `--unpin-program=`. Corrected, and the installed-command form is
  now shown alongside it. The `nix build` example pointed at `result/bin/cwebp`,
  which does not exist either; the binary is `result/bin/libwebp`.

## [1.6.0-1] - 2026-06-06

First release: `cwebp`, `dwebp`, `gif2webp`, `img2webp`, `webpinfo` and
`webpmux` in one binary, for Linux, macOS and Windows.
