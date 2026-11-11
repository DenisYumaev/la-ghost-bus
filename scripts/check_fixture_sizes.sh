#!/usr/bin/env bash
# Fail if any fixture that git would commit is larger than 1 MB.
# .gitignore cannot filter by size, so this runs in `make lint` and CI.
set -euo pipefail

limit=$((1024 * 1024))
status=0

# Tracked files plus untracked files that are not ignored.
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue  # tracked but deleted in the working tree
  size=$(wc -c < "$f" | tr -d ' ')
  if [ "$size" -gt "$limit" ]; then
    echo "Fixture over 1 MB: $f ($size bytes). Trim it, or add it to .gitignore." >&2
    status=1
  fi
done < <(git ls-files -z --cached --others --exclude-standard -- tests/fixtures)

exit "$status"
