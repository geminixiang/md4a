#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/md4a.app /path/to/fixture.md" >&2
  exit 64
fi

app=$1
fixture=$2
iterations=${MD4A_OPEN_ITERATIONS:-5}

[[ -d "$app" ]] || { echo "app not found: $app" >&2; exit 66; }
[[ -f "$fixture" ]] || { echo "fixture not found: $fixture" >&2; exit 66; }

cleanup() { pkill -x md4a 2>/dev/null || true; }
trap cleanup EXIT

window_names() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "md4a"
    return name of every window
  end tell
end tell
APPLESCRIPT
}

cleanup
open -na "$app"
sleep 2
pid=$(pgrep -nx md4a)
kill -0 "$pid"
windows=$(window_names)
[[ "$windows" == *"md4a"* ]] || { echo "welcome window missing: $windows" >&2; exit 1; }
[[ "$windows" != *"Open"* ]] || { echo "unexpected open panel: $windows" >&2; exit 1; }
echo "welcome pid=$pid windows=$windows"

for ((run = 1; run <= iterations; run++)); do
  open -a "$app" "$fixture"
  sleep 3
  pid=$(pgrep -nx md4a)
  kill -0 "$pid"
  windows=$(window_names)
  [[ "$windows" == *"$(basename "$fixture")"* ]] || {
    echo "run $run did not open fixture: $windows" >&2
    exit 1
  }
  echo "activation=$run pid=$pid windows=$windows"
done
