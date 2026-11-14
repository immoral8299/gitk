// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import CoreGraphics

/// Widths of the history list's three columns (headline, author, date).
///
/// gitk sizes its three list panes with fixed sash positions; here the author
/// and date columns fit their content and the headline column takes what is
/// left, so the whole row fits the list's width. A width the user set by
/// dragging a header divider is kept as is.
struct ColumnSizing: Equatable {
    var subject: CGFloat
    var author: CGFloat
    var date: CGFloat

    /// The auto-fitted author column never grows past this.
    static let authorCap: CGFloat = 200
    /// No column gets narrower than this.
    static let minColumn: CGFloat = 40
    /// The auto-fitted author column gives way before the headline column
    /// shrinks below this.
    static let minSubject: CGFloat = 120

    var total: CGFloat { subject + author + date }

    /// Fits the columns into `available` points (the list's width less the
    /// intercell spacing). `authorContent` and `dateContent` are the widest
    /// measured values, padding included; `userAuthor` and `userDate` are
    /// widths the user dragged a column to, which are kept unchanged.
    ///
    /// The date column always gets its content width; the author column its
    /// content width up to `authorCap`, then less (down to `minColumn`) while
    /// the headline would otherwise drop below `minSubject`. The headline
    /// column takes the rest.
    static func fit(available: CGFloat, authorContent: CGFloat, dateContent: CGFloat,
                    userAuthor: CGFloat? = nil, userDate: CGFloat? = nil) -> ColumnSizing {
        let date = max(minColumn, (userDate ?? dateContent).rounded(.up))
        var author: CGFloat
        if let userAuthor {
            author = max(minColumn, userAuthor.rounded(.up))
        } else {
            author = min(authorCap, max(minColumn, authorContent.rounded(.up)))
            author = max(minColumn, min(author, available - date - minSubject))
        }
        let subject = max(minColumn, (available - author - date).rounded(.down))
        return ColumnSizing(subject: subject, author: author, date: date)
    }

    /// The widths after the user dragged the right edge of `column` so that
    /// the column is `width` wide, starting from `start`. A divider between
    /// two columns moves with the mouse: the column right of it gives or takes
    /// the difference. The date column's right edge has no neighbour, so the
    /// headline column absorbs that change.
    static func dragged(column: Int, to width: CGFloat, from start: ColumnSizing,
                        available: CGFloat) -> ColumnSizing {
        var result = start
        switch column {
        case 0:
            result.subject = width
            result.author = max(minColumn, available - width - start.date)
        case 1:
            result.author = width
            result.date = max(minColumn, available - start.subject - width)
        default:
            result.date = width
            result.subject = max(minColumn, available - start.author - width)
        }
        return result
    }
}
