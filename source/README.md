# Mugetsu source

Mugetsu is [Ruffle](https://github.com/ruffle-rs/ruffle) (the open-source Flash Player emulator)
with changes for AdventureQuest Worlds. This folder holds those changes as patches on top of
Ruffle, plus scripts that build the Windows and Linux binaries from them.

Every release is built from this folder by GitHub Actions (`.github/workflows/build.yml`); each
run's page shows the build log and the SHA-256 of the zip it made, which matches the file on the
release page.

## What's here

| File | What it is |
|---|---|
| `RUFFLE_COMMIT` | The Ruffle commit Mugetsu is based on (nightly of 2026-10-02) |
| `RUST_VERSION` | The Rust version releases are built with |
| `patches/ruffle.patch` | All of Mugetsu's changes to Ruffle |
| `patches/wgpu-core.patch`, `wgpu-hal.patch`, `gc-arena.patch` | Changes to three libraries Ruffle uses (wgpu-core 30.0.1, wgpu-hal 30.0.1, gc-arena 0.7.0 from crates.io) |
| `pgo/aqw.profdata.zip` | The speed profile (PGO): counts of which code runs most while playing AQW, recorded with a measuring build. The compiler uses it to optimize for real play. It holds function names and counts only. |
| `build.ps1` | Downloads Ruffle at `RUFFLE_COMMIT` and the three libraries, applies the patches and builds |
| `build.sh` | Downloads the same pinned sources, applies the patches and builds the Linux binary |
| `release/` | The other files in the release zip (readme, license texts, notices) |
| `notes/` | Release notes, used for the draft release |

## Building it yourself (Windows)

You need [Rust](https://rustup.rs) (`rustup toolchain install 1.99.0`), Java 17 or newer (Ruffle
compiles its Flash classes with it) and git. Then, in this folder:

```
powershell -ExecutionPolicy Bypass -File build.ps1
```

The result is `build\out\Mugetsu.exe`. `-NoPgo` builds without the speed profile. A build takes
a while: Ruffle is a large program.

Your build won't be byte-for-byte identical to a release (file paths and the machine differ), but
it's made from the same code the same way.

## Building it yourself (Linux)

You need Rust (`rustup toolchain install 1.99.0`), Java 17 or newer, git, and the usual desktop
development libraries for Wayland/X11. From this folder, run:

```
./build.sh
```

The result is `build/out/Mugetsu`. Use `./build.sh --no-pgo` to skip the speed profile, or
`./build.sh --prepare-only` to fetch and patch the source without compiling. The binary uses
Ruffle's normal winit Wayland/X11 backend and native window decorations.

## What the changes do

Speed:
- Drawing work spread over all CPU cores; effect layers sized to their content and drawn
  together on shared canvases; glows and blurs drawn in batches; reused graphics memory.
- Shapes prepared on all cores, once, at the size they're drawn at (no stutter when entering a
  crowded room); mouse movement applied once per frame; steadier frame pacing and memory
  cleanup.
- Memory leaks fixed (weak-keyed `Dictionary`, unused game files freed), plus a faster memory
  allocator.
- DirectX 12: a faster command recorder and fixes, used by default on Intel and Qualcomm
  graphics.

Looking and working like Flash:
- 9-slice scaling (`scale9Grid`): stretched boxes keep their corners.
- Fonts: device-font substitutes with the right weight, embedded fonts looked up in Flash's
  order.
- Cutscenes stop at their Next buttons, chat scrolls and can be selected, newer Flash APIs are
  available to AQW, and more.

The app around it: AQW's address and settings built in, graphics card choice in the title-bar
menu, crash and update messages, a Quality tip for built-in graphics, and a performance log
(`%LOCALAPPDATA%\ruffle\log\ruffle.log`).

Comments in the code marked `AQW build:` explain each change.

## License

Mugetsu's changes are licensed under the GNU General Public License 3.0 (see `LICENSE` at the
top of this repository). Ruffle is dual-licensed MIT / Apache-2.0, wgpu-core and wgpu-hal are
MIT / Apache-2.0 and gc-arena is MIT / CC0; their licenses still apply to their code, and the
release zip includes all license texts and notices.

Mugetsu isn't affiliated with or endorsed by Artix Entertainment or the Ruffle project.
