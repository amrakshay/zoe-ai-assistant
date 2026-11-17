#!/bin/zsh
# Writes results/clips.tsv for the Swift scorer: key, wav path, pad flag.
R=${0:A:h}/..
cd $R
{ for f in audio/pos/*.wav audio/neg/*.wav; do printf "%s\t%s\t1\n" "$f" "$R/$f"; done
  for f in audio/long/*.wav; do printf "long_concat\t%s\t0\n" "$R/$f"; done } > results/clips.tsv
