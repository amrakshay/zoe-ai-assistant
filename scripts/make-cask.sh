#!/bin/sh
# Prints the Homebrew cask for a Zoe release. Usage: scripts/make-cask.sh VERSION SHA256
# Used by package-release.sh (local/CI builds) and the "Publish Homebrew cask" workflow (existing releases).
set -eu
VERSION=$1
SHA=$2
cat <<CASK
cask "zoe" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/amrakshay/zoe-ai-assistant/releases/download/v#{version}/Zoe-#{version}.zip"
  name "Zoe"
  desc "Voice assistant that works through Claude Code"
  homepage "https://github.com/amrakshay/zoe-ai-assistant"

  depends_on arch: :arm64
  depends_on formula: "uv"
  depends_on macos: :tahoe

  app "Zoe.app"

  zap trash: [
    "~/Library/Application Support/Zoe",
    "~/Library/Caches/io.github.amrakshay.zoe",
    "~/Library/Preferences/io.github.amrakshay.zoe.plist",
  ]

  caveats <<~EOS
    Zoe is free and not notarized by Apple, so macOS blocks the first launch:
      1. Open Zoe once (it will be blocked).
      2. System Settings → Privacy & Security → "Zoe was blocked…" → Open Anyway.
    Zoe uses your Claude Code login: run \`claude\` once and sign in if you haven't.
    The first launch downloads the core's dependencies (about 400 MB) and prepares the
    speech model (a few minutes, once).
  EOS
end
CASK
