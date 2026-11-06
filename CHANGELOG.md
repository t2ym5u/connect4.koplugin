# Changelog

All notable changes to this project will be documented in this file.

## [1.4.0] - 2026-11-05

### Changed
- Easy is really easy now: it looks two moves ahead instead of three and
  often picks a weaker column. Measured, it now wins about half of its
  games against a player who looks one move ahead (it won 70% before).
  Every level still takes a winning move and blocks yours.
- Easy and Medium no longer play the same game twice: a line that beat
  them once will not win every time. Medium now looks four moves ahead
  instead of five, so Hard is clearly stronger than Medium (about 75% of
  the points instead of 63%).

## [1.3.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.3.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.3.0] - 2026-11-04

### Changed
- Much faster AI: it no longer copies the grid for every simulated drop.
  The same depth is searched about 10x faster and plays exactly the same
  columns as before.
- The AI now thinks for at most ~2 s per move on an e-reader (Easy 0.5 s,
  Medium 1 s, Hard 2.2 s). Hard used to take up to ~20 s on a Kobo on some
  moves; it now nearly always reaches its full depth within the limit.

## [1.2.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.2.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.2.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.2.0] - 2026-10-30

### Changed
- Redesigned play screen: the 7×6 board fills the room the controls leave,
  with square cells (the six rows used to be stretched to fill a square
  board), and the column keys 1-7 form an even bar above it, each key over its
  column.
- Once the game is won or drawn, "New game" appears in place of the column
  keys.
- Title-bar menu in the shared order: New game (was "New"), "Difficulty:
  Medium", "Players: 1" (was "1 player"), Rules.
- The status line reads "7×6 · Medium · Turn: Player 1 (Yellow)" (the "(AI=…)"
  part is gone) and wraps in landscape.

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
