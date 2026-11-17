# Wake word on my own voice: `hey_claude.onnx`

## Utterances found (by energy) vs cues

| Block | Cues | Utterances found |
|---|---|---|
| pos_normal | 10 | 10 (33 s) |
| pos_command | 8 | 10 (38 s) |
| pos_far | 6 | 8 (21 s) |
| pos_fast | 6 | 8 (18 s) |
| neg_near | 12 | 13 (39 s) |

## Recall on "Hey Claude" (utterances detected)

| Block | ≥ 0.5 | ≥ 0.3 | ≥ 0.2 | ≥ 0.1 | ≥ 0.05 | Peak score per utterance |
|---|---|---|---|---|---|---|
| pos_normal | 1/10 | 1/10 | 1/10 | 1/10 | 2/10 | 0.00, 0.00, 0.00, 0.01, 0.00, 0.06, 0.00, 0.00, 0.76, 0.02 |
| pos_command | 1/10 | 1/10 | 1/10 | 1/10 | 1/10 | 0.00, 0.01, 0.00, 0.00, 0.89, 0.01, 0.00, 0.01, 0.00, 0.00 |
| pos_far | 0/8 | 0/8 | 0/8 | 0/8 | 0/8 | 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00 |
| pos_fast | 1/8 | 1/8 | 1/8 | 1/8 | 1/8 | 0.00, 0.72, 0.00, 0.02, 0.00, 0.00, 0.00, 0.00 |
| **all** | **3/36** (8%) | **3/36** (8%) | **3/36** (8%) | **3/36** (8%) | **4/36** (11%) | |

## Near-misses (must not fire)

| Threshold | ≥ 0.5 | ≥ 0.3 | ≥ 0.2 | ≥ 0.1 | ≥ 0.05 |
|---|---|---|---|---|---|
| Fired | 0/13 | 0/13 | 0/13 | 0/13 | 0/13 |

(Found 13 utterances for 12 cues, so per-phrase labels are skipped.) Peaks: 0.001, 0.001, 0.002, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001

## False fires on ordinary speech

2.5 min: free talk plus 30 speech-to-text recordings. Peak score 0.001.

| Threshold | ≥ 0.5 | ≥ 0.3 | ≥ 0.2 | ≥ 0.1 | ≥ 0.05 |
|---|---|---|---|---|---|
| Fires | 0 | 0 | 0 | 0 | 0 |
