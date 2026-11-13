// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Namespace for module-wide constants of the AppKit UI.
public enum GitkUI {
    public static var coreVersion: String { GitkCore.version }
}
