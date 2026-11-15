# Manual smoke test

Run against a repository with merges and long-running lines, with
`GITK_SWIFT_CONFIG_DIR` pointing at a temp directory.

## Graph line interaction (task 10.9)

1. Hover over a graph line (not the dot) and rest the pointer. A tooltip shows
   the subject of the line's parent commit. Moving off the line removes it.
2. Click a line leading down from a commit. The line is drawn thicker, the list
   selection is cleared, and the details sidebar lists the parent as "Parent"
   and each of its children under "Children", with author and date, each ID a
   link that selects that commit.
3. Click the thicker line's commit or any other row. The line returns to normal
   width.
4. In a history with a long line (a merge whose parent is far below), click the
   down arrow under the merge. The list scrolls so the matching up arrow's row
   is centred. Click that up arrow to jump back.
