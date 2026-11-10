# Nonogram KOReader Plugin

Solve picture cross (nonogram) puzzles directly inside KOReader with tap-friendly controls, automatic progress saving, and optional hints.

## Features

- **Picture puzzles**
  - Over 150 hand-drawn pictures, played in order; the name is revealed when you solve one.
  - Solved pictures are remembered, so **New game** continues with the next unsolved one.
- **Random puzzles**
  - Pick **Random puzzle** under **New game** for a fresh random grid within a reasonable size range.
  - Every puzzle has exactly one solution and can be solved by logic alone, without guessing.
  - A board counts as solved as soon as it satisfies all the clues.
- **Tap-focused board controls**
  - Tap a cell on the board to select it.
  - Use the action buttons below the board to apply an action to the selected cell.
- **Persistent progress**
  - Your current puzzle and board state are saved automatically.
  - When you reopen the plugin, you can continue where you left off.
- **Conflict checking and hints**
  - Check your current progress against the solution.
  - Optionally reveal a helpful hint when you are stuck.
- **Solution view**
  - Temporarily show the full solution for the current puzzle.

## How to open

1. Open KOReader.
2. Go to the main menu.
3. Open the *Tools* section.
4. Select **Nonogram**.

## Basic controls

- **Board**
  - Tap any cell to move the selection.
  - The selected cell is visually highlighted.

- **Top buttons**
  - **New game**: Choose between the next picture puzzle and a random puzzle.
  - **Restart**: Reset the current puzzle to its initial empty state.
  - **Show solution / Hide solution**: Toggle between your own board and the full solution.
  - **Close**: Exit the Nonogram screen and return to KOReader.

- **Action buttons**
  - **Fill cell**: Mark the selected cell as filled (part of the picture).
  - **Mark empty**: Mark the selected cell as empty (a cross / X).
  - **Clear cell**: Remove any mark from the selected cell.
  - **Hint**: Automatically correct or fill a single cell that does not match the solution.
  - **Check**: Highlight conflicts and emphasize satisfied row/column hints.

## Notes

- The plugin always keeps the board within the visible screen area and adapts the cell size to your device.
- When conflicts are detected, incorrect filled cells may be visually highlighted so that you can fix them.
- Showing the solution temporarily disables editing until you hide it again.

## Adding pictures

Pictures live in `nonogram_puzzles.lua` as rows of `#` (filled) and `.` (empty). After adding one, run
`luajit tests/nonogram_puzzles_test.lua` from the plugin folder: it checks that the picture fits the screen
(at most 15 cells per side) and has exactly one solution. Add `show` to print every picture.

## Credits

- This Nonogram plugin is designed and implemented with the assistance of **Windsurf (AI)**.
