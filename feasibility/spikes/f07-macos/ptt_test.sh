#!/bin/zsh
# F07 push-to-talk checks (needs a person at the keyboard).
cd "${0:A:h}"
echo "\n=== Test 1 of 2: shortcut ⌃⌥Space (Control+Option+Space) ==="
echo "When it says 'hold', press and HOLD Control+Option+Space for about a second, release, and repeat 3 times."
read "?Press Enter to start (15 s). "
./hotkey 15 | tee hotkey.log
echo "\n=== Test 2 of 2: right Option key on its own ==="
echo "Press and HOLD the RIGHT Option (⌥) key for about a second, release, and repeat 3 times."
read "?Press Enter to start (12 s). "
./ptt --wait 12 2>&1 | tee ptt.log
echo "\nAll done. Tell Claude in the chat."
