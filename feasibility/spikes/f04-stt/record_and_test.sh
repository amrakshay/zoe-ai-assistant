#!/bin/zsh
# F04 own-voice re-run: record yourself saying the same 15 phrases, then run the same
# SpeechAnalyzer matrix and WER/latency report on your recordings.
#
# Needs: ffmpeg (brew), microphone permission for the terminal app you run this from
# (macOS asks the first time). Run from a normal Terminal/iTerm window, not from inside Claude.
#
# Usage: ./record_and_test.sh            # record all 15, then test
#        ./record_and_test.sh --test-only  # re-test existing recordings in own_voice/
#        OUT=own_voice_holdout PHRASES=phrases_holdout.tsv ./record_and_test.sh   # held-out set
set -e
cd "$(dirname "$0")"
OUT=${OUT:-own_voice}
PHRASES=${PHRASES:-phrases.tsv}
mkdir -p $OUT
[[ -x ./stt ]] || ./build.sh

if [[ "$1" != "--test-only" ]]; then
  echo "Mic devices (pick the index you want; default 0):"
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n '/audio devices/,$p' | grep '\[' || true
  read "MIC?Audio device index [0]: "; MIC=${MIC:-0}
  touch $OUT/manifest.tsv
  # Phrases come from fd 3 so the Enter prompts read the keyboard (/dev/tty),
  # and ffmpeg gets -nostdin so it never treats keystrokes or phrase text as commands.
  # Resumable: phrases already saved (listed in the manifest) are skipped.
  while IFS=$'\t' read -r -u 3 id text; do
    grep -q "^${id}_me"$'\t' $OUT/manifest.tsv && continue
    raw=$OUT/${id}_raw.wav
    while true; do
      echo; echo "[$id]  Say:  \"$text\""
      # drop any stray Enter presses before asking
      while read -t 0.05 -k 1 < /dev/tty; do :; done 2>/dev/null || true
      read "?  Press Enter, then speak; press Enter again when done. " < /dev/tty
      rm -f $raw
      ffmpeg -nostdin -hide_banner -loglevel error -y -f avfoundation -i ":$MIC" -ac 1 -ar 16000 -sample_fmt s16 $raw &
      pid=$!
      read "?  (recording... Enter to stop) " < /dev/tty
      # SIGTERM, not SIGINT: a background job in a script may ignore SIGINT. Escalate if needed.
      kill -TERM $pid 2>/dev/null || true
      for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
      kill -KILL $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
      # trim leading/trailing silence so "last chunk" = end of speech (VAD would add ~0.7 s; use --pad to simulate)
      if [[ -s $raw ]] && ffmpeg -nostdin -hide_banner -loglevel error -y -i $raw \
          -af "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse" \
          -ac 1 -ar 16000 -sample_fmt s16 $OUT/${id}_me.wav 2>/dev/null; then
        dur=$(afinfo $OUT/${id}_me.wav | awk '/estimated duration/{print $3}')
        if (( dur > 0.8 )); then break; fi
      fi
      echo "  Too short or nothing recorded. Let's do this one again."
    done
    rm -f $raw
    printf "%s\tme\t%s\n" "${id}_me" "$text" >> $OUT/manifest.tsv
    echo "  saved, $dur s"
  done 3< $PHRASES
fi

./run_matrix.sh $OUT/manifest.tsv $OUT $OUT/results
# own voice is en-IN: treat speaker "me" as en-IN in the report
python3 wer.py $OUT/results $OUT/manifest.tsv -v | tee $OUT/report.md
echo; echo "Report: $PWD/$OUT/report.md"
