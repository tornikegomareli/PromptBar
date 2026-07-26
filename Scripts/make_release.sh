#!/usr/bin/env bash
# Build a release .app and zip it for distribution.
#
#   Scripts/make_release.sh            # uses MARKETING_VERSION from version.env
#   Scripts/make_release.sh 0.2.0      # overrides the version
#
# Produces dist/PromptBar-<version>.zip and prints the SHA-256 that the
# Homebrew cask needs.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)

source version.env
VERSION="${1:-$MARKETING_VERSION}"

# package_app.sh sources version.env itself, so an argument only takes effect
# if it is written back — which also keeps version.env the single source of
# truth for the version the bundle reports.
if [[ "$VERSION" != "$MARKETING_VERSION" ]]; then
  BUILD_NUMBER=$((BUILD_NUMBER + 1))
  printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$VERSION" "$BUILD_NUMBER" > version.env
  echo "==> version.env updated to $VERSION (build $BUILD_NUMBER)"
fi

APP_NAME=PromptBar
export APP_NAME
export BUNDLE_ID="${BUNDLE_ID:-com.promptbar.app}"
export MENU_BAR_APP=1

# Apple silicon only: the on-device model needs it, and the app declares so.
export ARCHES="${ARCHES:-arm64}"

# Sign with Developer ID when credentials are present, so the release is
# notarizable and installs without a Gatekeeper prompt. Falls back to ad-hoc.
[[ -f .signing.env ]] && source .signing.env
if [[ -n "${PROMPTBAR_SIGN_IDENTITY:-}" ]] \
   && security find-identity -v -p codesigning | grep -qF "$PROMPTBAR_SIGN_IDENTITY"; then
  export SIGNING_MODE=developer-id
  export APP_IDENTITY="$PROMPTBAR_SIGN_IDENTITY"
  SIGNED=1
else
  export SIGNING_MODE=adhoc
  SIGNED=0
  echo "==> No Developer ID found; building ad-hoc signed (not distributable)"
fi

echo "==> Regenerating icon"
Scripts/make_icon.sh >/dev/null

echo "==> Packaging ${APP_NAME}.app (${VERSION}, ${ARCHES})"
Scripts/package_app.sh release >/dev/null

if [[ "$SIGNED" == "1" ]]; then
  Scripts/sign_and_notarize.sh "$ROOT/${APP_NAME}.app"
fi

DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

ZIP="$DIST/${APP_NAME}-${VERSION}.zip"
echo "==> Creating $(basename "$ZIP")"
# ditto keeps the bundle's symlinks and metadata intact, which `zip` does not.
ditto -c -k --keepParent "$ROOT/${APP_NAME}.app" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

echo
echo "Artifact : $ZIP"
echo "Version  : $VERSION"
echo "Signing  : $([[ "$SIGNED" == "1" ]] && echo "Developer ID, notarized, stapled" || echo "ad-hoc")"
echo "SHA-256  : $SHA"
echo
echo "$SHA" > "$DIST/${APP_NAME}-${VERSION}.zip.sha256"
