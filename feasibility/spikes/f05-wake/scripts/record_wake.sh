#!/bin/zsh
# F05 own-voice wake-word test: record blocks of cued phrases, then score them with
# hey_claude.onnx (scripts/score_own.py). Each block records continuously while the
# script shows a cue every few seconds; scoring finds each utterance by its energy, so
# cue timing doesn't need to be exact.
#
# Usage: scripts/record_wake.sh              # record missing blocks, then score
#        scripts/record_wake.sh --score-only
# Resumable: blocks already saved in audio/own/ are skipped (delete one to redo it).
set -e
cd "${0:A:h}/.."
OUT=audio/own
mkdir -p $OUT

flush() { while read -t 0.05 -k 1 < /dev/tty; do :; done 2>/dev/null || true; }

record_block() {   # name, interval seconds, then the cue lines
  local name=$1 gap=$2; shift 2
  local f=$OUT/$name.wav
  [[ -s $f ]] && { echo "\n[$name] already recorded, skipping"; return; }
  echo "\n=== $name: ${#@} cues, one every ${gap} s ==="
  flush
  read "?  Press Enter to start. Say each line when it appears. " < /dev/tty
  ffmpeg -nostdin -hide_banner -loglevel error -y -f avfoundation -i ":$MIC" -ac 1 -ar 16000 -sample_fmt s16 $f.tmp.wav &
  local pid=$! n=0
  sleep 1.5
  for line in "$@"; do
    n=$((n+1)); echo "  [$n/${#@}]  >>  $line"; sleep $gap
  done
  echo "  (stopping)"; sleep 1
  kill -TERM $pid 2>/dev/null || true
  for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
  kill -KILL $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
  mv $f.tmp.wav $f
  afinfo $f | awk '/estimated duration/{print "  saved, " $3 " s"}'
}

record_free() {    # free speech until Enter
  local f=$OUT/free_talk.wav
  [[ -s $f ]] && { echo "\n[free_talk] already recorded, skipping"; return; }
  echo "\n=== free_talk: talk normally for about 3 minutes, WITHOUT saying \"hey Claude\" ==="
  echo "  Ideas: read a page or a Slack thread aloud, describe your day, or talk about work; the word \"Claude\" on its own is fine."
  flush
  read "?  Press Enter to start. " < /dev/tty
  ffmpeg -nostdin -hide_banner -loglevel error -y -f avfoundation -i ":$MIC" -ac 1 -ar 16000 -sample_fmt s16 $f.tmp.wav &
  local pid=$!
  read "?  (recording... Enter to stop) " < /dev/tty
  kill -TERM $pid 2>/dev/null || true
  for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
  kill -KILL $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
  mv $f.tmp.wav $f
  afinfo $f | awk '/estimated duration/{print "  saved, " $3 " s"}'
}

if [[ "$1" != "--score-only" ]]; then
  echo "Mic devices:"
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n '/audio devices/,$p' | grep '\[' || true
  read "MIC?Audio device index: " < /dev/tty

  H="Hey Claude"
  echo "\nFour blocks of \"Hey Claude\", one of near-misses, then free talk. About 10 minutes in all."
  echo "Sit at your normal distance from the laptop unless a block says otherwise."

  echo "\nBlock 1: say just \"Hey Claude\", in your normal voice."
  record_block pos_normal 3.5 $H $H $H $H $H $H $H $H $H $H

  echo "\nBlock 2: say the whole line, without pausing after \"Hey Claude\"."
  record_block pos_command 5 \
    "Hey Claude, what's on my calendar" "Hey Claude, show my Jira tickets" \
    "Hey Claude, is the build green" "Hey Claude, open the MR" \
    "Hey Claude, check Grafana" "Hey Claude, remind me at five" \
    "Hey Claude, summarise Slack" "Hey Claude, what time is it"

  echo "\nBlock 3: lean back or stand about 1.5-2 m from the laptop, and say \"Hey Claude\" a bit quieter."
  record_block pos_far 3.5 $H $H $H $H $H $H

  echo "\nBlock 4: say \"Hey Claude\" fast and casually, like you would when busy."
  record_block pos_fast 3 $H $H $H $H $H $H

  echo "\nBlock 5: near-misses. These must NOT wake it. Say each line as written."
  record_block neg_near 3.5 \
    "Hey cloud" "Hey clod" "Hey Claudia" "Hey Clyde" "Hey cloth" "Okay Claude" \
    "Hey, cloud sync" "Claude Code is open" "They clawed it" "A cloudy day" \
    "Hey, close it" "Hey Clara"

  record_free
fi

uv run --no-project --python 3.11 --with openwakeword==0.6.0 --with onnxruntime==1.32.0 \
  python scripts/score_own.py | tee results/own_voice.md
