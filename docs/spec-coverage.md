# Spec coverage

Every scenario in `openspec/changes/rewrite-gitk-in-swift/specs/**/spec.md`, and what proves it.
When you implement a scenario, fill in **Covered by** with a test (`SuiteName/testName`), a snapshot check, or a smoke step (`smoke-test.md #N`), and set **Status** to `covered`.
Task 20.2 checks that no row is still `pending`.

Total scenarios: 168

| Capability | Requirement | Scenario | Covered by | Status |
|---|---|---|---|---|
| cli-launch | gitk-compatible command line | Revision range and paths |  | pending |
| cli-launch | gitk-compatible command line | Select a commit at startup |  | pending |
| cli-launch | gitk-compatible command line | HEAD as select-commit |  | pending |
| cli-launch | gitk-compatible command line | Args command |  | pending |
| cli-launch | Paths without a `--` separator | Bare path argument |  | pending |
| cli-launch | Paths without a `--` separator | Ambiguous argument |  | pending |
| cli-launch | Paths without a `--` separator | Bad revision |  | pending |
| cli-launch | Repository discovery | Not a repository |  | pending |
| cli-launch | Repository discovery | Started from a subdirectory |  | pending |
| cli-launch | Repository argument | Open a repository by path | RepositoryArgumentTests/repositoryRootFromOutsideARepository | covered |
| cli-launch | Repository argument | Subdirectory stays a path | RepositoryArgumentTests/subdirectoryOfCurrentRepositoryStaysAPath | covered |
| cli-launch | Environment and version checks | Git too old |  | pending |
| cli-launch | Environment and version checks | SHA-256 repository |  | pending |
| cli-launch | Environment and version checks | Unknown hash algorithm |  | pending |
| cli-launch | Foreground activation | Launch from terminal |  | pending |
| commit-details | Details sidebar | Sidebar follows selection |  | pending |
| commit-details | Identity and metadata | Merge commit |  | pending |
| commit-details | Message section | Commit with notes |  | pending |
| commit-details | Message section | Message section collapses |  | pending |
| commit-details | Nearby refs | Nearby tags computed in the background |  | pending |
| commit-details | Nearby refs | Too many branches |  | pending |
| commit-details | Nearby refs | Index reused across launches |  | pending |
| commit-details | Commit-ID links | Revert message link |  | pending |
| commit-details | Commit-ID links | Unknown hash |  | pending |
| commit-details | Web links | Open a URL |  | pending |
| commit-details | Comment wrapping | Word wrap |  | pending |
| commit-details | Annotated tag display | Click a tag | TagDisplayTests/annotatedTagShowsTaggerMessageAndObject | covered |
| commit-find | Search kinds | Pickaxe search |  | pending |
| commit-find | Text matching options | Case-insensitive author search |  | pending |
| commit-find | Text matching options | Invalid regexp |  | pending |
| commit-find | Advanced search options | Options stay out of the bar |  | pending |
| commit-find | Advanced search options | Advanced filters |  | pending |
| commit-find | Advanced search options | Defaults |  | pending |
| commit-find | Live highlighting | Highlight while typing |  | pending |
| commit-find | Match boxes | Match boxes |  | pending |
| commit-find | Match boxes | Current match box |  | pending |
| commit-find | Match boxes | Matches in visible text |  | pending |
| commit-find | Search performance | Responsive search on a large repo |  | pending |
| commit-find | Search performance | Stale results never appear |  | pending |
| commit-find | Search performance | Prefix refinement reuses results |  | pending |
| commit-find | Search performance | Cancellation |  | pending |
| commit-find | Stepping through matches | Wraparound |  | pending |
| commit-find | Stepping through matches | No wrap with Shift |  | pending |
| commit-find | Match counter and progress | Match counter |  | pending |
| commit-find | Match counter and progress | Searching status |  | pending |
| commit-find | Touching-paths patterns | Directory path |  | pending |
| commit-find | Touching-paths patterns | Quoted path with spaces |  | pending |
| commit-find | Focus shortcuts | Slash to search |  | pending |
| commit-graph | Lane layout parity | Matches gitk on reference repositories |  | pending |
| commit-graph | Lane layout parity | Linear history |  | pending |
| commit-graph | Long-line truncation | Distant parent |  | pending |
| commit-graph | Long-line truncation | Arrow jump |  | pending |
| commit-graph | Commit markers | HEAD marker |  | pending |
| commit-graph | Commit markers | Local-changes markers |  | pending |
| commit-graph | Line colours | Straight branch keeps colour |  | pending |
| commit-graph | Graph width limit | Very wide graph |  | pending |
| commit-graph | Ref labels | Current branch label |  | pending |
| commit-graph | Ref labels | Remote label |  | pending |
| commit-graph | Ref labels | Many tags on one commit |  | pending |
| commit-graph | Ref labels | Context menu on a head label | RefLabelHitTests/adjacentLabelsUseHalfOpenBounds | covered |
| commit-graph | Line interaction | Click a line |  | pending |
| commit-list | Window layout | Initial layout |  | pending |
| commit-list | Window layout | Narrow window |  | pending |
| commit-list | Titlebar controls | No top bar |  | pending |
| commit-list | Titlebar controls | No unified titlebar |  | pending |
| commit-list | Three-column list | Synchronized scrolling |  | pending |
| commit-list | Three-column list | Date format with timezone |  | pending |
| commit-list | Selection | Select a commit |  | pending |
| commit-list | Selection | Auto-copy |  | pending |
| commit-list | Selection | Default selection |  | pending |
| commit-list | Keyboard navigation | j/k navigation |  | pending |
| commit-list | Keyboard navigation | Letter keys inside a field |  | pending |
| commit-list | Keyboard navigation | Go to parent |  | pending |
| commit-list | Back/forward history | Back after following a link |  | pending |
| commit-list | Go to commit | Abbreviated ID |  | pending |
| commit-list | Commit resolution errors | Not in view |  | pending |
| commit-list | Row context menu | Context menu on a fake row | RowMenuTests/fakeRowHasOnlyDiffAndPatch, RowMenuTests/attachedMenuOnLocalChangesRow | covered |
| commit-list | Status and progress | Status during load |  | pending |
| commit-list | Mouse scrolling | Wheel multiplier |  | pending |
| diff-viewer | Diff pane placement | Selection shows the diff |  | pending |
| diff-viewer | Patch display | Ordinary commit |  | pending |
| diff-viewer | Patch display | Rename |  | pending |
| diff-viewer | Patch display | Large diff |  | pending |
| diff-viewer | Merge diffs | Octopus merge | DiffModeTests/octopusMarkersUseConfiguredParentColors; `Tools/snapshot.sh evil-octopus /tmp/octopus.png` (three colored marker columns, visually verified) | covered |
| diff-viewer | Local-changes and two-commit diffs | Unstaged row |  | pending |
| diff-viewer | Local-changes and two-commit diffs | Index row |  | pending |
| diff-viewer | Diff controls | Old version |  | pending |
| diff-viewer | Diff controls | Context lines |  | pending |
| diff-viewer | Diff controls | Color words |  | pending |
| diff-viewer | Path-limited diffs | Limited view |  | pending |
| diff-viewer | Text search in the pane | Incremental search | PaneSearchTests/highlightsEveryMatchAndSelectsFirstAfterCursor, PaneSearchTests/nextAndPreviousStepAndStopAtEnds | covered |
| diff-viewer | Pane scrolling keys | Next file |  | pending |
| diff-viewer | Tree mode | View a file at a revision |  | pending |
| diff-viewer | Per-file encodings | Shift-JIS file | GitAttributesTests/shiftJISFileTextDecodes | covered |
| diff-viewer | Line origin | Origin of an added line | LineOriginTests/normalHunkCoordinates, LineOriginTests/wholeDiffLookupMatchesHunkLookup, LineOriginTests/findsNewFileLineInDiff | covered |
| file-list | Changed Files section | Jump to file |  | pending |
| file-list | Changed Files section | Change totals |  | pending |
| file-list | Linked highlighting | Scroll the diff |  | pending |
| file-list | Tree mode | Expand a directory |  | pending |
| file-list | File context menu | External diff |  | pending |
| file-list | File context menu | External diff with a renamed file |  | pending |
| file-list | File context menu | Highlight this only |  | pending |
| file-list | File context menu | Copy path |  | pending |
| file-list | Temporary file cleanup | Quit after external diff |  | pending |
| history-loading | Streaming commit load | Large repository |  | pending |
| history-loading | Streaming commit load | git log fails |  | pending |
| history-loading | Display ordering | Parents below children |  | pending |
| history-loading | Display ordering | Late-arriving child |  | pending |
| history-loading | Boundary and parent rewriting | Range view |  | pending |
| history-loading | Commit metadata parsing | Non-UTF-8 commit |  | pending |
| history-loading | Commit metadata parsing | Unsupported encoding |  | pending |
| history-loading | References | Annotated tag |  | pending |
| history-loading | References | Detached HEAD |  | pending |
| history-loading | Update, reload and reread references | New commit then Update |  | pending |
| history-loading | Update, reload and reread references | Reload after a ref moved away |  | pending |
| history-loading | Local-changes rows | Staged and unstaged changes |  | pending |
| history-loading | Local-changes rows | Changes resolved |  | pending |
| history-loading | Local-changes rows | Path-limited view |  | pending |
| history-loading | Cancellation | Switch view mid-load |  | pending |
| localization | Shipped languages | German system |  | pending |
| localization | Shipped languages | Untranslated string |  | pending |
| localization | Mnemonics and format specifiers | Formatted message |  | pending |
| localization | Language override | Override from terminal |  | pending |
| localization | Language override | C locale |  | pending |
| localization | Catalog regeneration | Idempotent conversion |  | pending |
| preferences | Preferences window | Change a colour |  | pending |
| preferences | Preferences window | Cancel | PrefsGeneralTests/cancelDiscardsChanges | covered |
| preferences | General settings page | Toggle local changes |  | pending |
| preferences | Colour and font settings pages | Change the text font |  | pending |
| preferences | Colour and font settings pages | Change a search colour |  | pending |
| preferences | Defaults match gitk on macOS | Fresh install |  | pending |
| preferences | Persistence | Geometry restored |  | pending |
| preferences | Persistence | Sidebar state restored |  | pending |
| preferences | Persistence | Corrupt settings |  | pending |
| preferences | Legacy gitk config import | Import existing config |  | pending |
| preferences | Legacy gitk config import | Config with code |  | pending |
| preferences | Legacy gitk config import | Legacy file untouched |  | pending |
| preferences | Font size shortcuts | Increase font |  | pending |
| preferences | Quit and close | Quit during load |  | pending |
| reference-list | Reference list window | Open with F2 | RefListModelTests/openListsAllHeadsAndTags | covered |
| reference-list | Filtering and sorting | Filter refs | RefListModelTests/globFilter | covered |
| reference-list | Jump to reference | Ref outside view | RefListModelTests/refOutsideViewIsOmitted | covered |
| reference-list | Live updates and geometry | Branch created while open |  | pending |
| repository-actions | Commit context menu | No mark set | RowMenuTests/orderAndMarkEnablement, RowMenuTests/attachedMenuFollowsSessionMark | covered |
| repository-actions | Diff between two commits | Diff against selection |  | pending |
| repository-actions | Mark and compare | Compare cherry-picked series |  | pending |
| repository-actions | Branch operations | Create branch | BranchDialogTests/emptyNameAndConfirmedOverwrite | covered |
| repository-actions | Branch operations | Remove current branch |  | pending |
| repository-actions | Branch operations | Checkout with local changes |  | pending |
| repository-actions | Tag creation | Annotated tag | CreateTagTests/annotatedTagAndValidation, CreateTagTests/emptyMessageMakesLightweightTagAndLabelIsInSession | covered |
| repository-actions | Cherry-pick and revert | Successful cherry-pick |  | pending |
| repository-actions | Cherry-pick and revert | Conflict |  | pending |
| repository-actions | Cherry-pick and revert | Nothing to commit |  | pending |
| repository-actions | Reset | Hard reset | ResetTests/mixedDefaultAndHardResetRefreshesChanges | covered |
| repository-actions | Patch and commit export | Make patch | MakePatchTests/patchAppliesAtParent, MakePatchTests/reverseSwapsEndpointsAndGeneratesReversePatch | covered |
| repository-actions | Copy commit reference | Copy reference |  | pending |
| repository-actions | External tools | git gui missing |  | pending |
| repository-actions | Error reporting for write operations | Branch already exists outside the app |  | pending |
| views | Command-line view | No arguments |  | pending |
| views | View editor | Create a view |  | pending |
| views | View editor | Apply without closing |  | pending |
| views | View editor fields | Pickaxe as regexp |  | pending |
| views | View editor fields | Paths field |  | pending |
| views | Round-trip of view arguments | Edit a command-line view |  | pending |
| views | Switching and deleting views | Switch keeps selection |  | pending |
| views | Remembered views | Persist across launches |  | pending |
| views | Remembered views | Unchecked view not saved |  | pending |
| views | Merge-conflict view | Merge in progress |  | pending |
