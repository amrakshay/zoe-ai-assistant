#!/bin/zsh
# Repo hygiene and syntax checks run by CI (and runnable locally). Until phase 1 adds the app, this is the
# whole of `build-and-test`:
#   1. no private or large files are tracked (audio, models, raw logs/transcripts, files over 5 MB)
#   2. every shell script parses (zsh -n / sh -n)
#   3. every Python file compiles
#   4. every Swift file parses (swiftc -parse; macOS only)
set -eu
cd "${0:A:h}/.."
fail=0
err() { echo "::error::$1"; fail=1; }

echo "== 1. Private / large files"
bad=$(git ls-files | grep -E '\.(wav|mp3|m4a|aiff|caf|flac|srt|onnx|mlmodel|log|jsonl)$|\.mlmodelc/' || true)
[[ -z $bad ]] || err "audio, models or raw outputs are tracked (keep them out of git):\n$bad"
big=$(git ls-files -z | xargs -0 stat -f '%z %N' 2>/dev/null | awk '$1 > 5*1024*1024 {print $2}' || true)
[[ -z $big ]] || err "files over 5 MB are tracked:\n$big"
emails=$(git grep -I -n -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' -- ':!*.lock' ':!LICENSE' ':!CODE_OF_CONDUCT.md' ':!scripts/ci-checks.sh' \
  | grep -v -E 'noreply@|@users\.noreply\.github\.com|git@github\.com|example\.(com|org|invalid)' || true)
[[ -z $emails ]] || err "email addresses found (use placeholders):\n$emails"

echo "== 2. Shell scripts"
for f in $(git ls-files '*.sh'); do
  if head -1 $f | grep -q zsh; then zsh -n $f || err "zsh syntax: $f"; else sh -n $f || err "sh syntax: $f"; fi
done

echo "== 3. Python"
for f in $(git ls-files '*.py'); do
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" $f || err "python syntax: $f"
done

echo "== 4. Swift"
if command -v swiftc >/dev/null; then
  for f in $(git ls-files '*.swift' | grep -v '/Package.swift$'); do
    swiftc -parse $f >/dev/null 2>&1 || { swiftc -parse $f; err "swift parse: $f"; }
  done
else
  echo "swiftc not found; skipped"
fi

scripts/check-version.sh || fail=1
(( fail == 0 )) && echo "All checks passed" || { echo "Checks failed"; exit 1; }
