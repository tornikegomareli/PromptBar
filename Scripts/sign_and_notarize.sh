#!/usr/bin/env bash
# Sign PromptBar.app with a Developer ID identity, notarize it with Apple, and
# staple the ticket so it launches without a Gatekeeper prompt.
#
#   Scripts/sign_and_notarize.sh <path-to-PromptBar.app>
#
# Credentials come from .signing.env (gitignored) or the environment:
#   PROMPTBAR_SIGN_IDENTITY   codesign identity
#   PROMPTBAR_TEAM_ID         Apple team id
#   PROMPTBAR_NOTARY_PROFILE  notarytool keychain profile name
#   PROMPTBAR_SKIP_NOTARIZE   set to 1 to sign only (local testing)
#
# No secret is stored in the repository: the Apple ID and app-specific password
# live in the macOS keychain under the notarytool profile.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$(pwd)

APP_PATH="${1:-$ROOT/PromptBar.app}"

[[ -f .signing.env ]] && source .signing.env

SIGN_IDENTITY="${PROMPTBAR_SIGN_IDENTITY:-}"
TEAM_ID="${PROMPTBAR_TEAM_ID:-}"
NOTARY_PROFILE="${PROMPTBAR_NOTARY_PROFILE:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "error: no signing identity. Copy .signing.env.example to .signing.env." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  echo "error: identity not in keychain: $SIGN_IDENTITY" >&2
  exit 1
fi

echo "==> Signing $(basename "$APP_PATH") with Developer ID"
# Hardened runtime and a secure timestamp are both required for notarization.
codesign --force --options runtime --timestamp \
         --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "${PROMPTBAR_SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "==> Skipping notarization (PROMPTBAR_SKIP_NOTARIZE=1)"
  exit 0
fi

if [[ -z "$NOTARY_PROFILE" ]] || \
   ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool profile '${NOTARY_PROFILE:-<unset>}' not found." >&2
  echo "Create it with:" >&2
  echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE:-promptbar-notary}\" \\" >&2
  echo "    --apple-id <apple-id> --team-id \"${TEAM_ID:-<team-id>}\" --password <app-specific-password>" >&2
  exit 1
fi

# Notarization takes a zip; the ticket is then stapled to the .app itself.
SUBMIT_ZIP="$(mktemp -d)/PromptBar-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ZIP"

echo "==> Submitting to Apple for notarization (this takes a few minutes)"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Gatekeeper assessment"
spctl --assess --type execute -vv "$APP_PATH"

echo "Signed, notarized, and stapled."
