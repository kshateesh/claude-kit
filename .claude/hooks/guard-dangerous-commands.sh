#!/bin/bash
# guard-dangerous-commands.sh
#
# PreToolUse hook, matcher Bash. Three rules, chosen because each one is
# irreversible and none of them has a legitimate use inside a scoped task.
#
#   1. rm -rf outside the project directory
#   2. force-push to main or master
#   3. shell redirect into a credential or state file
#
# Rule 1 matters most on a machine that is not mine. The rule is deliberately
# simple to state: rm -rf is allowed on a relative path inside the project and
# nowhere else. Absolute paths, home, parent directories and a bare glob are all
# refused, so `rm -rf node_modules` works and `rm -rf ~/Documents` does not.
#
# Limitation, stated rather than hidden: the hook sees the command before the
# shell expands it, so a path that arrives through a variable is invisible here.
# This is defence in depth, not a seal.
#
# Exit 2 blocks the call. stderr is fed back to the model as the reason.

set -uo pipefail
INPUT=$(cat)
. "$(dirname "${BASH_SOURCE[0]}")/_jget.sh"

COMMAND=$(jget 'tool_input.command')
[ -z "$COMMAND" ] && exit 0

block() { echo "Blocked by guard-dangerous-commands: $1" >&2; exit 2; }

# ---- 1. rm -rf, scoped to the project ----
if echo "$COMMAND" | grep -qE '(^|[;&|]|\s)rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR])'; then
  TARGETS=$(echo "$COMMAND" \
    | sed -E 's/.*rm[[:space:]]+((-[a-zA-Z]+[[:space:]]+)*)//' \
    | tr '|;&' '\n' | head -1)
  # Globbing off while splitting: an unquoted $TARGETS containing `*` would be
  # expanded by this shell into the names of files in the current directory, and
  # the bare-glob case below would never see a `*` to reject.
  set -f
  for t in $TARGETS; do
    case "$t" in
      -*) continue ;;
    esac
    t_unq=$(printf '%s' "$t" | tr -d "\"'")
    case "$t_unq" in
      /|/*)          block "rm -rf on the absolute path '$t_unq'. Only relative paths inside the project are allowed." ;;
      '~'|'~/'*)     block "rm -rf on '$t_unq', which is under your home directory." ;;
      '$HOME'*|'${HOME}'*) block "rm -rf on '$t_unq', which is under your home directory." ;;
      .|..|../*)     block "rm -rf on '$t_unq' reaches outside the project." ;;
      '*'|'.*')      block "rm -rf on a bare glob deletes the whole working directory. Name the target." ;;
    esac
  done
  set +f
fi

# ---- 2. force-push to a protected branch ----
if echo "$COMMAND" | grep -qE '(^|&&|\|\| )git push[^&|]*(--force|-f)([^a-zA-Z]|$)[^&|]*(origin[[:space:]]+)?(main|master)([[:space:]]|$)'; then
  block "force-push to main or master. Push to a feature branch, or run it yourself outside the agent."
fi

# ---- 3. shell redirect into a credential or state file ----
REDIR=$(echo "$COMMAND" | grep -oE '>>?[[:space:]]*[^[:space:]|&;<>]+' | sed -E 's/^>>?[[:space:]]*//' || true)
for t in $REDIR; do
  # Strip quotes the shell would have removed, and trailing metacharacters that
  # are part of the surrounding command rather than the path. Without the second
  # step, basename of `.env.example)` is `.env.example)`, which misses the
  # template allowlist below and blocks a write that should be fine.
  t=$(printf '%s' "$t" | tr -d "\"'" | sed -E 's/[);,&|]+$//')
  b=$(basename "$t")
  case "$b" in
    .env.example|.env.sample|.env.template|*.env.example|*.env.sample) continue ;;
  esac
  case "$b" in
    .env|.env.*|*.env|*.tfstate|*.tfstate.*|*.pem|*.key|id_rsa*|kubeconfig|*credentials*.json|.netrc|.npmrc|.pypirc)
      block "shell redirect into $t. Credential and state files are edited by hand." ;;
  esac
  case "$t" in
    */secrets/*|*/.secrets/*|*/.ssh/*|*/.gnupg/*)
      block "shell redirect into $t, which is under a secrets directory." ;;
  esac
done

exit 0
