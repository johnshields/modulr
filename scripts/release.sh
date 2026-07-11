#!/bin/bash
# Build, notarise, publish a Modulr release and bump the cask.
# Version comes from Info.plist (set CFBundleShortVersionString in run.sh first).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/Modulr.app"
CASK="Casks/modulr.rb"

command -v gh >/dev/null || { echo "gh CLI required." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login" >&2; exit 1; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || { echo "Release from main only (on $BRANCH)." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean; commit or stash first." >&2; exit 1; }

# Build + sign + notarise + DMG. package.sh prints the version and sha256.
./scripts/package.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Modulr-$VERSION.dmg"
TAG="v$VERSION"
[ -f "$DMG" ] || { echo "Missing $DMG." >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

gh release view "$TAG" >/dev/null 2>&1 && { echo "Release $TAG already exists." >&2; exit 1; }

echo
echo "About to publish:"
echo "  tag     $TAG"
echo "  dmg     $DMG"
echo "  sha256  $SHA"
read -r -p "Publish and push? [y/N] " reply
[ "$reply" = "y" ] || { echo "Aborted."; exit 0; }

# Bump the in-repo cask to the new version + sha.
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

# Tag, publish the DMG, then land the cask bump.
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --title "Modulr $VERSION" --notes "Modulr $VERSION"
git add "$CASK"
git commit -m "release: $TAG"
git push origin main

echo
echo "Released $TAG."
echo "Sync the Homebrew tap (fromlost/homebrew-modulr) with:"
echo "  version \"$VERSION\"  sha256 \"$SHA\""
