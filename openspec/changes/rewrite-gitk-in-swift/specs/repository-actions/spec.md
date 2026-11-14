# Spec Delta

## Purpose

Defines the actions available from the commit and branch context menus that change the repository, write files, compare commits, or launch external git tools, with gitk's dialogs, confirmations and error handling.

## ADDED Requirements

### Requirement: Commit context menu
Secondary-clicking a commit row SHALL offer, in this order:
- Diff this -> selected, Diff selected -> this
- Make patch, Create tag, Copy commit reference, Write commit to file
- Create new branch, Cherry-pick this commit, Reset HEAD branch to here
- Mark this commit, Return to mark, Find descendant of this and mark, Compare with marked commit
- Diff this -> marked commit, Diff marked commit -> this
- Revert this commit

Items that need a mark SHALL be disabled when no commit is marked.

#### Scenario: No mark set
- **WHEN** no commit is marked and the user opens the menu
- **THEN** "Return to mark", "Compare with marked commit" and both "marked commit" diff items are disabled

### Requirement: Diff between two commits
"Diff this -> selected" and the other diff items SHALL show the diff from the first commit to the second in the diff pane and the Changed Files section. The details sidebar SHALL name both commits as links.

#### Scenario: Diff against selection
- **WHEN** commit A is selected and the user chooses "Diff this -> selected" on commit B
- **THEN** the pane shows `git diff-tree` output from B to A

### Requirement: Mark and compare
"Mark this commit" SHALL mark a single commit, drawn with the marked-line background. "Return to mark" SHALL select it. "Find descendant of this and mark" SHALL mark the nearest commit that descends from both the clicked commit and the marked commit. "Compare with marked commit" SHALL compare the commits from each side by patch ID and list those with no equivalent on the other side.

#### Scenario: Compare cherry-picked series
- **WHEN** a series was cherry-picked onto another branch and the user compares the tips
- **THEN** commits with equal patch IDs are reported as equivalent and the rest are listed as differing

### Requirement: Branch operations
- "Create new branch" SHALL ask for a name. It SHALL refuse an empty name, and SHALL ask for confirmation before overwriting an existing branch.
- The branch label menu SHALL offer: Check out this branch, Rename this branch, Remove this branch and Copy branch name.
- Removing the checked-out branch SHALL be refused. Removing a branch whose commits are on no other branch SHALL need confirmation.

#### Scenario: Create branch
- **WHEN** the user creates branch `topic` at commit X
- **THEN** `git branch topic X` runs and a `topic` label appears on X without a reload

#### Scenario: Remove current branch
- **WHEN** the user chooses "Remove this branch" on the checked-out branch
- **THEN** "Cannot delete the currently checked-out branch" is shown and nothing changes

#### Scenario: Checkout with local changes
- **WHEN** checkout fails because local changes would be overwritten
- **THEN** git's error is shown, and HEAD and labels are unchanged

### Requirement: Tag creation
"Create tag" SHALL show the commit ID, a tag name and an optional message. If a message is given, the tag SHALL be annotated. It SHALL refuse empty or already-existing names.

#### Scenario: Annotated tag
- **WHEN** the user enters name `v2.0` and message "Release 2.0"
- **THEN** an annotated tag `v2.0` is created and its label appears on the commit

### Requirement: Cherry-pick and revert
Cherry-pick and revert SHALL run git on the clicked commit:
- If the commit is already in the current branch, cherry-pick SHALL ask "really re-apply it?" before running.
- If the operation fails because of local changes, the app SHALL name the blocking file.
- If it fails because of a conflict, the app SHALL offer to run `git citool`.
- On success the new commit SHALL be added on top of HEAD and selected.

#### Scenario: Successful cherry-pick
- **WHEN** the user cherry-picks a commit from another branch onto a clean HEAD
- **THEN** a new commit appears as HEAD's child, the current branch label moves to it, and it is selected

#### Scenario: Conflict
- **WHEN** the cherry-pick conflicts
- **THEN** the app asks "Cherry-pick failed because of merge conflict. Do you wish to run git citool to resolve it?" and the view is updated whatever the answer

#### Scenario: Nothing to commit
- **WHEN** the cherry-pick leaves HEAD unchanged
- **THEN** "No changes committed" is shown

### Requirement: Reset
"Reset HEAD branch to here" SHALL show "Reset branch <branch> to <id>?" with Soft, Mixed (the default) and Hard choices, and run the matching `git reset` only after confirmation.

#### Scenario: Hard reset
- **WHEN** the user picks Hard and confirms
- **THEN** `git reset --hard <id>` runs, the branch label moves, and the local-changes rows are refreshed

### Requirement: Patch and commit export
"Make patch" SHALL show From and To IDs, a Reverse option and an output file (default `patch<n>.patch`), then write `git diff-tree -p` output to that file. "Write commit to file" SHALL run a configurable command (default `git diff-tree --stdin -p --pretty=email`) with the commit ID on stdin and write the output to the chosen file.

#### Scenario: Make patch
- **WHEN** the user generates a patch from A to B into `fix.patch`
- **THEN** `fix.patch` contains the diff from A to B, which `git apply` can apply

### Requirement: Copy commit reference
"Copy commit reference" SHALL copy the output of `git show -s --pretty=format:'%h ("%s", %ad)' --date=short`. The hash SHALL be abbreviated to the "Length of commit ID to copy" setting when that is shorter than the full hash.

#### Scenario: Copy reference
- **WHEN** the copy length is 7 and the user copies the reference of a commit
- **THEN** the clipboard holds text like `1a2b3c4 ("Fix widget sizing", 2026-03-01)`

### Requirement: External tools
File→"Start git gui" SHALL start `git gui` in the background. The app SHALL keep running when an external tool fails, and SHALL show the tool's error output.

#### Scenario: git gui missing
- **WHEN** `git gui` is not installed and the user chooses "Start git gui"
- **THEN** an error dialog shows git's message and the app keeps running

### Requirement: Error reporting for write operations
Every action that changes the repository SHALL show the "busy" status while running. It SHALL show git's error output if the action fails, and leave the displayed refs consistent with the repository afterwards.

#### Scenario: Branch already exists outside the app
- **WHEN** creating a branch fails because another process created it first
- **THEN** git's error is shown and the labels match the repository after "Reread references"
