#!/usr/bin/env bash
# Runs a command. When it fails, the first error lines become a workflow annotation, which can be
# read on the run page and through the API without signing in to GitHub.
log=$(mktemp)
"$@" >"$log" 2>&1
code=$?
cat "$log"
if [ "$code" -ne 0 ]; then
    summary=$(grep -E '^(error|warning)|^ +--> |panicked at|\.\.\. FAILED|^failures:|^ +[a-z_:]+::[a-z_:0-9]+$' "$log" | head -40 | awk 'BEGIN{ORS="%0A"} {print}')
    echo "::error title=$*::${summary:-no error lines found, exit code $code}"
fi
exit "$code"
