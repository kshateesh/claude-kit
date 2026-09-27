#!/bin/bash
# format-after-edit.sh
#
# PostToolUse hook, matcher Edit|Write. Runs the file's own formatter right
# after it is edited, so formatting never shows up in a diff and nobody spends
# review time on it.
#
# Every branch is guarded by a command check and redirects its own errors, so a
# machine without the formatter installed gets a silent no-op rather than noise
# in the transcript. --no-install means npx never pauses to download prettier
# mid-session, which would be its own kind of surprise.

set -uo pipefail
INPUT=$(cat)
. "$(dirname "${BASH_SOURCE[0]}")/_jget.sh"

FILE_PATH=$(jget 'tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md)
    command -v npx >/dev/null 2>&1 && npx --no-install prettier --write "$FILE_PATH" >/dev/null 2>&1
    ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$FILE_PATH" >/dev/null 2>&1
    ;;
  *.py)
    command -v ruff >/dev/null 2>&1 && ruff format "$FILE_PATH" >/dev/null 2>&1
    ;;
esac

exit 0
