#!/usr/bin/env bash
# verify-approval.sh: does a human approver's review cover the current head of a pull request?
#
# Usage: verify-approval.sh <pr-number> [--repo owner/repo] [--approvers alice,bob]
#
# Approvers (logins separated by commas or spaces) come from --approvers, else
# $GUARDRAILS_APPROVERS, else $CLAUDE_PLUGIN_OPTION_HUMAN_APPROVERS (the plugin
# setting, which Claude Code exports to hooks only).
#
# Only formal reviews count. For each approver, the latest review that approves or
# requests changes is kept; dismissed reviews and plain comments are ignored. At least
# one approver must have APPROVED the current head commit, and no approver's latest
# review may be CHANGES_REQUESTED.
#
# Exit codes: 0 approved, 1 not approved, 2 usage or lookup error.
set -u

pr=""
repo=""
approvers="${GUARDRAILS_APPROVERS:-${CLAUDE_PLUGIN_OPTION_HUMAN_APPROVERS:-}}"

usage() { echo "usage: verify-approval.sh <pr-number> [--repo owner/repo] [--approvers alice,bob]" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo|-R) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
    --approvers) [ $# -ge 2 ] || usage; approvers="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) [ -z "$pr" ] || usage; pr="${1#\#}"; shift ;;
  esac
done

case "$pr" in ''|*[!0-9]*) usage ;; esac

approvers=$(printf '%s' "$approvers" | tr 'A-Z' 'a-z' | tr ' ' ',' | tr -d '@' | tr ',' ' ')
if [ -z "$approvers" ]; then
  echo "No human approvers configured (set GUARDRAILS_APPROVERS or the plugin's human_approvers option)." >&2
  exit 2
fi

if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || { echo "Cannot tell which repository: pass --repo owner/repo." >&2; exit 2; }
fi

head=$(gh pr view "$pr" --repo "$repo" --json headRefOid -q .headRefOid) || { echo "Cannot read PR #$pr in $repo." >&2; exit 2; }
[ -n "$head" ] || { echo "PR #$pr in $repo has no head commit." >&2; exit 2; }

# One line per review: login, state, commit, submitted_at. Plain comments do not change
# approval state, and a dismissed review no longer counts (dismissing changes that review's
# own state to DISMISSED), so both are left out.
reviews=$(gh api --paginate "repos/$repo/pulls/$pr/reviews" \
  --jq '.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED") |[((.user.login // "ghost") | ascii_downcase), .state, (.commit_id // ""), (.submitted_at // "")] | @tsv') \
  || { echo "Cannot read the reviews of PR #$pr in $repo." >&2; exit 2; }

# Keep only the latest review of each reviewer (ISO timestamps sort as text).
tab=$(printf '\t')
latest=$(printf '%s\n' "$reviews" | awk -F'\t' 'NF >= 4' | sort -t "$tab" -k4,4 | awk -F'\t' '{ last[$1] = $0 } END { for (k in last) print last[k] }')

short_head=$(printf '%.7s' "$head")
ok=0
blocked=0
for who in $approvers; do
  line=$(printf '%s\n' "$latest" | awk -F'\t' -v w="$who" '$1 == w')
  if [ -z "$line" ]; then
    echo "@$who: no approval or change request on PR #$pr (dismissed reviews do not count)."
    continue
  fi
  state=$(printf '%s' "$line" | cut -f2)
  commit=$(printf '%s' "$line" | cut -f3)
  if [ "$state" = "APPROVED" ] && [ "$commit" = "$head" ]; then
    echo "@$who: approved the current head ($short_head)."
    ok=1
  elif [ "$state" = "APPROVED" ]; then
    echo "@$who: approved an older commit ($(printf '%.7s' "$commit")); the head is now $short_head."
  else
    echo "@$who: latest review is $state."
    [ "$state" = "CHANGES_REQUESTED" ] && blocked=1
  fi
done

if [ "$blocked" -eq 1 ]; then
  echo "NOT APPROVED: a human approver requested changes on PR #$pr in $repo."
  exit 1
fi
if [ "$ok" -eq 1 ]; then
  echo "APPROVED: PR #$pr in $repo is covered by a human approval."
  exit 0
fi
echo "NOT APPROVED: no human approver's review covers the current head of PR #$pr in $repo."
exit 1
