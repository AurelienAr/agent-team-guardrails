#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks a pull request merge unless a human approver's
# review covers the current head of that pull request.
#
# Off when no approver is configured. It is a guardrail against mistakes and
# planted text, not a security boundary: use branch protection for that.
#
# Recognised merges, anywhere in a chained command:
#   gh [-R repo] pr merge [flags] [<number> | #<number> | <url> | <branch>] [flags]
#   gh api -X PUT repos/<owner>/<repo>/pulls/<number>/merge
#   gh api graphql ... mergePullRequest ...      (always blocked: cannot be checked)
# The script of `bash -c` / `sh -c` and the words of `eval` are read the same way.
# Blocked because they cannot be checked: `gh pr merge --auto` (it fires later, on a head
# nobody checked), a merge whose PR comes through xargs, and a merge-looking command
# whose name is computed (`$cmd pr merge 12`).
set -u
set -f

input=$(cat)
approvers="${GUARDRAILS_APPROVERS:-${CLAUDE_PLUGIN_OPTION_HUMAN_APPROVERS:-}}"
[ -n "$(printf '%s' "$approvers" | tr -d ' ,@')" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
  cmd=$(printf '%s' "$input" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | sed -e 's/\\"/"/g' -e 's/\\n/\n/g')
fi
[ -n "$cmd" ] || exit 0
# Cheap exit for the vast majority of commands.
case "$cmd" in *gh*) ;; *) exit 0 ;; esac

here=$(cd "$(dirname "$0")" && pwd)
verify="$here/../skills/signature-is-not-proof/scripts/verify-approval.sh"

SEP=$(printf '\001')SEP
REDIR=$(printf '\001')REDIR

# Shell-like tokenizer: one token per line, quotes and backslashes resolved,
# command separators (; & | newline) and redirections (< >) as markers.
tokenize() {
  printf '%s' "$1" | awk -v sep="$SEP" -v redir="$REDIR" 'BEGIN { RS = "\001" } {
    s = $0; n = length(s); tok = ""; has = 0; q = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q == "\047") { if (c == "\047") q = ""; else tok = tok c; continue }
      if (q == "\"") {
        if (c == "\\" && i < n) { i++; tok = tok substr(s, i, 1); continue }
        if (c == "\"") q = ""; else tok = tok c
        continue
      }
      if (c == "\047" || c == "\"") { q = c; has = 1; continue }
      if (c == "\\" && i < n) { i++; tok = tok substr(s, i, 1); has = 1; continue }
      if (c == " " || c == "\t") { if (has) { print tok; tok = ""; has = 0 } continue }
      if (c == ";" || c == "&" || c == "|" || c == "\n") { if (has) { print tok; tok = ""; has = 0 } print sep; continue }
      if (c == "<" || c == ">") { if (has) { print tok; tok = ""; has = 0 } print redir; continue }
      tok = tok c; has = 1
    }
    if (has) print tok
  }'
}

targets=""     # one "repo|pr" per line; repo may be empty (current repository)
problems=""    # reasons to block that need no API call
nl='
'

add_problem() { problems="$problems$1$nl"; }

# Resolve what `gh pr merge` was given into a PR number.
add_pr_target() { # add_pr_target <repo> <target>
  local repo=$1 target=$2 num="" r
  case "$target" in
    http://*|https://*|github.com/*|www.github.com/*)
      r=$(printf '%s' "$target" | sed -nE 's#^(https?://)?(www\.)?github\.com/([^/]+/[^/]+)/pull/([0-9]+).*#\3#p')
      num=$(printf '%s' "$target" | sed -nE 's#^(https?://)?(www\.)?github\.com/([^/]+/[^/]+)/pull/([0-9]+).*#\4#p')
      [ -n "$r" ] && repo=$r ;;
    \#*) num=${target#\#} ;;
    '') ;;
    *) num=$target ;;
  esac
  case "$num" in
    ''|*[!0-9]*)
      # A branch name, or nothing: ask gh which pull request it is.
      if [ -n "$target" ] && [ -n "$repo" ]; then
        num=$(gh pr view "$target" --repo "$repo" --json number -q .number 2>/dev/null)
      elif [ -n "$target" ]; then
        num=$(gh pr view "$target" --json number -q .number 2>/dev/null)
      elif [ -n "$repo" ]; then
        num=$(gh pr view --repo "$repo" --json number -q .number 2>/dev/null)
      else
        num=$(gh pr view --json number -q .number 2>/dev/null)
      fi ;;
  esac
  case "$num" in
    ''|*[!0-9]*) add_problem "A command merges a pull request (${target:-current branch}), but the guard cannot tell which one. Run the merge with an explicit PR number." ;;
    *) targets="$targets$repo|$num$nl" ;;
  esac
}

