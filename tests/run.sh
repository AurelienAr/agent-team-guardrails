#!/usr/bin/env bash
# Runs the test suite against a fake gh (tests/bin/gh) and JSON fixtures.
# Needs bash and jq. Usage: bash tests/run.sh
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
verify="$root/skills/signature-is-not-proof/scripts/verify-approval.sh"
guard="$root/hooks/guard-merge.sh"
rollup="$root/skills/single-writer-status/scripts/rollup.sh"
export PATH="$root/tests/bin:$PATH"
chmod +x "$root/tests/bin/gh"

pass=0; fail=0
HEAD_SHA=aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111
OLD_SHA=bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222

new_case() {
  FAKE_GH_DIR=$(mktemp -d); export FAKE_GH_DIR
  : > "$FAKE_GH_DIR/calls.log"
  echo '{"nameWithOwner":"acme/app"}' > "$FAKE_GH_DIR/repo.json"
  echo "{\"headRefOid\":\"$HEAD_SHA\"}" > "$FAKE_GH_DIR/pr.json"
  echo '{"number":7}' > "$FAKE_GH_DIR/current-pr.json"
  unset GUARDRAILS_APPROVERS CLAUDE_PLUGIN_OPTION_HUMAN_APPROVERS
}

# review <login> <state> <commit> <time>
review() { printf '{"user":{"login":"%s"},"state":"%s","commit_id":"%s","submitted_at":"%s"}' "$1" "$2" "$3" "$4"; }
reviews() { local IFS=,; echo "[$*]" > "$FAKE_GH_DIR/reviews.json"; }

