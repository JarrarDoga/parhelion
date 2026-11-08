#!/bin/sh
# Fails if SF Symbols data is tracked in the repository.
#
# Parhelion never contains Apple's SF Symbols (see docs/adr/0021-user-sf-symbols.md).
# This looks at the files Git tracks, or at the files in the directories given as
# arguments, for:
#   - file names of the SF Symbols app and Apple's symbol-bearing fonts;
#   - SVG exports of SF Symbols, which have a group per weight and scale,
#     such as id="Regular-M" or id="Ultralight-S".
set -eu

cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  files=$(find "$@" -type f)
else
  files=$(git ls-files)
fi

status=0

names=$(printf '%s\n' "$files" | grep -iE '(^|/)(SF-?Pro[^/]*\.(ttf|otf|ttc)|SFNS[^/]*\.(ttf|otf|ttc)|SFSymbols[^/]*|SF Symbols[^/]*|CoreGlyphs[^/]*|Assets\.car|symbol_order\.plist|name_availability\.plist|symbol_search\.plist|layerset_availability\.plist)$|\.dmg$' || true)
if [ -n "$names" ]; then
  echo "error: these files look like SF Symbols data from Apple:" >&2
  echo "$names" >&2
  status=1
fi

# The group ids of an export. This script is the only place in the repository
# that spells the pattern out.
pattern='id=["'"'"'](Ultralight|Thin|Light|Regular|Medium|Semibold|Bold|Heavy|Black)-[SML]["'"'"']'
matches=$(printf '%s\n' "$files" | grep -v '^Scripts/check-no-sf-symbols\.sh$' | while IFS= read -r file; do
  [ -f "$file" ] && grep -lEI "$pattern" "$file" 2>/dev/null || true
done)
if [ -n "$matches" ]; then
  echo "error: these files contain SF Symbols SVG exports:" >&2
  echo "$matches" >&2
  status=1
fi

exit "$status"