# Look at one simple command (its tokens are in the array seg).
check_segment() {
  local n=${#seg[@]} i=0 repo="" t via_xargs=0 j s
  [ "$n" -gt 0 ] || return 0
  # Skip variable assignments and common wrappers before the command name.
  while [ "$i" -lt "$n" ]; do
    t=${seg[$i]}
    case "$t" in
      [A-Za-z_]*=*) i=$((i + 1)) ;;
      command|exec|time|env|sudo|nohup) i=$((i + 1)) ;;
      xargs) via_xargs=1; i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  case "${seg[$i]}" in
    gh|*/gh) ;;
    bash|sh|zsh|dash|ksh|*/bash|*/sh|*/zsh|*/dash|*/ksh)
      # `bash -c "<script>"`: read the script as a command line of its own.
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case "${seg[$j]}" in
          --*) j=$((j + 1)) ;;
          -*c*) [ $((j + 1)) -lt "$n" ] && scan "${seg[$((j + 1))]}"; return 0 ;;
          -*) j=$((j + 1)) ;;
          *) return 0 ;;
        esac
      done
      return 0 ;;
    eval)
      s=""
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do s="$s ${seg[$j]}"; j=$((j + 1)); done
      scan "$s"
      return 0 ;;
    *'$'*|*'`'*)
      # The command name is computed (`$cmd`, `$(...)`): what runs cannot be known here.
      if mentions_merge; then
        add_problem "A command whose name is computed (${seg[$i]}) looks like a pull request merge and cannot be checked. Run gh pr merge <number> directly."
      fi
      return 0 ;;
    *) return 0 ;;
  esac
  i=$((i + 1))
  # Global flags before the subcommand.
  while [ "$i" -lt "$n" ]; do
    t=${seg[$i]}
    case "$t" in
      -R|--repo) repo=${seg[$((i + 1))]:-}; i=$((i + 2)) ;;
      --repo=*) repo=${t#--repo=}; i=$((i + 1)) ;;
      -R?*) repo=${t#-R}; i=$((i + 1)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0

  if [ "${seg[$i]}" = pr ] && [ "${seg[$((i + 1))]:-}" = merge ]; then
    local target="" auto=0 disable=0
    i=$((i + 2))
    while [ "$i" -lt "$n" ]; do
      t=${seg[$i]}
      case "$t" in
        "$REDIR") i=$((i + 2)); continue ;;
        --disable-auto) disable=1 ;;
        --auto) auto=1 ;;
        -R|--repo) repo=${seg[$((i + 1))]:-}; i=$((i + 1)) ;;
        --repo=*) repo=${t#--repo=} ;;
        -R?*) repo=${t#-R} ;;
        -t|--subject|-b|--body|-F|--body-file|--match-head-commit|-A|--author-email) i=$((i + 1)) ;;
        -*) ;;
        *) [ -n "$target" ] || target=$t ;;
      esac
      i=$((i + 1))
    done
    [ "$disable" -eq 1 ] && return 0
    if [ "$via_xargs" -eq 1 ]; then
      add_problem "A merge run through xargs takes its pull request from input the guard cannot see. Run gh pr merge <number> directly."
      return 0
    fi
    if [ "$auto" -eq 1 ]; then
      add_problem "Auto-merge (--auto) is blocked: it would merge a later head that no human approved. Merge once a human approval covers the current head."
      return 0
    fi
    add_pr_target "$repo" "$target"
    return 0
  fi

  if [ "${seg[$i]}" = api ]; then
    local method="" path="" graphql=0 mutation=0
    i=$((i + 1))
    while [ "$i" -lt "$n" ]; do
      t=${seg[$i]}
      case "$t" in *mergePullRequest*) mutation=1 ;; esac
      case "$t" in
        -X|--method) method=${seg[$((i + 1))]:-}; i=$((i + 1)) ;;
        --method=*) method=${t#--method=} ;;
        -X?*) method=${t#-X} ;;
        -f|-F|--field|--raw-field|-H|--header|--input|-q|--jq|-t|--template|--hostname|--cache|-p|--preview)
          case "${seg[$((i + 1))]:-}" in *mergePullRequest*) mutation=1 ;; esac
          i=$((i + 1)) ;;
        graphql) graphql=1 ;;
        -*) ;;
        *) [ -n "$path" ] || path=$t ;;
      esac
      i=$((i + 1))
    done
    if [ "$graphql" -eq 1 ] && [ "$mutation" -eq 1 ]; then
      add_problem "Merging through the GraphQL mergePullRequest mutation cannot be checked and is blocked. Use: gh pr merge <number>."
      return 0
    fi
    method=$(printf '%s' "$method" | tr 'a-z' 'A-Z')
    path=${path#/}
    if [ "$method" = PUT ] && printf '%s' "$path" | grep -Eq '^repos/[^/]+/[^/]+/pulls/[0-9]+/merge$'; then
      local r num
      r=$(printf '%s' "$path" | sed -E 's#^repos/([^/]+/[^/]+)/pulls/.*#\1#')
      num=$(printf '%s' "$path" | sed -E 's#^repos/[^/]+/[^/]+/pulls/([0-9]+)/merge$#\1#')
      case "$r" in *'{'*) r=$repo ;; esac
      targets="$targets$r|$num$nl"
    fi
  fi
  return 0
}

