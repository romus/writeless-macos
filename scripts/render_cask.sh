#!/bin/bash
# Renders the Homebrew cask for a release.
#
#   ./scripts/render_cask.sh --version 2.0.0 --sha256 <sha> --output Casks/writeless.rb
#
# --url overrides the download URL (the release workflow points it at a local
# file:// archive for its smoke test).
set -euo pipefail

VERSION=""
SHA256=""
OUTPUT=""
URL=""
REPO="${GITHUB_REPOSITORY:-romus/writeless-macos}"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --sha256) SHA256="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

for required in VERSION SHA256 OUTPUT; do
  if [ -z "${!required}" ]; then
    echo "--${required,,} is required" >&2
    exit 1
  fi
done

HOMEPAGE="https://github.com/${REPO}"
if [ -n "$URL" ]; then
  URL_LINE="  url \"${URL}\""
else
  URL_LINE="  url \"${HOMEPAGE}/releases/download/v#{version}/Writeless-#{version}.zip\""
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
cask "writeless" do
  version "${VERSION}"
  sha256 "${SHA256}"

${URL_LINE}
  name "Write Less"
  desc "On-device speech-to-text from the menu bar"
  homepage "${HOMEPAGE}"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Write Less.app"

  # Releases are ad-hoc signed, so their code signature changes with every
  # build and Homebrew cannot carry the Gatekeeper approval across upgrades.
  # Without this, every update means another trip to Privacy & Security.
  # Remove this block once releases are signed with a stable identity.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Write Less.app"]
  end

  uninstall quit: "dev.romus.writeless"

  zap trash: [
    "~/Library/Application Support/Writeless",
    "~/Library/Caches/dev.romus.writeless",
    "~/Library/HTTPStorages/dev.romus.writeless",
    "~/Library/Preferences/dev.romus.writeless.plist",
  ]

  caveats <<~CAVEATS
    Write Less needs Microphone access on first launch, to record.

    Each transcript goes to the clipboard — press ⌘V to paste it.

    It downloads its speech model (about 630 MB) on first launch.
  CAVEATS
end
EOF

echo "Wrote $OUTPUT"
