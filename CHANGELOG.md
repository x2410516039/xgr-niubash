# Changelog

All notable changes to Niubash are documented in this file.

## [Unreleased]

### Features

- **One-shot fast path** for `-c` / `--encoded-command`: skip REPL-only
  initialization on the non-interactive hot path (`890f3b1`)
- **`--encoded-command` v1: prefix**: optional marker so MSYS path conversion
  can never mangle a leading `/` when the command line travels through Git
  Bash (`deb7211`)
- **`--cwd-state <file>`**: directory memory for one-shot agent invocations —
  restore the recorded directory before the command and record the final
  directory after it; atomic temp-file write with retry
  (`5c4ec1d`, docs/cwd-state.md)
- **`--cwd-state-verbose`**: report restore/record lines on stderr for
  debugging the contract

### Performance

- **Lazy history open**: `niu -c` no longer opens the history file at startup;
  the open is deferred to the first `history`/`fc` builtin touch
  (~0.6-0.8 ms saved per one-shot invocation) (`833cc7a`)
- **Framework probe trim**: fewer negative-path stats when resolving the
  oh-my-niu bundle directory (~0.5 ms on bundle-less machines) (`833cc7a`)

## [1.1.2] - 2026-09-15

### Fixes

- **Piped stdin scripts**: decode script source on char boundaries so
  multibyte UTF-8 survives a byte-at-a-time pipe read (#98, `28033c9`)
- **`--dump-strings`**: keep a trailing backslash in unterminated `$"…"`
  literals, matching GNU bash (`8c3d750`)

### Dependencies

- **rubash 1.2.0** pinned from git master `b4cbcadc`; the crate now tracks
  rubash git master instead of the crates.io 1.1.0 release (`daacb8b`,
  `c5bb3a6`)

## [1.1.1] - 2026-09-14

### Features

- **Startup banner** trimmed to a single version line (`676a680`)
- **Self-update diagnostics**: surface WinHTTP error causes and the download
  URLs that failed (`a6e0d1a`)

### Fixes

- **Setup wizard**: ignore key-release events and force-enable VT output on
  startup so Windows 10 conhost renders the wizard correctly (`6f56136`)
- **Read-only install roots**: keep `/tmp` writable and warn once instead of
  failing startup (#94, `27f4b47`)

## [1.1.0] - 2026-09-12

### Highlights

One week of intensive work after v1.0.1: IDE-style completion menu, colorized
plugin CLI, NIU_ENV/BASH_ENV one-shot env files, startup-overhead fix, release
binary size reduction (LTO + panic=abort), and upstream rubash v1.1.0 with the
CTLESC `\x11` leak fix that resolves `NIU_BINDKEYS` parsing.

### Features

- **IDE-style completion menu** with descriptions; humanized plugin CLI views
  (`26610e7`, `a6c1fee`)
- **Colorized plugin CLI**: TTY-gated ANSI styling for plugin list/action
  feedback (`cb72d52`, `3ab1b42`)
- **NIU_ENV / BASH_ENV opt-in env files** for one-shot mode (#82, `ee1c410`)
- **Interactive shell easter eggs** (`30efd9a`)
- **Demo bundle** for plugin development (`f7d2943`)

### Fixes

- **Startup overhead**: skip framework hook dispatch when the runner is
  undefined (#80, `6fbee9f`)
- **CTLESC `\x11` leak** (upstream rubash v1.1.0): quoted assignment fast path
  leaked `\x11` into stored values, breaking `NIU_BINDKEYS="Ctrl+X:..."` parsing
  (`a313729b` in rubash)
- **Hook runner resilience**: hook runners survive user `set -eu` (`6ba7af0`)
- **REPL heredoc-body scanning**: fix completeness check for heredoc bodies
  spanning command-substitution boundaries (`6ba7af0`)
- **WinuxCmd auto-activation**: portable first-run activation with absolute-path
  activate script (`ca574ed`)
- **Panic hook**: best-effort console restore under `panic=abort` (`270d16b`)
- **Rename brand gate**: restore working version drift gate (`92e6724`)
- **$BASH path**: set `$BASH` to the running executable path (`0ea5513`)
- **Completion engine**: wire rubash completion engine, drop hardcoded builtin
  list (`316a8f6`)
- **Heredoc diagnostics** (upstream rubash v1.1.0): warning line numbers now
  use computed `warning_line` matching GNU `make_cmd.c:627` (`a313729b` in
  rubash; remaining gaps tracked in rubash issue #72)
- **Chinese path crash** (#84): `host_path_to_shell_path_with_root` panicked
  with `byte index is not a char boundary` when the shell root byte length
  fell inside a multi-byte character in the current directory path. Added
  `is_char_boundary` guard before slicing. Also fixed
  `longest_common_prefix` in the completion module which had the same class
  of bug when decrementing `prefix_len` through multi-byte characters.

### Build

- **Release binary size**: enable thin LTO + `panic=abort` (-35% size,
  `f94c48d`)
- **Warning suppression**: crate-level `#![allow]` for 11 legacy rubash warnings
  to unblock downstream CI (`a313729b` in rubash)

### Documentation

- Locale default decision for `${#var}` UTF-8 counting (`2f86b3e`)
- Trim redundant README sections; drop stale arm64/version claims (`ceb431e`)
- Add Built-ins & Fast Paths page (`1e35971`)
- Translate architecture page to English (`5a02b7b`)

### Dependencies

- Rubash upgraded from v1.0.0 to **v1.1.0**

## [1.0.1] - 2026-09-04

Initial stable release.
