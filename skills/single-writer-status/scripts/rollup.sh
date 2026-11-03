#!/usr/bin/env bash
# rollup.sh: gathers the "For STATUS" sentences of the pull requests merged since the last roll-up.
#
# Usage: rollup.sh --since <ISO-8601 time> [--base main] [--repo owner/repo]
#                  [--label status-rollup] [--heading "For STATUS"] [--limit 200]
#                  [--settle-minutes 10] [--now <ISO-8601 time>]
#
# Prints Markdown for the status writer: the new marker, one line per sentence, and the
# merged pull requests that left no sentence. The writer folds the sentences into the
# status file; this script never edits it.
#
# Pull requests merged in the last --settle-minutes are left for the next roll-up, so that
# GitHub's search index has caught up before the marker moves past them.
#
# Exit codes: 0 done (even if nothing is new), 2 usage or lookup error.
set -u

since=""; base="main"; repo=""; label="status-rollup"; heading="For STATUS"; limit=200
settle=10; now=""

usage() { echo "usage: rollup.sh --since <ISO time> [--base main] [--repo owner/repo] [--label status-rollup] [--heading \"For STATUS\"] [--limit 200] [--settle-minutes 10]" >&2; exit 2; }

while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --since) since="$2" ;;
    --base) base="$2" ;;
    --repo|-R) repo="$2" ;;
    --label) label="$2" ;;
    --heading) heading="$2" ;;
    --limit) limit="$2" ;;
    --settle-minutes) settle="$2" ;;
    --now) now="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$since" ] || usage
case "$limit" in ''|*[!0-9]*) echo "--limit must be a number." >&2; exit 2 ;; esac
case "$settle" in ''|*[!0-9]*) echo "--settle-minutes must be a number." >&2; exit 2 ;; esac

# Cut-off: now minus the settle time, in UTC ISO-8601 (BSD date on macOS, GNU date elsewhere).
if [ -z "$now" ]; then
  cutoff=$(date -u -v-"${settle}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "$settle minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || { echo "Cannot compute the current time." >&2; exit 2; }
else
  cutoff=$now
fi

search="merged:>$since"
[ -n "$label" ] && search="$search -label:$label"

set -- --state merged --base "$base" --search "$search" --limit "$limit" \
  --json number,title,mergedAt,body \
  --jq '.[] | [(.number | tostring), .mergedAt, (.title | @base64), ((.body // "") | @base64)] | @tsv'
[ -n "$repo" ] && set -- "$@" --repo "$repo"
rows=$(gh pr list "$@") || { echo "Cannot list merged pull requests." >&2; exit 2; }

decode() { printf '%s' "$1" | base64 --decode 2>/dev/null; }

# Prints the text of the section under the heading, on one line. HTML comments (even over
# several lines) are removed, headings inside code fences do not count, list markers are
# dropped, and the section stops at the next heading.
extract() {
  tr -d '\r' | awk -v h="$heading" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function uncomment(l,   out, p) {
      out = ""
      while (length(l) > 0) {
        if (inc) { p = index(l, "-->"); if (!p) return out; l = substr(l, p + 3); inc = 0 }
        else { p = index(l, "<!--"); if (!p) { out = out l; break }; out = out substr(l, 1, p - 1); l = substr(l, p + 4); inc = 1 }
      }
      return out
    }
    function title(l) { sub(/^#+[[:space:]]+/, "", l); sub(/[[:space:]]+#+[[:space:]]*$/, "", l); l = trim(l); sub(/:$/, "", l); return tolower(trim(l)) }
    {
      line = uncomment($0)
      if (line ~ /^[[:space:]]*(```|~~~)/) { fence = !fence; next }
      if (!fence && line ~ /^#+[[:space:]]/) {
        if (in_s) exit
        if (title(line) == tolower(h)) in_s = 1
        next
      }
      if (in_s) {
        line = trim(line)
        sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/, "", line)
        if (line != "") out = out (out == "" ? "" : " ") line
      }
    }
    END { print out }'
}

count=0; marker=""
sentences=""; missing=""; nothing=""; later=""
nl='
'
tab=$(printf '\t')
while IFS="$tab" read -r number merged title64 body64; do
  [ -n "$number" ] || continue
  count=$((count + 1))
  title=$(decode "$title64")
  if [ "$merged" \> "$cutoff" ]; then
    later="$later- #$number $title$nl"
    continue
  fi
  sentence=$(decode "$body64" | extract)
  if [ -z "$marker" ] || [ "$merged" \> "$marker" ]; then marker="$merged"; fi
  if [ -z "$sentence" ]; then
    missing="$missing- #$number $title$nl"
  elif printf '%s' "$sentence" | grep -Eiq "^nothing for "; then
    nothing="$nothing- #$number $title$nl"
  else
    sentences="$sentences$merged$tab- #$number $title: $sentence$nl"
  fi
done <<ROWS
$rows
ROWS

if [ "$count" -ge "$limit" ]; then
  echo "Warning: $count results, the limit. Some merged pull requests may be missing: raise --limit or narrow --since." >&2
fi

if [ -z "$marker" ]; then
  if [ -n "$later" ]; then
    echo "Only pull requests merged in the last $settle minutes; they are left for the next roll-up. No roll-up needed now."
  else
    echo "Nothing merged into $base since $since. No roll-up needed."
  fi
  exit 0
fi

echo "<!-- last-rollup: $marker -->"
echo
echo "## Merged into $base since $since"
if [ -n "$sentences" ]; then
  printf '%s' "$sentences" | sort | cut -f2-
else
  echo "- (no sentence to fold in)"
fi
if [ -n "$missing" ]; then
  echo
  echo "### No \"$heading\" section"
  printf '%s' "$missing"
fi
if [ -n "$nothing" ]; then
  echo
  echo "### Nothing to fold in"
  printf '%s' "$nothing"
fi
if [ -n "$later" ]; then
  echo
  echo "### Left for the next roll-up (merged in the last $settle minutes)"
  printf '%s' "$later"
fi
