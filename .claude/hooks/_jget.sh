# Shared JSON field reader, sourced by the hooks.
#
# Hook payloads arrive as JSON on stdin. jq is the clean way to read them, but it
# is not guaranteed to be installed on a machine you did not set up, and a hook
# that crashes is worse than one that is absent. So: jq if present, python3 if
# not, and if neither exists the caller exits 0 and the guard is simply off.
#
# Fail-open is the deliberate choice here. These guards protect against an agent
# mistake, not against an adversary; blocking all work because jq is missing
# would trade a small risk for a large one.
jget() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".$1 // empty"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d,dict) else None
print(d if isinstance(d,str) else "")' "$1"
  else
    printf ''
  fi
}
