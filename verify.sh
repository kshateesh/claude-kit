#!/bin/bash
# verify.sh - tests for the guardrails.
#
# A guard nobody tested is a guard nobody should trust. Each case feeds a real
# hook payload to a real hook and asserts the exit code: 2 means blocked, 0 means
# allowed. The allow cases matter as much as the block cases, because a guard
# that blocks ordinary work gets switched off within a day.
#
# Exit 0 = every case passed. Exit 1 = at least one did not.

set -uo pipefail
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.claude/hooks"
PASS=0; FAIL=0

# $1 hook  $2 json payload  $3 expected exit  $4 description
check() {
  local hook="$1" payload="$2" want="$3" desc="$4"
  printf '%s' "$payload" | "$HOOKS/$hook" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '  pass  %s\n' "$desc"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  %s (wanted exit %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

w() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
c() { printf '{"tool_input":{"command":"%s"}}' "$1"; }

echo "guard-secrets: blocks"
check guard-secrets.sh "$(w '/app/.env')"                 2 "dotenv"
check guard-secrets.sh "$(w '/app/.env.production')"      2 "dotenv, suffixed"
check guard-secrets.sh "$(w '/home/me/.ssh/id_rsa')"      2 "private key"
check guard-secrets.sh "$(w '/infra/main.tfstate')"       2 "terraform state"
check guard-secrets.sh "$(w '/app/secrets/token.txt')"    2 "under a secrets directory"
check guard-secrets.sh "$(w '/app/gcp-credentials.json')" 2 "credentials json"

echo "guard-secrets: allows"
check guard-secrets.sh "$(w '/app/.env.example')"         0 "dotenv template"
check guard-secrets.sh "$(w '/app/src/payments.ts')"      0 "ordinary source file"
check guard-secrets.sh "$(w '/app/README.md')"            0 "ordinary doc"
check guard-secrets.sh '{"tool_input":{}}'                0 "payload with no file_path"

echo "guard-dangerous: rm -rf blocks"
check guard-dangerous-commands.sh "$(c 'rm -rf /')"              2 "root"
check guard-dangerous-commands.sh "$(c 'rm -rf /usr/local/lib')" 2 "absolute path"
check guard-dangerous-commands.sh "$(c 'rm -rf ~/Documents')"    2 "under home"
check guard-dangerous-commands.sh "$(c 'rm -rf ../..')"          2 "parent directory"
check guard-dangerous-commands.sh "$(c 'rm -rf *')"              2 "bare glob"
check guard-dangerous-commands.sh "$(c 'rm -fr /etc')"           2 "flags reversed, still caught"

echo "guard-dangerous: rm -rf allows"
check guard-dangerous-commands.sh "$(c 'rm -rf node_modules')"   0 "node_modules"
check guard-dangerous-commands.sh "$(c 'rm -rf dist coverage')"  0 "build output"
check guard-dangerous-commands.sh "$(c 'rm file.txt')"           0 "plain rm"

echo "guard-dangerous: git"
check guard-dangerous-commands.sh "$(c 'git push --force origin main')"   2 "force-push to main"
check guard-dangerous-commands.sh "$(c 'git push --force origin feat/x')" 0 "force-push to a feature branch"
check guard-dangerous-commands.sh "$(c 'git push origin main')"           0 "ordinary push"

echo "guard-dangerous: redirects"
REDIR_SECRET=$(printf 'echo TOKEN=abc >%s.env' ' ')
REDIR_TEMPLATE=$(printf 'echo PLACEHOLDER >%s.env.example' ' ')
REDIR_ORDINARY=$(printf 'npm test >%sout.log' ' ')
check guard-dangerous-commands.sh "$(c "$REDIR_SECRET")"   2 "into a dotenv"
check guard-dangerous-commands.sh "$(c "$REDIR_TEMPLATE")" 0 "into a dotenv template"
check guard-dangerous-commands.sh "$(c "$REDIR_ORDINARY")" 0 "into an ordinary file"

echo "format-after-edit: never blocks"
check format-after-edit.sh "$(w '/nonexistent/file.ts')" 0 "missing file is a no-op"
check format-after-edit.sh '{"tool_input":{}}'           0 "empty payload is a no-op"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = "0" ] || exit 1
