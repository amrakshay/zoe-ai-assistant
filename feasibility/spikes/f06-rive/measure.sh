#!/bin/zsh
# Usage: ./measure.sh <label> <binary> [args...]
# Runs the binary for 35 s; CPU% = process CPU-time delta over t=5..35 s / 30 s;
# RSS = mean and max of 1 s samples over the same window; phys footprint at t=30 s.
# Also records WindowServer CPU over the same window (context only: it includes other apps).
label=$1; shift
cd "${0:A:h}"
mkdir -p results
log=results/$label.log
"$@" --duration 37 > $log 2>&1 &
pid=$!
cpusec() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
ws=$(pgrep -x WindowServer)
sleep 5
c0=$(cpusec $pid); w0=$(cpusec $ws); t0=$(date +%s.%N 2>/dev/null || python3 -c 'import time;print(time.time())')
rss_sum=0; rss_max=0; n=0
for i in {1..30}; do
  r=$(ps -o rss= -p $pid | tr -d ' '); rss_sum=$((rss_sum + r)); n=$((n+1)); (( r > rss_max )) && rss_max=$r
  [[ $i == 25 ]] && fp=$(footprint -p $pid 2>/dev/null | awk '/phys_footprint:/ {print $2, $3; exit}')
  sleep 1
done
c1=$(cpusec $pid); w1=$(cpusec $ws)
wait $pid
cpu=$(echo "scale=2; ($c1 - $c0) * 100 / 30" | bc)
wscpu=$(echo "scale=2; ($w1 - $w0) * 100 / 30" | bc)
fps=$(grep 'frames/s' $log | tail -4 | awk '{s+=$NF; n++} END { if (n) printf "%.1f", s/n; else print "n/a" }')
printf "%-28s cpu=%6s%%  rss_mean=%5d MB  rss_max=%5d MB  footprint=%s  fps=%s  windowserver=%s%%\n" \
  $label $cpu $((rss_sum / n / 1024)) $((rss_max / 1024)) "${fp:-n/a}" $fps $wscpu | tee -a results/summary.txt
