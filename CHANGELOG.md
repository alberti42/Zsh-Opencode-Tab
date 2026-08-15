# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Z_OC_TAB_BINDKEY` to bind the plugin to a key other than <kbd>TAB</kbd>
  (for example `^G`), avoiding conflicts with completion plugins that re-bind
  <kbd>TAB</kbd>.

### Changed

- The generator agent prompt (`shell_cmd_generator`) handles comments and user
  requests more reliably.
- Updated the zinit installation instructions.
- The release archive now ships the banner image referenced by the README.

### Fixed

- opencode failures are reported instead of silently succeeding. The worker
  previously ignored opencode's exit status and its `error` events, so a failed
  run pasted the raw error JSON into the command line. The failure reason is now
  shown in the ZLE message area and the original request line is restored.
  ([#4](https://github.com/alberti42/Zsh-Opencode-Tab/issues/4))
- `Z_OC_TAB_DEBUG_LOG` is written for failed and malformed runs too. The debug
  log was only written on the success path, so the one case worth inspecting
  never produced a log.
- Re-sourcing the plugin no longer loses the binding to the widget originally
  bound to the trigger key.

## [1.3.1] - 2026-02-10

### Added

- Debug mode logs the exact opencode command line, in copy/pasteable form, for
  reproducing a run outside the plugin.

### Changed

- The opencode workdir is pinned and the bundled agents are bootstrapped into
  it, so sessions and configuration behave consistently regardless of the
  current directory.

### Removed

- Reliance on `OPENCODE_CONFIG_DIR`; the plugin now runs entirely from its
  workdir.

### Fixed

- Improved generator agent behavior and prompt.

## [1.3.0] - 2026-02-10

### Added

- `Z_OC_TAB_OPENCODE_BACKEND_URL` and `Z_OC_TAB_OPENCODE_RUN_MODE`. A reachable
  backend is required for session deletion.
- Logging improvements: timestamps and debug file options.

### Changed

- More robust interaction between ZLE and the TTY.
- Refactored the controller/worker interaction for stability.

### Fixed

- Better handling of error situations.
- Improved prompt and generator agent behavior.

## [1.2.0] - 2026-02-10

### Added

- Persistence and in-place iteration as a first-class workflow: generated output
  can keep the original request line above it, so the request can be edited and
  re-submitted to refine the result.
- Persistence prefixes `#+` (force keep) and `#-` (force replace); plain `#`
  follows the configured default.
- `Z_OC_TAB_PERSIST_DEFAULT` to choose the default behavior for plain `# ...`.
- Separate agent prompt files for generation and explanation, selectable with
  `Z_OC_TAB_OPENCODE_AGENT_GENERATOR` and `Z_OC_TAB_OPENCODE_AGENT_EXPLAINER`.
- Dummy mode for faster local iteration (`Z_OC_TAB_OPENCODE_DUMMY` and
  `Z_OC_TAB_OPENCODE_DUMMY_TEXT`).

### Changed

- Rewrote the README to be easier to scan, and added a "Pro Tip: Iterate In
  Place" section with a multi-step example.
- Clarified that only first-line magic is stripped; extra lines are kept as
  context for iteration.

## [1.1.0] - 2026-02-10

### Added

- Documented the magic prefixes: `#=` to keep the request above the generated
  command, and `#?` to ask for an explanation (printed to the terminal by
  default).

### Changed

- Expanded the configuration documentation, in particular around the spinner and
  the explain output.
- Added a demo video link, cleaned up the mini demo examples, and added
  author/contact and contribution pointers.

## [1.0.0] - 2026-02-10

First release.

[Unreleased]: https://github.com/alberti42/Zsh-Opencode-Tab/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/alberti42/Zsh-Opencode-Tab/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/alberti42/Zsh-Opencode-Tab/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/alberti42/Zsh-Opencode-Tab/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/alberti42/Zsh-Opencode-Tab/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/alberti42/Zsh-Opencode-Tab/releases/tag/v1.0.0
