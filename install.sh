#!/bin/bash
# install.sh - drop this kit into a project.
#
# Default is project-scoped: everything lands in ./.claude plus CLAUDE.md and
# AGENTS.md at the project root. Nothing outside the target directory is touched
# and nothing is installed on the machine, which is the point when the machine
# is not mine. --uninstall puts it back.
#
#   ./install.sh                 install into the current directory
#   ./install.sh ../my-app       install into another directory
#   ./install.sh --check         report drift, exit 1 if any
#   ./install.sh --dry-run       print what would change, write nothing
#   ./install.sh --uninstall     remove every file this script installed
#
# Idempotent. Re-running after editing the kit re-syncs the changed files only.

set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=install
TARGET="$PWD"
for arg in "$@"; do
  case "$arg" in
    --check)     MODE=check ;;
    --dry-run)   MODE=dryrun ;;
    --uninstall) MODE=uninstall ;;
    -h|--help)   sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "unknown flag: $arg" >&2; exit 2 ;;
    *)           TARGET="$arg" ;;
  esac
done

[ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

if [ "$TARGET" = "$KIT" ]; then
  echo "refusing to install the kit into itself. Pass a target directory." >&2
  exit 2
fi

# Every file the kit owns. Uninstall reads the same list, so the two can never
# drift apart.
FILES=(
  "AGENTS.md"
  "CLAUDE.md"
  ".claude/settings.json"
  ".claude/rules/frontend.md"
  ".claude/rules/backend.md"
  ".claude/rules/api-contracts.md"
  ".claude/rules/scaffolding.md"
  ".claude/rules/operability.md"
  ".claude/agents/code-reviewer.md"
  ".claude/agents/debugger.md"
  ".claude/agents/infra-reviewer.md"
  ".claude/skills/ship-check/SKILL.md"
  ".claude/hooks/_jget.sh"
  ".claude/hooks/guard-secrets.sh"
  ".claude/hooks/guard-dangerous-commands.sh"
  ".claude/hooks/format-after-edit.sh"
)

DRIFT=0

if [ "$MODE" = "uninstall" ]; then
  for rel in "${FILES[@]}"; do
    [ -f "$TARGET/$rel" ] && { rm -f "$TARGET/$rel"; echo "removed  $rel"; }
  done
  # Only removes directories that are now empty, so a project's own
  # .claude/settings.local.json or extra agents survive.
  find "$TARGET/.claude" -type d -empty -delete 2>/dev/null || true
  echo "uninstalled from $TARGET"
  exit 0
fi

for rel in "${FILES[@]}"; do
  src="$KIT/$rel"
  dst="$TARGET/$rel"
  [ -f "$src" ] || { echo "missing in kit: $rel" >&2; exit 1; }

  if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
    DRIFT=1
    case "$MODE" in
      check)  echo "DRIFT    $rel" ;;
      dryrun) echo "would write  $rel" ;;
      install)
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        case "$rel" in *.sh) chmod +x "$dst" ;; esac
        echo "wrote    $rel"
        ;;
    esac
  fi
done

case "$MODE" in
  check)
    [ "$DRIFT" = "0" ] && { echo "in sync"; exit 0; }
    echo "drift detected - run ./install.sh $TARGET"; exit 1 ;;
  dryrun)
    [ "$DRIFT" = "0" ] && echo "nothing to do"
    exit 0 ;;
esac

[ "$DRIFT" = "0" ] && echo "already in sync"
echo
echo "installed into $TARGET"
echo "next: run '$KIT/verify.sh' to prove the guards actually block, then start Claude Code in $TARGET"
