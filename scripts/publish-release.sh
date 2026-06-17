#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
TAG="v${VERSION}"
ZIP_PATH="$ROOT_DIR/dist/Newsprint-${VERSION}.zip"
CASK_PATH="$ROOT_DIR/packaging/homebrew/Casks/newsprint.rb"
TAP_DIR="${HOMEBREW_TAP_DIR:-/tmp/homebrew-newsprint}"
TAP_REPO_URL="${HOMEBREW_TAP_REPO_URL:-https://github.com/ata-sesli/homebrew-newsprint.git}"
SOURCE_REPO="${SOURCE_REPO:-ata-sesli/newsprint}"

usage() {
  echo "Usage: scripts/publish-release.sh <version>" >&2
  echo "Example: scripts/publish-release.sh 1.0.1" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run() {
  echo "+ $*"
  "$@"
}

cd "$ROOT_DIR"

if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  usage
  exit 1
fi

require_command git
require_command gh
require_command shasum
require_command ditto

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before publishing." >&2
  git status --short >&2
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Could not determine current git branch." >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists locally: $TAG" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag already exists on origin: $TAG" >&2
  exit 1
fi

run scripts/package-release.sh "$VERSION"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Expected release zip was not created: $ZIP_PATH" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if ! grep -q "version \"$VERSION\"" "$CASK_PATH"; then
  echo "Cask version was not updated to $VERSION: $CASK_PATH" >&2
  exit 1
fi
if ! grep -q "sha256 \"$SHA256\"" "$CASK_PATH"; then
  echo "Cask checksum does not match $ZIP_PATH" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  run git add scripts/build-release-app.sh scripts/package-release.sh scripts/publish-release.sh packaging/homebrew/Casks/newsprint.rb docs/release-homebrew.md README.md
  run git commit -m "Release Newsprint ${TAG}"
fi

run git push origin "$CURRENT_BRANCH"
run git tag "$TAG"
run git push origin "$TAG"

run gh release create "$TAG" "$ZIP_PATH" \
  --repo "$SOURCE_REPO" \
  --title "Newsprint ${TAG}" \
  --notes "Newsprint ${TAG}"

if [[ -d "$TAP_DIR/.git" ]]; then
  run git -C "$TAP_DIR" pull --ff-only
else
  rm -rf "$TAP_DIR"
  run git clone "$TAP_REPO_URL" "$TAP_DIR"
fi

run mkdir -p "$TAP_DIR/Casks"
run cp "$CASK_PATH" "$TAP_DIR/Casks/newsprint.rb"

if [[ -n "$(git -C "$TAP_DIR" status --porcelain)" ]]; then
  run git -C "$TAP_DIR" add Casks/newsprint.rb
  run git -C "$TAP_DIR" commit -m "Update Newsprint to ${TAG}"
  run git -C "$TAP_DIR" push origin main
else
  echo "Tap repo already contains the current cask."
fi

cat <<EOF

Newsprint ${TAG} published.

Release:
  https://github.com/${SOURCE_REPO}/releases/tag/${TAG}

Zip:
  $ZIP_PATH

SHA256:
  $SHA256

Tap:
  $TAP_DIR/Casks/newsprint.rb

Test upgrade:
  brew update
  brew upgrade --cask newsprint
EOF