check() { # check <name> <expected exit> <actual exit> [<output> <expected substring>]
  local name=$1 want=$2 got=$3
  if [ "$want" != "$got" ]; then
    echo "FAIL  $name: exit $got, expected $want"; [ $# -ge 4 ] && printf '      %s\n' "$4"; fail=$((fail + 1)); return
  fi
  if [ $# -ge 5 ] && ! printf '%s' "$4" | grep -qF -- "$5"; then
    echo "FAIL  $name: output lacks \"$5\""; printf '      %s\n' "$4"; fail=$((fail + 1)); return
  fi
  echo "ok    $name"; pass=$((pass + 1))
}

hook_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

echo "== verify-approval.sh"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "approval on the current head passes" 0 $? "$out" "APPROVED: PR #7"

new_case; reviews "$(review alice APPROVED $OLD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "approval on an older commit fails" 1 $? "$out" "older commit"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)" "$(review alice CHANGES_REQUESTED $HEAD_SHA 2026-01-02T11:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "a later change request cancels the approval" 1 $? "$out" "requested changes"

new_case; reviews "$(review alice CHANGES_REQUESTED $HEAD_SHA 2026-01-02T09:00:00Z)" "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "a later approval replaces an earlier change request" 0 $? "$out"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)" "$(review alice COMMENTED $HEAD_SHA 2026-01-02T11:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "a later plain comment does not cancel the approval" 0 $? "$out"

# Dismissing a review changes that review's own state to DISMISSED.
new_case; reviews "$(review alice DISMISSED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "a dismissed approval does not count" 1 $? "$out" "dismissed reviews do not count"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)" "$(review alice DISMISSED $HEAD_SHA 2026-01-02T11:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "a dismissed change request does not cancel the approval" 0 $? "$out"

new_case; reviews "$(review team-bot APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "an approval by the bot account does not count" 1 $? "$out" "@alice: no approval"

new_case; reviews "$(review bob APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers "alice bob" 2>&1); check "approvers can be separated by spaces" 0 $? "$out"

new_case; reviews "$(review Alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 --approvers "@ALICE, bob" 2>&1); check "logins compare without case or @" 0 $? "$out"

new_case; reviews "$(review bob APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)" "$(review alice CHANGES_REQUESTED $HEAD_SHA 2026-01-02T11:00:00Z)"
out=$(bash "$verify" 7 --approvers alice,bob 2>&1); check "one approver's change request blocks another's approval" 1 $? "$out" "requested changes"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(bash "$verify" 7 2>&1); check "no approvers configured is an error" 2 $? "$out" "No human approvers"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(GUARDRAILS_APPROVERS=alice bash "$verify" 7 2>&1); check "approvers can come from the environment" 0 $? "$out"

new_case; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"; rm "$FAKE_GH_DIR/pr.json"
out=$(bash "$verify" 7 --approvers alice 2>&1); check "an unreadable PR is an error, not an approval" 2 $? "$out"

echo "== guard-merge.sh (hook)"
m="gh pr"" merge"   # split so that other tools scanning this file do not mistake it for a real merge

new_case; reviews
out=$(hook_input "$m 7 --squash" | bash "$guard" 2>&1); check "guard is off without approvers" 0 $? "$out"

new_case; reviews; export GUARDRAILS_APPROVERS=alice
out=$(hook_input "gh pr view 7" | bash "$guard" 2>&1); check "other commands pass" 0 $? "$out"

new_case; export GUARDRAILS_APPROVERS=alice; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(hook_input "$m 7 --squash" | bash "$guard" 2>&1); check "approved merge passes" 0 $? "$out"

new_case; export GUARDRAILS_APPROVERS=alice; reviews "$(review alice APPROVED $OLD_SHA 2026-01-02T10:00:00Z)"
out=$(hook_input "$m 7 --squash" | bash "$guard" 2>&1); check "merge without approval on head is blocked" 2 $? "$out" "Blocked by agent-team-guardrails"

new_case; export GUARDRAILS_APPROVERS=alice; reviews
out=$(hook_input "$m https://github.com/acme/other/pull/12" | bash "$guard" 2>&1); code=$?
check "merge by URL is checked against that repository" 2 $code "$(cat "$FAKE_GH_DIR/calls.log")" "--repo acme/other"

new_case; export GUARDRAILS_APPROVERS=alice; reviews
out=$(hook_input "cd app && $m -R acme/app 7" | bash "$guard" 2>&1); code=$?
check "merge inside a chained command is checked" 2 $code "$out" "PR #7"

new_case; export GUARDRAILS_APPROVERS=alice; reviews
out=$(hook_input "gh api -X PUT repos/acme/app/pulls/9/merge" | bash "$guard" 2>&1); check "merge through the API is blocked" 2 $? "$out" "PR #9"

new_case; export GUARDRAILS_APPROVERS=alice; reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
out=$(hook_input "$m --squash" | bash "$guard" 2>&1); check "merge of the current branch's PR uses its number" 0 $? "$(cat "$FAKE_GH_DIR/calls.log")"

new_case; export GUARDRAILS_APPROVERS=alice; reviews; rm "$FAKE_GH_DIR/current-pr.json"
out=$(hook_input "$m --squash" | bash "$guard" 2>&1); check "merge of an unknown PR is blocked" 2 $? "$out" "cannot tell which one"

# PR 7 (the current branch) is approved, PR 12 is not: each form below must check PR 12.
approved_7_not_12() {
  new_case; export GUARDRAILS_APPROVERS=alice
  reviews "$(review alice APPROVED $HEAD_SHA 2026-01-02T10:00:00Z)"
  echo '[]' > "$FAKE_GH_DIR/reviews-12.json"
}
for form in "$m --squash 12" "$m --squash --delete-branch 12" "$m '12'" "$m \\\"12\\\" --merge" \
            "$m 12; echo done" "$m 12 | cat" "$m 12 > log.txt" "$m -t \\\"Ship it now\\\" 12" \
            "$m https://github.com/acme/app/pull/12/files" "$m http://www.github.com/acme/app/pull/12" \
            "gh -R acme/app pr merge 12" "$m --repo=acme/app 12" "GH_DEBUG=1 $m 12"; do
  approved_7_not_12
  out=$(hook_input "$form" | bash "$guard" 2>&1); check "checks the right PR: ${form#gh pr }" 2 $? "$out" "PR #12"
done

approved_7_not_12
out=$(hook_input "$m 7 && $m 12" | bash "$guard" 2>&1); check "every merge in a chained command is checked" 2 $? "$out" "PR #12"

for form in "bash -c \\\"$m 12\\\"" "sh -lc '$m --squash 12'" "eval $m 12" "eval \\\"$m 12\\\"" \
            "cd app && bash -c 'git pull && $m 12'"; do
  approved_7_not_12
  out=$(hook_input "$form" | bash "$guard" 2>&1); check "reads inside: $form" 2 $? "$out" "PR #12"
done

approved_7_not_12
out=$(hook_input "bash -c \\\"$m 7\\\"" | bash "$guard" 2>&1); check "an approved merge inside bash -c passes" 0 $? "$out"

approved_7_not_12
out=$(hook_input "g=gh; \$g pr merge 12" | bash "$guard" 2>&1); check "a computed command name that merges is blocked" 2 $? "$out" "cannot be checked"

approved_7_not_12
out=$(hook_input "\$(which gh) pr merge 12" | bash "$guard" 2>&1); check "a command substitution that merges is blocked" 2 $? "$out" "cannot be checked"

approved_7_not_12
out=$(hook_input "echo 12 | xargs $m" | bash "$guard" 2>&1); check "a merge through xargs is blocked" 2 $? "$out" "xargs"

approved_7_not_12
out=$(hook_input "bash -c 'echo hello'" | bash "$guard" 2>&1); check "other bash -c commands pass" 0 $? "$out"

approved_7_not_12
out=$(hook_input "\$EDITOR notes.md" | bash "$guard" 2>&1); check "other computed commands pass" 0 $? "$out"

approved_7_not_12
out=$(hook_input "$m t12-branch" | bash "$guard" 2>&1); code=$?
check "a branch name is resolved to its PR" 0 $code "$(cat "$FAKE_GH_DIR/calls.log")" "pr view t12-branch"

approved_7_not_12
out=$(hook_input "$m 7 --auto --squash" | bash "$guard" 2>&1); check "auto-merge is blocked" 2 $? "$out" "Auto-merge"

approved_7_not_12
out=$(hook_input "$m 12 --disable-auto" | bash "$guard" 2>&1); check "turning auto-merge off is allowed" 0 $? "$out"

approved_7_not_12
out=$(hook_input "echo $m 12" | bash "$guard" 2>&1); check "a merge command inside echo is not a merge" 0 $? "$out"

approved_7_not_12
out=$(hook_input "git log --grep '$m 12'" | bash "$guard" 2>&1); check "a merge command inside a search string is not a merge" 0 $? "$out"

approved_7_not_12
out=$(hook_input "gh api repos/acme/app/pulls/12/merge" | bash "$guard" 2>&1); check "reading a PR's merge status is allowed" 0 $? "$out"

approved_7_not_12
out=$(hook_input "gh api --method PUT 'repos/{owner}/{repo}/pulls/12/merge'" | bash "$guard" 2>&1); check "API merge with {owner}/{repo} is checked in the current repository" 2 $? "$out" "PR #12 in acme/app"

approved_7_not_12
out=$(hook_input "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \\\"X\\\"}) { clientMutationId } }'" | bash "$guard" 2>&1)
check "GraphQL merge is blocked" 2 $? "$out" "GraphQL"
unset GUARDRAILS_APPROVERS

echo "== rollup.sh"

body() { printf '%s' "$1" | jq -Rs .; }
new_case
cat > "$FAKE_GH_DIR/prs.json" <<JSON
[
  {"number": 21, "title": "Login by email", "mergedAt": "2026-03-01T09:00:00Z",
   "body": $(body "Adds login.

## For STATUS
Login by email works end to end; password reset is still missing (see #88).

## Tests
All green.")},
  {"number": 22, "title": "Fix typo", "mergedAt": "2026-03-01T12:00:00Z",
   "body": $(body "## For STATUS
Nothing for STATUS")},
  {"number": 23, "title": "Refactor storage", "mergedAt": "2026-03-01T10:00:00Z",
   "body": $(body "No section here.")},
  {"number": 24, "title": "Export to CSV", "mergedAt": "2026-03-01T11:00:00Z",
   "body": $(printf '### for status\r\n<!-- one sentence -->\r\nUsers can export\r\ntheir data to CSV.\r\n' | jq -Rs .)}
]
JSON
out=$(bash "$rollup" --since 2026-02-28T18:00:00Z 2>&1); code=$?
check "marker moves to the last merge" 0 $code "$out" "<!-- last-rollup: 2026-03-01T12:00:00Z -->"
check "a sentence is extracted and stops at the next heading" 0 $code "$out" "- #21 Login by email: Login by email works end to end; password reset is still missing (see #88)."
check "lower-case heading, CRLF and a comment are handled" 0 $code "$out" "- #24 Export to CSV: Users can export their data to CSV."
check "a PR without the section is listed for its author" 0 $code "$out" "- #23 Refactor storage"
check "\"Nothing for STATUS\" is kept apart" 0 $code "$(printf '%s' "$out" | sed -n '/Nothing to fold in/,$p')" "- #22 Fix typo"
check "sentences come in merge order" 0 $code "$(printf '%s' "$out" | grep -n '^- #2[14] ' | head -1)" "#21"
check "roll-up PRs are excluded from the search" 0 $code "$(cat "$FAKE_GH_DIR/calls.log")" "merged:>2026-02-28T18:00:00Z -label:status-rollup"

template="$root/skills/single-writer-status/templates/pull_request_template.md"
new_case
cat > "$FAKE_GH_DIR/prs.json" <<JSON
[
  {"number": 31, "title": "Untouched template", "mergedAt": "2026-03-01T09:00:00Z", "body": $(body "$(cat "$template")")},
  {"number": 32, "title": "Filled template", "mergedAt": "2026-03-01T09:10:00Z", "body": $(body "$(cat "$template")
Search is now instant.")},
  {"number": 33, "title": "Template, nothing", "mergedAt": "2026-03-01T09:20:00Z", "body": $(body "$(cat "$template")
Nothing for STATUS")},
  {"number": 34, "title": "Colon heading", "mergedAt": "2026-03-01T09:30:00Z", "body": $(body "## For STATUS: ##
- Dark mode works.
- Contrast still to check.")},
  {"number": 35, "title": "Fenced", "mergedAt": "2026-03-01T09:40:00Z", "body": $(body "## For STATUS
Config moved to one file:
\`\`\`
# settings.toml
\`\`\`
See the docs.")},
  {"number": 36, "title": "Just merged", "mergedAt": "2026-03-01T11:55:00Z", "body": $(body "## For STATUS
Too fresh.")}
]
JSON
out=$(bash "$rollup" --since 2026-02-28T18:00:00Z --now 2026-03-01T11:50:00Z 2>&1); code=$?
check "an untouched template counts as missing" 0 $code "$(printf '%s' "$out" | sed -n '/No "For STATUS"/,/^$/p')" "- #31 Untouched template"
check "the template's comment is not part of the sentence" 0 $code "$out" "- #32 Filled template: Search is now instant."
check "\"Nothing for STATUS\" after the template's comment is recognised" 0 $code "$(printf '%s' "$out" | sed -n '/Nothing to fold in/,$p')" "- #33 Template, nothing"
check "a heading with a colon or closing #s, and list markers" 0 $code "$out" "- #34 Colon heading: Dark mode works. Contrast still to check."
check "a # line inside a code fence does not end the section" 0 $code "$out" "See the docs."
check "a PR merged within the settle time is left for later" 0 $code "$(printf '%s' "$out" | sed -n '/Left for the next/,$p')" "- #36 Just merged"
check "the marker stays before PRs left for later" 0 $code "$out" "<!-- last-rollup: 2026-03-01T09:40:00Z -->"

new_case; echo '[]' > "$FAKE_GH_DIR/prs.json"
out=$(bash "$rollup" --since 2026-02-28T18:00:00Z --limit abc 2>&1); check "a non-numeric limit is refused" 2 $? "$out" "--limit must be a number"

new_case; echo '[]' > "$FAKE_GH_DIR/prs.json"
out=$(bash "$rollup" --since 2026-02-28T18:00:00Z 2>&1); check "nothing merged means no roll-up" 0 $? "$out" "No roll-up needed"

new_case; echo '[{"number":1,"title":"a","mergedAt":"2026-03-01T09:00:00Z","body":""},{"number":2,"title":"b","mergedAt":"2026-03-01T10:00:00Z","body":""}]' > "$FAKE_GH_DIR/prs.json"
out=$(bash "$rollup" --since 2026-02-28T18:00:00Z --limit 2 2>&1); check "a full page warns that results may be cut" 0 $? "$out" "Warning: 2 results"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
