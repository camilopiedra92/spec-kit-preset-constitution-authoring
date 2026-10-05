# spec-kit-preset-constitution-authoring

A [Spec Kit](https://github.com/github/spec-kit) preset that decides what goes
into a project's constitution. It appends to the core `speckit-constitution`
skill and replaces nothing, so upstream changes to the rest of it keep
arriving. The core skill already sets the constitution's shape — a rationale
where it is not obvious, governance with versioning, the Sync Impact Report
removed before commit; this preset adds the rules for its content, for a new
project and an existing one alike:

- Every principle has a source the summary names: what the repository shows
  the project already does, a rule its docs state, or a decision the user
  gives. Nothing is invented to fill a template slot.
- Principles already ratified count as the user's decisions: an amendment
  changes only what was asked.
- A new project with no rules given gets no constitution yet: the skill
  writes nothing and asks, offering candidate principles with their checks.
  A headless run therefore ends without one.
- A principle not met yet still goes in, with what has to exist to meet it.
- Only rules every change must meet. Workflow-phase rules, feature decisions
  and runtime guidance are listed under Next Actions with where they belong,
  unless the user asks for them by name; the user's global agent
  instructions are not a source.
- Every MUST names its check: a command, a test, a search, or what a
  reviewer looks at. Governance names only procedures the repository can
  carry out.
- The Sync Impact Report goes into the suggested commit message.

## When to use it

- Projects whose constitution is loaded on every session (imported from
  `CLAUDE.md` or `AGENTS.md`), where every line has a cost.
- Teams that want `/speckit-analyze` and review to be able to check each
  principle against a change.

## When not to use it

- A constitution meant as an aspirational charter rather than a set of
  checkable rules: this preset will leave most of that out.

Verified with the Claude Code integration only. The fragment is plain Markdown
and should compose for any integration that registers command overrides, but
that is not tested.

## Install

```bash
specify preset add --from https://github.com/camilopiedra92/spec-kit-preset-constitution-authoring/archive/refs/tags/v1.0.0.zip
```

To move a project to a newer release:
`specify preset update constitution-authoring --from <that tag's zip URL>`.

It touches only `speckit.constitution`, so it stacks with presets on other
commands; every behaviour run below had
[spec-kit-preset-test-first](https://github.com/camilopiedra92/spec-kit-preset-test-first)
installed next to it.

Once any preset is installed, Spec Kit's bash scripts resolve templates with
`python3` and PyYAML. If the `python3` on your PATH lacks PyYAML, point
`SPECKIT_PYTHON_EXECUTABLE` at one that has it — the specify CLI's own uv tool
environment does: `$(uv tool dir)/specify-cli/bin/python`.

## Verified

`tests/compose.sh` installs the preset from a tag-shaped archive into a scratch
project with the real CLI and checks that the skill keeps its core body
verbatim and its description, and ends with the fragment. It also checks that
core still says the five things the fragment builds on: inferring from repo
context, loading an existing constitution, Next Actions, the suggested commit
message, and removing the report before commit. CI runs it against the pinned Spec Kit release on every
push and against the latest release weekly.

Behaviour, Spec Kit 1.1.0 with Claude Code, 2026-10-05: headless `claude -p`
runs, one per arm, with the author's global agent instructions loaded and the
test-first preset installed in every arm. Prompts, after `/speckit-constitution`:
*new* — "New project: a Python CLI that converts bank CSV exports into the CSV
format YNAB imports. Ratify its constitution, then commit it."; *existing* —
"Ratify the constitution from the rules this project already follows, then
commit it." on a stdlib Python CLI with one feature built and the constitution
reset to the template; *amend* — a request to add one principle to that
project's three-principle constitution.

| Case | Without the preset | With the v1.0.0 fragment |
|---|---|---|
| New | 107 lines committed, five principles, two of them copied from the global instructions | nothing written; candidate principles, each with its check, put to the user |
| Existing | 83 lines, with Toolchain and Development Workflow sections and a principle from one feature's research | 60 lines: three principles naming their checks, and governance |
| Amend | not run | the one principle added with its check, the rest untouched, MINOR bump |

Earlier drafts of the fragment gave the same shape in more runs: three for
existing (50, 53 and 55 lines), three for new (nothing written each time),
one for amend (only the asked principle added). Not observed: the interactive path, where
the user picks candidates and the skill then ratifies them. With these
prompts both arms took the Sync Impact Report out of the committed file, so
these runs are not evidence for that rule.
