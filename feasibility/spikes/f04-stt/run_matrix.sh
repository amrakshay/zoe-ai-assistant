#!/bin/zsh
# Runs the SpeechAnalyzer matrix over audio/manifest.tsv (or $1) with real-time 100 ms chunks.
cd "$(dirname "$0")"
M=${1:-audio/manifest.tsv}; D=${2:-audio}; OUT=${3:-results}
mkdir -p $OUT
for eng in st dt; do for loc in en-US en-IN; do for ctx in none ctx; do
  f=$OUT/${eng}_${loc}_${ctx}.jsonl
  args=(run --engine $eng --locale $loc)
  [[ $ctx == ctx ]] && args+=(--context context.txt)
  /usr/bin/time -l ./stt $args $M $D > $f 2> $OUT/${eng}_${loc}_${ctx}.time
  echo "$f: $(grep -c hyp $f) results, peak RSS $(awk '/maximum resident/{printf "%.1f MB", $1/1048576}' $OUT/${eng}_${loc}_${ctx}.time)"
done; done; done
