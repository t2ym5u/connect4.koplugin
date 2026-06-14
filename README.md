# puissance4.koplugin

A Connect Four (Puissance 4) plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

*(Screenshot to be added.)*

## Rules

Two players alternate dropping pieces into a 7×6 grid. Pieces fall to the lowest empty row in the chosen column. The first player to connect **four in a row** — horizontal, vertical, or diagonal — wins. A full board with no winner is a draw.

## Features

- **Two-player local mode**
- **Win detection** — the four winning pieces are highlighted
- **Undo** — remove the last dropped piece
- **New game** — reset the board at any time
- **Auto-save** — game state saved and restored on next launch

## Installation

1. Download `puissance4.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Connect Four**.

## Controls

| Action | How |
|--------|-----|
| Drop a piece | Tap a column |
| Undo last move | Tap **Undo** |
| New game | Tap **New** |
| Show rules | Tap **Rules** |

## License

GPL-3.0 — see [LICENSE](LICENSE).
