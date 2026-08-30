# ASS-003 — Visual custom layout editor

**Status:** Functional MVP complete; direct drag-and-drop topology editing remains.

## Goal

Let a user arrange the exact layout for a selected monitor and window count
inside Settings, without moving real windows while editing.

## User flow

1. Select a monitor and a window-count card.
2. Choose **Custom** and click **Edit Layout**.
3. Start from the current preset, the last custom layout or a blank balanced
   layout.
4. Arrange numbered tiles on a monitor-shaped canvas.
5. Save to apply or cancel without changing the active layout.

## Interactions

- Drag a separator to change the split ratio.
- Drag a tile to another tile to swap their logical positions.
- Use **Continue from Previous Count** to copy the preceding card and choose
  where the new window is inserted.
- Use **Split Selected Tile** to divide only one region horizontally or
  vertically, initially at 50/50.
- Use **Apply Preset to Region** to start Dwindle, Columns, Rows, Vertical Pairs
  or Grid inside the selected subtree without replacing the rest of the layout.
- Drop on a directional edge to place a tile left, right, above or below a
  target and update the tree topology.
- Select a split to rotate it, reverse its children or balance it.
- Undo and redo every editor operation.
- Reset from Dwindle, Columns, Rows, Vertical Pairs or Grid.
- Show minimum-size constraints before Save becomes available.

## Acceptance criteria

- Editing is isolated in a draft; Cancel is a true no-op.
- Save persists one blueprint for the exact monitor and count.
- A user can keep a large primary pane, split the layout at window 2, and begin
  a nested Dwindle at window 3, 4 or any later slot.
- Preview aspect ratio matches the selected monitor.
- The editor supports keyboard operation and VoiceOver descriptions.
- The UI remains usable at the Settings minimum window size.
- Unit tests cover commands, undo/redo and geometry hit testing.
