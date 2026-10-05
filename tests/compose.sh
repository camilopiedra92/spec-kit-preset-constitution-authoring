#!/usr/bin/env bash
# Installs this preset into a scratch Spec Kit project with the real CLI and
# checks what it does to the skill it appends to. The CLI version is whatever
# `specify` is on PATH: CI runs it pinned and against the latest release, which
# is how an upstream change to the core skill shows up here before it shows up
# in a project.
#
# Usage:  tests/compose.sh        from the repository root
set -euo pipefail

PRESET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
server=
trap '[ -n "$server" ] && kill "$server" 2> /dev/null; rm -rf "$work"' EXIT
# Quiet on success, the whole output on failure: the CLI reports through a
# rich console on stdout, so silencing it blindly hid why CI failed.
quiet() {
  "$@" > "$work/last.log" 2>&1 || {
    echo "FAIL: $*"
    cat "$work/last.log"
    exit 1
  }
}
fail=0
problem() {
  echo "FAIL: $*"
  fail=1
}

# The specify CLI's own environment ships PyYAML; the system python3 may not.
PY="${SPECKIT_PYTHON_EXECUTABLE:-$(uv tool dir)/specify-cli/bin/python}"
description() {
  "$PY" -c 'import sys, yaml
text = open(sys.argv[1], encoding="utf-8").read()
print(yaml.safe_load(text.split("---")[1])["description"])' "$1"
}
# The commands come from preset.yml, so a command added there is checked
# without touching this script: one "speckit.x<TAB>commands/x.md" per line.
# Manifest and fragments are read from HEAD, like the archive installed below.
git -C "$PRESET" show HEAD:preset.yml > "$work/preset.yml"
"$PY" -c 'import sys, yaml
m = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for t in m["provides"]["templates"]:
    if t["type"] != "command" or t.get("strategy") != "append":
        sys.exit("compose.sh checks appended commands only: " + t["name"])
    print(t["name"] + "\t" + t["file"])' "$work/preset.yml" > "$work/commands.tsv"

# Installed the way a project installs it: GitHub's tag archive is a zip of the
# committed tree under one top-level directory, minus export-ignore paths, and
# `--from` downloads it. git archive builds the same shape from HEAD, and the
# CLI accepts plain HTTP from localhost only, so a local server stands in for
# GitHub. Uncommitted changes are not in HEAD and so are not tested.
mkdir "$work/www"
quiet git -C "$PRESET" archive --format=zip --prefix="$(basename "$PRESET")/" \
  -o "$work/www/preset.zip" HEAD
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/www" > /dev/null 2>&1 &
server=$!
disown "$server"
for _ in $(seq 50); do
  curl -sf -o /dev/null "http://127.0.0.1:$port/preset.zip" && break
  sleep 0.1
done

cd "$work"
quiet git init -q
# The skills are what is under test, not Claude Code, which a runner lacks:
# without this, init stops at "claude not found".
quiet specify init --here --force --integration claude --ignore-agent-tools
skill_of() { echo ".claude/skills/${1//./-}/SKILL.md"; }
mkdir core
while IFS=$'\t' read -r name _; do
  cp "$(skill_of "$name")" "core/$name.md"
done < commands.tsv

# The fragment builds on these parts of the core skill by name. If upstream
# drops or rewords one, the fragment refers to nothing and has to be revised.
core=core/speckit.constitution.md
anchor() {
  grep -qF -- "$1" "$core" ||
    problem "core speckit-constitution no longer says '$1'; revise the fragment"
}
anchor 'Otherwise infer from existing repo context'
anchor 'exists, load it as the source of current project-specific'
anchor "include a \`Next Actions\` section"
anchor 'Suggested commit message'
anchor 'expected to be removed before the amended constitution file is committed'

quiet specify preset add --from "http://127.0.0.1:$port/preset.zip"

while IFS=$'\t' read -r name file; do
  skill=$(skill_of "$name")
  fragment="fragment.md"
  git -C "$PRESET" show "HEAD:$file" > "$fragment"
  # An empty fragment would pass the tail comparison below.
  grep -q '[^[:space:]]' "$fragment" || problem "$file is empty"
  # Appended: the whole core body survives verbatim, then the fragment closes
  # the file. Not compared line for line from the top: on composing, the CLI
  # re-serializes the frontmatter and adds a title heading (1.1.0).
  "$PY" -c 'import sys
body = lambda p: open(p, encoding="utf-8").read().split("---", 2)[2].strip()
sys.exit(body(sys.argv[1]) not in body(sys.argv[2]))' "core/$name.md" "$skill" ||
    problem "$name lost or changed the core body"
  # Trailing whitespace aside, which the CLI trims when it composes.
  "$PY" -c 'import sys
read = lambda p: open(p, encoding="utf-8").read().rstrip()
sys.exit(not read(sys.argv[2]).endswith(read(sys.argv[1])))' "$fragment" "$skill" ||
    problem "$name does not end with the fragment"
  # The description is what Claude reads to decide when to invoke the skill;
  # a fragment with frontmatter replaces it. Compared as parsed YAML, because
  # the CLI re-serializes the frontmatter whenever it composes a skill.
  [ "$(description "$skill")" = "$(description "core/$name.md")" ] ||
    problem "$name description changed: $(description "$skill")"
done < commands.tsv

specify version > version.txt 2>&1 || true
[ "$fail" -eq 0 ] && echo "ok: composes on specify $(grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' version.txt)"
exit "$fail"
