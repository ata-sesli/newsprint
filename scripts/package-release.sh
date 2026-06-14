#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_DIR="$ROOT_DIR/dist/Newsprint.app"
ZIP_PATH="$ROOT_DIR/dist/Newsprint-${APP_VERSION}.zip"
CASK_PATH="$ROOT_DIR/packaging/homebrew/Casks/newsprint.rb"
RELEASE_URL="https://github.com/ata-sesli/newsprint/releases/new?tag=v${APP_VERSION}"

cd "$ROOT_DIR"

echo "Building Newsprint ${APP_VERSION}..."
APP_VERSION="$APP_VERSION" scripts/build-release-app.sh

if [[ ! -d "$APP_DIR" ]]; then
  echo "Expected app bundle was not created: $APP_DIR" >&2
  exit 1
fi

rm -f "$ZIP_PATH"
echo "Creating $ZIP_PATH..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Expected release zip was not created: $ZIP_PATH" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

if [[ -f "$CASK_PATH" ]]; then
  perl -0pi -e "s/(sha256 \")[0-9a-f]{64}(\")/\${1}$SHA256\${2}/" "$CASK_PATH"
fi

cat <<EOF

Newsprint ${APP_VERSION} package is ready.

Zip:
  $ZIP_PATH

SHA256:
  $SHA256

GitHub Release upload target:
  $RELEASE_URL

Homebrew cask template:
  $CASK_PATH

Manual release checklist:
  1. Create and push tag v${APP_VERSION}.
  2. Create GitHub Release v${APP_VERSION}.
  3. Upload $(basename "$ZIP_PATH") to that release.
  4. Copy $CASK_PATH to ata-sesli/homebrew-newsprint/Casks/newsprint.rb.
  5. Commit and push the tap repo.
  6. Test: brew install --cask ata-sesli/newsprint/newsprint
EOF
