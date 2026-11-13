# Spec Delta

## Purpose

Shows the UI in the user's language, using translations derived from gitk's existing catalogs so that work done by gitk's translators carries over.

## ADDED Requirements

### Requirement: Shipped languages
The app SHALL ship translations for every language gitk ships: af, bg, ca, de, es, fr, hu, it, ja, pt_BR, pt_PT, ru, sv, ta, vi and zh_CN. The translations SHALL be generated from `gitk/po/*.po`. English SHALL be the development language and the fallback for strings with no translation.

#### Scenario: German system
- **WHEN** macOS's preferred language is German
- **THEN** menus and dialogs show gitk's German strings, such as "Datei" for the File menu

#### Scenario: Untranslated string
- **WHEN** a string has no translation, or a fuzzy one, in the chosen language
- **THEN** the English text is shown

### Requirement: Mnemonics and format specifiers
Tk mnemonic markers (`&`) SHALL be removed from menu titles. Tcl `%s` and `%d` placeholders SHALL be converted to their positional Foundation equivalents, so translated strings format correctly.

#### Scenario: Formatted message
- **WHEN** "Reset branch %s to %s?" is shown in French
- **THEN** the French text has the branch name and commit ID in the places the translator put them

### Requirement: Language override
The `LC_ALL`, `LC_MESSAGES` and `LANG` environment variables, checked in that order as Tcl msgcat does, SHALL override the system's preferred language when one of them names a shipped language.

#### Scenario: Override from terminal
- **WHEN** the user runs `LANG=ja_JP.UTF-8 gitk-swift`
- **THEN** the UI is shown in Japanese

#### Scenario: C locale
- **WHEN** `LANG=C` and no other variable is set
- **THEN** the system's preferred language is used

### Requirement: Catalog regeneration
A documented script SHALL regenerate the app's localized resources from `gitk/po/*.po`. Re-running it with no `.po` changes SHALL produce byte-identical output.

#### Scenario: Idempotent conversion
- **WHEN** the conversion script is run twice in a row
- **THEN** `git status` shows no changes after the second run
