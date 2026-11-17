#!/bin/zsh
# F04 Whisper run: WhisperKit CLI (Core ML, Neural Engine) on the own-voice recordings,
# with and without a term prompt. Writes wer.py-compatible JSONL to own_voice/results/.
#
# Needs: brew install whisperkit-cli. The model (~1.5 GB) is downloaded into whisper_models/
# on first use; delete that folder to reclaim the space.
#
# Latency = WhisperKit's fullPipeline time for the whole utterance (log-mel + encode + decode),
# i.e. the delay between end of speech and the final text in a "Whisper for the final" design.
# Model load is excluded (the app keeps the model loaded).
#
# Modes: none (no prompt), prompt (comma list of terms), sentence (terms in a sentence).
# DIR=own_voice_holdout for the held-out set.
# Usage: [DIR=...] [MODES="none prompt sentence"] ./run_whisper.sh [model]   default: large-v3-v20240930_turbo
set -e
cd "$(dirname "$0")"
DIR=${DIR:-own_voice}
MODEL=${1:-large-v3-v20240930_turbo}
MDIR=whisper_models/models/argmaxinc/whisperkit-coreml/openai_whisper-$MODEL
if [[ ! -d $MDIR ]]; then
  whisperkit-cli transcribe --model $MODEL --download-model-path whisper_models \
    --download-tokenizer-path whisper_models --language en --audio-path own_voice/p01_me.wav >/dev/null
fi
PROMPT_LIST="Jira, MR, merge request, Databricks, PRJ-21499, GitLab, Grafana, Kubernetes, ArgoCD, collector, CCB, hash collector dev, bulk push batching, Slack, pods."
OUT=$DIR/results
PROMPT_SENT="I work on GitLab MRs and Jira tickets like PRJ-21499, check Grafana and ArgoCD on Kubernetes pods, the Databricks collector, the CCB meeting, and Slack, like hash collector dev and bulk push batching."
for mode in ${=MODES:-none prompt sentence}; do
  name=whisper_${MODEL}_${mode}
  rep=$DIR/whisper/$name
  rm -rf $rep; mkdir -p $rep
  args=(transcribe --model-path $MDIR --language en --without-timestamps --report --report-path $rep)
  [[ $mode == prompt ]] && args+=(--prompt "$PROMPT_LIST")
  [[ $mode == sentence ]] && args+=(--prompt "$PROMPT_SENT")
  : > $rep/rss.txt
  for f in $DIR/*_me.wav; do
    /usr/bin/time -l whisperkit-cli $args --audio-path $f >/dev/null 2>> $rep/rss.txt
  done
  python3 - $rep > $OUT/$name.jsonl <<'EOF'
import json, sys, glob, os
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    d = json.load(open(p))
    t = d["timings"]
    print(json.dumps({"id": os.path.basename(p)[:-5], "hyp": d["text"].strip(),
                      "finalAfterLastChunkMs": t["fullPipeline"] * 1000,
                      "encodeMs": t["encoding"] * 1000, "audioS": t["inputAudioSeconds"],
                      "loadMs": t["modelLoading"] * 1000}))
EOF
  echo "$name: $(wc -l < $OUT/$name.jsonl) results, peak footprint max $(awk '/peak memory footprint/{if($1>m)m=$1}END{printf "%.0f MB", m/1048576}' $rep/rss.txt)"
done
python3 wer.py $OUT $DIR/manifest.tsv -v > $DIR/report.md
cat $DIR/report.md