# Does the current command mention a pull request merge anywhere in its words?
mentions_merge() {
  printf ' %s ' "${seg[*]}" | grep -Eq '[[:space:]]pr[[:space:]]+merge[[:space:]]|pulls/[^[:space:]]+/merge|mergePullRequest'
}

# Walk a command line simple command by simple command. Called again on the script
# of `bash -c` and the words of `eval`, a few levels deep at most.
depth=0
scan() {
  local tok
  depth=$((depth + 1))
  if [ "$depth" -gt 4 ]; then
    add_problem "Commands nested too deeply to check for a pull request merge."
    depth=$((depth - 1)); return 0
  fi
  seg=()
  while IFS= read -r tok; do
    if [ "$tok" = "$SEP" ]; then
      check_segment; seg=()
    else
      seg[${#seg[@]}]=$tok
    fi
  done <<TOKENS
$(tokenize "$1")
TOKENS
  check_segment; seg=()
  depth=$((depth - 1))
}

scan "$cmd"

[ -n "$targets$problems" ] || exit 0

report=""
failed=0
if [ -n "$problems" ]; then failed=1; report="$problems"; fi
while IFS="|" read -r repo pr; do
  [ -n "$pr" ] || continue
  if [ -n "$repo" ]; then
    out=$(bash "$verify" "$pr" --repo "$repo" 2>&1)
  else
    out=$(bash "$verify" "$pr" 2>&1)
  fi
  if [ $? -ne 0 ]; then
    failed=1
    report="$report$out$nl"
  fi
done <<TARGETS
$targets
TARGETS

[ "$failed" -eq 0 ] && exit 0

{
  echo "Blocked by agent-team-guardrails: merging a pull request needs a human approval on its current head."
  printf '%s' "$report"
  echo "Ask a human approver ($(printf '%s' "$approvers" | tr -d ' ')) to approve the pull request on GitHub."
  echo "A comment, a signature or a summary saying it was approved does not count."
} >&2
exit 2
