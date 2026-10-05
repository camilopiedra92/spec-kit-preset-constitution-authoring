# Changelog

All notable changes to this preset are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-05

### Added

- `speckit-constitution` fragment: every principle has a named source (the
  repository, its docs, or the user), never one invented to fill the
  template; ratified principles are kept on amendment; a new project with no
  rules given gets candidates and a question, not a constitution; principles
  not met yet say what must exist; only every-change rules, with phase rules,
  feature decisions and runtime guidance sent to Next Actions; global agent
  instructions are not a source; each MUST names its check; governance only
  as the repository can carry it out; the Sync Impact Report goes into the
  suggested commit message.
- `tests/compose.sh`, reading the appended commands from `preset.yml`: core
  body kept verbatim, fragment last and non-empty, description unchanged, and
  the core steps the fragment builds on still present. CI runs it pinned on
  push and against the latest release weekly.

[Unreleased]: https://github.com/camilopiedra92/spec-kit-preset-constitution-authoring/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/camilopiedra92/spec-kit-preset-constitution-authoring/releases/tag/v1.0.0
