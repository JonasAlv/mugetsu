#!/usr/bin/env bash
# Build Mugetsu from Ruffle's source on Linux (Wayland or X11).
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORK="${ROOT}/build"
RUFFLE="${WORK}/ruffle"
OUT="${WORK}/out"
COMMIT="$(tr -d '[:space:]' < "${ROOT}/RUFFLE_COMMIT")"
REMOTE="${MUGETSU_RUFFLE_REMOTE:-https://github.com/ruffle-rs/ruffle.git}"
NO_PGO=0
PREPARE_ONLY=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--no-pgo] [--prepare-only]

Build Mugetsu's Linux binary from the pinned Ruffle commit.
The resulting binary is: source/build/out/Mugetsu

Environment:
  MUGETSU_RUFFLE_REMOTE  Ruffle git remote or local clone
  MUGETSU_CRATES_DIR     directory containing wgpu-core-30.0.1,
                         wgpu-hal-30.0.1 and gc-arena-0.7.0
USAGE
}
while (($#)); do
    case "$1" in
        --no-pgo) NO_PGO=1 ;;
        --prepare-only) PREPARE_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

run() { "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
command -v git >/dev/null || die "git is required"
command -v cargo >/dev/null || die "cargo is required"
command -v rustc >/dev/null || die "rustc is required"
command -v java >/dev/null || die "Java 17 or newer is required"

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    echo "=> Wayland session detected; building the normal winit Wayland/X11 desktop target"
elif [[ -n "${DISPLAY:-}" ]]; then
    echo "=> X11 session detected; building the normal winit Wayland/X11 desktop target"
else
    echo "=> No display session detected; building headlessly (runtime needs Wayland or X11)"
fi

rm -rf "$RUFFLE" "$OUT"
mkdir -p "$RUFFLE" "$WORK"
git -C "$RUFFLE" init -q
git -C "$RUFFLE" fetch -q --depth 1 "$REMOTE" "$COMMIT"
git -C "$RUFFLE" -c advice.detachedHead=false checkout -q FETCH_HEAD

echo "=> Applying Mugetsu Ruffle patch"
git -C "$RUFFLE" apply --whitespace=nowarn "$ROOT/patches/ruffle.patch"

CRATES=(
    "wgpu-core:30.0.1"
    "wgpu-hal:30.0.1"
    "gc-arena:0.7.0"
)
mkdir -p "$RUFFLE/patches"
for spec in "${CRATES[@]}"; do
    name="${spec%%:*}"
    version="${spec##*:}"
    full="${name}-${version}"
    dest="$RUFFLE/patches/$name"
    rm -rf "$dest"
    if [[ -n "${MUGETSU_CRATES_DIR:-}" ]]; then
        cp -a "$MUGETSU_CRATES_DIR/$full" "$dest" || die "Missing crate: $MUGETSU_CRATES_DIR/$full"
    else
        archive="$WORK/$full.crate"
        echo "=> Downloading $full"
        curl --fail --location --silent --show-error \
            "https://static.crates.io/crates/$name/$full.crate" -o "$archive"
        tmp="$WORK/crates/$full"
        rm -rf "$tmp"
        mkdir -p "$WORK/crates"
        tar -xzf "$archive" -C "$WORK/crates"
        mv "$tmp" "$dest"
    fi
    rm -f "$dest/.cargo_vcs_info.json"
    git -C "$RUFFLE" apply --whitespace=nowarn -p1 \
        --directory="patches/$name" "$ROOT/patches/$name.patch"
done

if ((PREPARE_ONLY)); then
    echo "=> Patched source ready: $RUFFLE"
    exit 0
fi

# Keep the release profile equivalent to build.ps1. Linux uses the normal dynamic
# system runtime so proc-macros and Wayland/X11 libraries link correctly. x86-64-v3 requires AVX2;
# pass MUGETSU_RUSTFLAGS to override this for older x86-64 CPUs.
# Linux proc-macros cannot be linked with the Windows CRT-static setting.
flags=("-Ctarget-cpu=x86-64-v3" \
    "--remap-path-prefix=$RUFFLE=ruffle" "--remap-path-prefix=$HOME=home")
if [[ -n "${CARGO_HOME:-}" ]]; then
    flags+=("--remap-path-prefix=$CARGO_HOME=cargo")
fi
if [[ -n "${MUGETSU_RUSTFLAGS:-}" ]]; then
    flags=( ${MUGETSU_RUSTFLAGS} )
elif ((NO_PGO == 0)); then
    # Linux rustc can consume the same LLVM profile data as the Windows build.
    pgo="$WORK/pgo"
    rm -rf "$pgo"
    mkdir -p "$pgo"
    unzip -q -o "$ROOT/pgo/aqw.profdata.zip" -d "$pgo"
    profdata="$(find "$pgo" -type f -name '*.profdata' -print -quit)"
    [[ -n "$profdata" ]] || die "No .profdata file found in the PGO archive"
    flags+=("-Cprofile-use=$profdata")
fi
export RUSTFLAGS="${flags[*]}"
export CARGO_TARGET_DIR="$WORK/target"

# winit selects the available Wayland/X11 backend at runtime. No custom title-bar
# flag is needed: the Windows title-bar menu is compiled only for Windows.
echo "=> Building Mugetsu Linux binary"
(cd "$RUFFLE" && cargo build --locked --package ruffle_desktop --profile dist)
mkdir -p "$OUT"
cp -f "$CARGO_TARGET_DIR/dist/ruffle_desktop" "$OUT/Mugetsu"
chmod +x "$OUT/Mugetsu"
echo "=> Built: $OUT/Mugetsu"
