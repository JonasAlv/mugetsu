#!/usr/bin/env bash
# Trigger GitHub Actions release or build locally
set -Eeuo pipefail

TAG="${1:-}"

if command -v gh >/dev/null 2>&1; then
    echo "=== Triggering GitHub Actions Release Workflow ==="
    if [ -n "$TAG" ]; then
        gh workflow run release.yml -f tag="$TAG"
        echo "Dispatched release workflow for tag: $TAG"
    else
        gh workflow run release.yml
        echo "Dispatched release workflow (auto-version)"
    fi
    echo "Track progress with: gh run list --workflow=release.yml"
else
    echo "=== Local Release Packaging ==="
    echo "Note: 'gh' CLI not found. Building and packaging locally..."
    bash source/build.sh
    
    VERSION=$(sed -n 's/^pub const VERSION: &str = "\([^"]*\)";.*/\1/p' source/build/ruffle/desktop/src/mugetsu.rs 2>/dev/null || echo "1.5.1")
    TAG="${TAG:-v$VERSION}"
    
    mkdir -p package/Mugetsu/LICENSES release
    cp source/build/out/Mugetsu package/Mugetsu/
    cp -r source/release-linux/* package/Mugetsu/ 2>/dev/null || true
    cp -r source/release/LICENSES/* package/Mugetsu/LICENSES/ 2>/dev/null || true
    cp LICENSE package/Mugetsu/LICENSES/Mugetsu-LICENSE-GPL-3.0.txt 2>/dev/null || true
    
    ARCHIVE="Mugetsu-$VERSION-linux.tar.gz"
    tar -C package --owner=0 --group=0 --numeric-owner -czf "release/$ARCHIVE" Mugetsu
    
    cd release
    sha256sum "$ARCHIVE" > SHA256SUMS.txt
    sha256sum ../source/build/out/Mugetsu >> SHA256SUMS.txt
    cd ..
    
    echo "Packaging complete in release/:"
    ls -lh source/build/out/Mugetsu release/
fi
