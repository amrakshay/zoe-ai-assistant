#!/bin/zsh
# Generates synthetic test clips with macOS `say` (16 kHz mono int16 WAV).
set -e
D=${0:A:h}/../audio
mkdir -p $D/pos $D/neg $D/long
voices=("Aman" "Rishi" "Tara" "Samantha" "Ralph" "Daniel" "Flo (English (UK))" "Karen")
rates=(150 210)
pos=("hey claude" "hey Claude, can you check my calendar" "hey Claude what time is it")
neg=("hey cloud" "say cloud out loud" "hey clod" "the weather today looks cloudy" "please open the terminal and run the tests" "hey there how are you")
i=0
for v in $voices; do for r in $rates; do
  j=0; for t in $pos; do say -v "$v" -r $r --file-format=WAVE --data-format=LEI16@16000 -o "$D/pos/p_${i}_${j}.wav" "$t"; j=$((j+1)); done
  j=0; for t in $neg; do say -v "$v" -r $r --file-format=WAVE --data-format=LEI16@16000 -o "$D/neg/n_${i}_${j}.wav" "$t"; j=$((j+1)); done
  echo "$i	$v	$r" >> $D/index.tsv
  i=$((i+1))
done; done
# ~10 min of non-wake speech: a long paragraph read by several voices
txt="I spent the morning reviewing pull requests and then went for a long walk. The cloud bill was higher than expected this month, so we should look at the storage classes. Could you remind me to call the plumber tomorrow? My colleague Claudia said the build is green again. They played music loudly next door until midnight. Hey, did anyone see where I left my keys? The quarterly report needs charts, a summary and a list of risks. We clawed back some time by caching the results. Cloudflare had an outage last week. Clyde and Claire are coming over for dinner on Friday. Okay, let us start the meeting now."
k=0
for v in "Aman" "Samantha" "Daniel" "Tara" "Ralph" "Flo (English (UK))" "Rishi" "Karen"; do
  for r in 170; do say -v "$v" -r $r --file-format=WAVE --data-format=LEI16@16000 -o "$D/long/l_$k.wav" "$txt $txt $txt"; k=$((k+1)); done
done
