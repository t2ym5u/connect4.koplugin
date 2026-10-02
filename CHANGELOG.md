# Changelog

All notable changes to this project will be documented in this file.

## [1.1.17] - 2026-10-02

### Fixed
- Aligned `1 player (vs AI)` on "1 joueur (contre l'IA)", and the Spanish
  equivalent. `package.loaded` is keyed by module name alone, so every
  `require("i18n")` on the device resolves to one module and the first plugin
  loaded wins it. Every plugin's `i18n_fr.lua` merges into that one shared
  table, where plugins silently overwrite each other's translations. This
  plugin and chess disagreed on the string, so whichever merged last decided
  it for both.

## [1.1.16] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.15] - 2026-09-30

### Fixed
- The root search gave every column a fresh (-infinity, +infinity) window,
  which discarded every cutoff between siblings — most of what alpha-beta is
  for. It now carries the running best score into each subsequent search.
  Play is unchanged (verified: the two versions pick the same column in
  289 of 289 random positions); it simply takes about a third less time,
  0.006s per move against 0.009s at the default depth.
