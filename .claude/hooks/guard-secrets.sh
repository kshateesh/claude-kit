#!/bin/bash
# guard-secrets.sh
#
# PreToolUse hook, matcher Edit|Write. Blocks writes to files that hold
# credentials or infrastructure state.
#
# This is enforcement, not advice. A line in CLAUDE.md is a request the model
# can talk itself out of; a non-zero exit here is a guarantee it cannot.
#
# Bash redirects into the same paths are caught by guard-dangerous-commands.sh,
# because this matcher only ever sees the Edit and Write tools.
#
# Exit 2 blocks the call. stderr is fed back to the model as the reason.

set -uo pipefail
INPUT=$(cat)
. "$(dirname "${BASH_SOURCE[0]}")/_jget.sh"

FILE_PATH=$(jget 'tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
BASE=$(basename "$FILE_PATH")

block() { echo "Blocked by guard-secrets: $1" >&2; exit 2; }

# Templates are not secrets. Checked first so the .env rule below can stay broad.
case "$BASE" in
  .env.example|.env.sample|.env.template|*.env.example|*.env.sample) exit 0 ;;
esac

case "$BASE" in
  .env|.env.*|*.env)                    block "$BASE holds environment secrets. Edit it by hand." ;;
  *.tfstate|*.tfstate.*)                block "Terraform state is never hand-edited." ;;
  *.pem|*.key|id_rsa*|id_ed25519*)      block "$BASE is private key material." ;;
  kubeconfig|*.kubeconfig)              block "kubeconfig holds cluster credentials." ;;
  *credentials*.json|credentials|.netrc|.npmrc|.pypirc)
                                        block "$BASE holds credentials." ;;
esac

case "$FILE_PATH" in
  */secrets/*|*/.secrets/*|*/.ssh/*|*/.gnupg/*)
    block "path is under a secrets directory." ;;
esac

exit 0
