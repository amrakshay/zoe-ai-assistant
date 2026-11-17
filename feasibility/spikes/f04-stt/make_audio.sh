#!/bin/zsh
# Generates synthetic test audio with `say`: 16 kHz mono 16-bit WAV.
# Voices alternate en-IN (Rishi, Aman, Tara) and en-US (Samantha, Fred).
cd "$(dirname "$0")"
mkdir -p audio
voices=(Rishi Samantha Aman Tara Fred)
i=0
while IFS=$'\t' read -r id text; do
  v=${voices[$(( i % ${#voices} + 1 ))]}
  say -v "$v" -o "audio/${id}_${v}.wav" --file-format=WAVE --data-format=LEI16@16000 "$text"
  printf "%s\t%s\t%s\n" "${id}_${v}" "$v" "$text"
  i=$((i+1))
done < phrases.tsv > audio/manifest.tsv
cat audio/manifest.tsv
