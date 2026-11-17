#!/bin/zsh
# Builds the spike with swiftc (Command Line Tools only). Info.plist is embedded so TCC can show a speech-recognition prompt.
cd "$(dirname "$0")"
swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 stt.swift -o stt \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
codesign -s - -f --identifier local.voice-assistant.f04-stt stt
