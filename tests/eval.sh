#!/usr/bin/env bash
# Behaviour eval: runs /speckit-constitution headless on a small existing
# project, once per run, with this preset at a given git ref, and keeps each
# constitution and transcript for reading. It rebuilds the setup of the
# README's v1.1.0 and v1.2.0 "Verified" arms: same fixture, prompt and
# allowlist, no git remote. One difference: the ref is installed and committed
# by the script, where the published v1.2.0 arm was a `specify preset add
# --dev` overlay left uncommitted. The two dropped wordings were never
# commits, so they cannot be re-run.
#
# Usage:  tests/eval.sh <ref> <runs> <out-dir>     from the repository root
#         e.g. tests/eval.sh v1.1.0 3 /tmp/eval && tests/eval.sh HEAD 3 /tmp/eval
#
# Not in CI: each run is a Claude Code session, which needs a login and costs
# tokens, and its result is read, not asserted. The README's tables were
# scored by reading <out-dir>/<ref>/<n>/constitution.md against the definition
# stated there. The author's global agent instructions load in every run, as
# they did for the published tables.
#
# The allowlist leaves out `resolve-template.sh`, as the published runs did:
# the core command then reads the template layers by hand, a fallback it
# forbids, and a run may stop instead of writing (README, "Verified").
set -euo pipefail

usage() {
  echo "usage: tests/eval.sh <ref> <runs> <out-dir>   (runs >= 1)" >&2
  exit 2
}
[ $# -eq 3 ] || usage
ref=$1 runs=$2 out=$3
# A leading zero is refused too: bash arithmetic reads 010 as octal.
case $runs in '' | *[!0-9]* | 0*) usage ;; esac
PRESET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# What sdd-init installs next to this preset.
TEST_FIRST_URL=https://github.com/camilopiedra92/spec-kit-preset-test-first/archive/refs/tags/v1.6.0.zip
PROMPT='/speckit-constitution Ratify the constitution from the rules this project already follows. Do not commit.'
ALLOWED='Read,Write,Edit,Glob,Grep,Bash(ls:*),Bash(cat:*),Bash(git log:*),Bash(git status:*),Bash(git diff:*),Bash(find:*)'

for tool in claude specify uv git curl python3; do
  command -v "$tool" > /dev/null || {
    echo "eval.sh: $tool not found" >&2
    exit 1
  }
done
git -C "$PRESET" rev-parse --verify -q "$ref^{commit}" > /dev/null || {
  echo "eval.sh: $ref is not a commit in this repository" >&2
  exit 1
}
dest="$out/$ref"
[ ! -e "$dest" ] || {
  echo "eval.sh: $dest exists; pick another out-dir" >&2
  exit 1
}

work=$(mktemp -d)
server=
pids=()
# Interrupted, the sessions are stopped too: they would keep spending tokens
# in a directory about to be removed.
trap '[ ${#pids[@]} -eq 0 ] || kill "${pids[@]}" 2> /dev/null
[ -z "$server" ] || kill "$server" 2> /dev/null
rm -rf "$work"' EXIT
# Quiet on success, the whole output on failure (see tests/compose.sh).
quiet() {
  "$@" > "$work/last.log" 2>&1 || {
    echo "FAIL: $*"
    cat "$work/last.log"
    exit 1
  }
}
# The specify CLI's own environment ships PyYAML; preset installs need it.
# Assigned before export, so a failing `uv` is not hidden by export's status.
PY="${SPECKIT_PYTHON_EXECUTABLE:-$(uv tool dir)/specify-cli/bin/python}"
export SPECKIT_PYTHON_EXECUTABLE="$PY"

# The ref is installed the way a project installs a release: a zip of the
# committed tree, served from localhost because the CLI takes plain HTTP from
# there only (see tests/compose.sh).
mkdir "$work/www"
git -C "$PRESET" archive --format=zip --prefix="preset/" -o "$work/www/preset.zip" "$ref"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/www" > /dev/null 2>&1 &
server=$!
# Out of the job table, so the final `wait` waits for the runs only.
disown "$server"
for _ in $(seq 50); do
  curl -sf -o /dev/null "http://127.0.0.1:$port/preset.zip" && break
  sleep 0.1
done

# The fixture: a stdlib CLI with one feature and its tests, and rules a
# constitution can be drawn from (integer cents, the check command).
fixture="$work/fixture"
mkdir -p "$fixture/src/splitter" "$fixture/tests"
cat > "$fixture/src/splitter/__init__.py" << 'EOF'
"""Split a shared expense evenly; amounts are integer cents, never float."""


def split(total_cents: int, people: int) -> list[int]:
    if people <= 0:
        raise ValueError("people must be positive")
    base, rest = divmod(total_cents, people)
    return [base + 1 if i < rest else base for i in range(people)]
EOF
cat > "$fixture/src/splitter/__main__.py" << 'EOF'
import sys

from splitter import split

if __name__ == "__main__":
    print(*split(int(sys.argv[1]), int(sys.argv[2])))
EOF
cat > "$fixture/tests/test_split.py" << 'EOF'
import pytest

from splitter import split


def test_shares_add_up_to_the_total():
    assert sum(split(1000, 3)) == 1000


def test_the_remainder_goes_to_the_first_people():
    assert split(1000, 3) == [334, 333, 333]


def test_nobody_to_split_between_is_refused():
    with pytest.raises(ValueError):
        split(100, 0)
EOF
cat > "$fixture/pyproject.toml" << 'EOF'
[project]
name = "splitter"
version = "0.1.0"
requires-python = ">=3.12"

[dependency-groups]
dev = ["pytest>=8", "ruff>=0.6"]

[tool.pytest.ini_options]
pythonpath = ["src"]

[tool.ruff]
line-length = 100
EOF
cat > "$fixture/README.md" << 'EOF'
# splitter

Splits a shared expense evenly between people. Amounts are integer cents:
floats never touch money. Run the checks with `uv run pytest && uv run ruff check`.
EOF
commit() { git -C "$fixture" -c user.name=eval -c user.email=eval@localhost commit -q -m "$1"; }
git -C "$fixture" init -q -b main
git -C "$fixture" add -A
commit "Split an expense evenly in integer cents"
cd "$fixture"
quiet specify init --here --force --integration claude
quiet specify preset add --from "$TEST_FIRST_URL"
quiet specify preset add --from "http://127.0.0.1:$port/preset.zip"
cd - > /dev/null
git -C "$fixture" add .specify .claude/skills
commit "Initialize Spec Kit with both presets"

mkdir -p "$dest"
for ((i = 1; i <= runs; i++)); do
  # A clone, not a copy: git's fsmonitor socket cannot be copied. The remote
  # the clone adds goes, since the published runs had none and governance
  # reads it.
  git clone -q "$fixture" "$work/run$i"
  git -C "$work/run$i" remote remove origin
  (
    cd "$work/run$i"
    # In the background of this subshell, so the subshell can pass the
    # trap's TERM on: killing the subshell alone would orphan the session,
    # and a background job ignores the terminal's SIGINT.
    claude -p "$PROMPT" --permission-mode dontAsk --allowedTools "$ALLOWED" \
      --output-format stream-json --verbose > transcript.jsonl 2> stderr.log &
    session=$!
    trap 'kill "$session" 2> /dev/null; exit 143' TERM
    status=0
    wait "$session" || status=$?
    mkdir -p "$dest/$i"
    cp transcript.jsonl stderr.log .specify/memory/constitution.md "$dest/$i/"
    echo "$status" > "$dest/$i/exit"
  ) &
  pids+=($!)
done
# Each run is judged on its own: init leaves the template in place, so a run
# that stopped before writing still has a constitution.md, full of the
# template's [PLACEHOLDER] tokens.
failed=0
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || true
  n=$((i + 1))
  if [ "$(cat "$dest/$n/exit" 2> /dev/null || echo missing)" != 0 ]; then
    echo "run $n: claude exited $(cat "$dest/$n/exit" 2> /dev/null || echo '(no exit recorded)')"
    failed=1
  elif grep -qE '\[[A-Z_]+\]' "$dest/$n/constitution.md"; then
    echo "run $n: constitution.md is still the template"
    failed=1
  fi
done
pids=()
echo "eval.sh: $runs runs of $ref in $dest"
exit "$failed"
