// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Implements the strftime subset of Tcl's `clock format`, in the C locale
/// (English names), with an explicit timezone offset.
public enum TclDateFormat {
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]
    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Parses a git raw timezone such as `+0530` or `-0430` into seconds east of UTC.
    /// Returns nil for malformed input.
    public static func offsetSeconds(fromGitTZ tz: String) -> Int? {
        let u = Array(tz.utf8)
        guard u.count == 5, u[0] == 0x2B || u[0] == 0x2D,
              u[1...].allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        let d = u[1...].map { Int($0) - 0x30 }
        let secs = (d[0] * 10 + d[1]) * 3600 + (d[2] * 10 + d[3]) * 60
        return u[0] == 0x2D ? -secs : secs
    }

    /// Port of gitk proc `formatdate` (gitk/gitk 12152–12180), for one date.
    /// With `useCommitZone` nil, the commit's own offset is used when `format`
    /// contains `%z` or `%Z`; otherwise `localZone` is used.
    public static func format(epoch: Int64, tzOffsetSeconds: Int, format: String,
                              useCommitZone: Bool? = nil,
                              localZone: TimeZone = .current) -> String {
        let commitZone = useCommitZone ?? containsZoneSpecifier(format)
        let offset: Int
        let abbrev: String
        if commitZone {
            offset = tzOffsetSeconds
            // Tcl prints the numeric offset for %Z with a numeric -timezone.
            abbrev = numericZone(offset)
        } else {
            let date = Date(timeIntervalSince1970: TimeInterval(epoch))
            offset = localZone.secondsFromGMT(for: date)
            // %Z is the only specifier that reads the abbreviation, and a
            // format with %Z never takes this branch (it sets commitZone).
            // The abbreviation is therefore only built for the explicit
            // `useCommitZone: false` case; a nil formatter for the common
            // no-zone formats (gitk's default date column) skips the
            // expensive DateFormatter entirely.
            abbrev = hasAbbrevSpecifier(format) ? zoneAbbreviation(date, localZone: localZone) : ""
        }
        return strftime(format, local: epoch + Int64(offset), offset: offset, abbrev: abbrev, epoch: epoch)
    }

    /// Mirrors Tcl `string match {*%[zZ]*}`.
    private static func containsZoneSpecifier(_ f: String) -> Bool {
        hasSpecifier(f, in: "zZ")
    }

    /// Mirrors Tcl `string match {*%Z*}`.
    private static func hasAbbrevSpecifier(_ f: String) -> Bool {
        hasSpecifier(f, in: "Z")
    }

    /// True when `%` followed by a character of `specs` appears in `f`.
    private static func hasSpecifier(_ f: String, in specs: String) -> Bool {
        let c = Array(f.unicodeScalars)
        guard c.count >= 2 else { return false }
        for i in 0..<(c.count - 1) where c[i] == "%" && specs.unicodeScalars.contains(c[i + 1]) { return true }
        return false
    }

    /// The local-zone abbreviation for `%Z`, from one reused formatter.
    /// Building a `DateFormatter` costs tens of microseconds, so the instance
    /// is cached; the lock keeps it safe for callers on any thread.
    private static func zoneAbbreviation(_ date: Date, localZone: TimeZone) -> String {
        abbrevCache.abbreviation(for: date, zone: localZone)
    }

    /// Lock-guarded holder for the cached `%Z` formatter, so the cache can be
    /// an immutable `static let` under Swift 6 strict concurrency.
    private final class AbbrevCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatter: DateFormatter?

        func abbreviation(for date: Date, zone: TimeZone) -> String {
            lock.lock()
            defer { lock.unlock() }
            let f: DateFormatter
            if let cached = formatter {
                f = cached
            } else {
                f = DateFormatter()
                f.locale = Locale(identifier: "en_US")
                formatter = f
            }
            f.timeZone = zone
            f.dateFormat = "zzz"
            return f.string(from: date)
        }
    }

    private static let abbrevCache = AbbrevCache()

    private static func numericZone(_ offset: Int) -> String {
        let a = abs(offset)
        return (offset < 0 ? "-" : "+") + pad(a / 3600, 2, "0") + pad(a % 3600 / 60, 2, "0")
    }

    private static func pad(_ n: Int, _ width: Int, _ ch: Character) -> String {
        let s = String(n)
        return s.count >= width ? s : String(repeating: ch, count: width - s.count) + s
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    private static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    private static func strftime(_ format: String, local: Int64, offset: Int, abbrev: String, epoch: Int64) -> String {
        let dayNum = floorDiv(local, 86400)
        let sod = Int(local - dayNum * 86400)
        // Civil-from-days (Howard Hinnant).
        let z = dayNum + 719468
        let era = floorDiv(z, 146097)
        let doe = Int(z - era * 146097)
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy0 = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy0 + 2) / 153
        let day = doy0 - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + Int(era) * 400 + (month <= 2 ? 1 : 0)
        let wday = Int((dayNum % 7 + 11) % 7) // 1970-01-01 was a Thursday
        let cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let yday = cum[month - 1] + day + (month > 2 && isLeap(year) ? 1 : 0)
        let hour = sod / 3600, minute = sod % 3600 / 60, second = sod % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let yy = pad(((year % 100) + 100) % 100, 2, "0")
        let hms = "\(pad(hour, 2, "0")):\(pad(minute, 2, "0")):\(pad(second, 2, "0"))"

        func expand(_ spec: Character) -> String? {
            switch spec {
            case "Y": return String(year)
            case "C": return pad(year / 100, 2, "0")
            case "y": return yy
            case "m": return pad(month, 2, "0")
            case "d": return pad(day, 2, "0")
            case "e": return pad(day, 2, " ")
            case "H": return pad(hour, 2, "0")
            case "k": return pad(hour, 2, " ")
            case "I": return pad(hour12, 2, "0")
            case "l": return pad(hour12, 2, " ")
            case "M": return pad(minute, 2, "0")
            case "S": return pad(second, 2, "0")
            case "j": return pad(yday, 3, "0")
            case "p": return hour < 12 ? "AM" : "PM"
            case "P": return hour < 12 ? "am" : "pm"
            case "b", "h": return String(months[month - 1].prefix(3))
            case "B": return months[month - 1]
            case "a": return String(days[wday].prefix(3))
            case "A": return days[wday]
            case "u": return String(wday == 0 ? 7 : wday)
            case "w": return String(wday)
            case "s": return String(epoch)
            case "z": return numericZone(offset)
            case "Z": return abbrev
            case "n": return "\n"
            case "t": return "\t"
            case "%": return "%"
            case "c": return "\(days[wday].prefix(3)) \(months[month - 1].prefix(3)) \(pad(day, 2, " ")) \(hms) \(year)"
            case "x": return "\(pad(month, 2, "0"))/\(pad(day, 2, "0"))/\(year)"
            case "D": return "\(pad(month, 2, "0"))/\(pad(day, 2, "0"))/\(yy)"
            case "X", "T": return hms
            case "R": return "\(pad(hour, 2, "0")):\(pad(minute, 2, "0"))"
            default: return nil
            }
        }

        var out = ""
        var it = format.makeIterator()
        while let ch = it.next() {
            guard ch == "%" else { out.append(ch); continue }
            guard let spec = it.next() else { out.append("%"); break }
            if let s = expand(spec) { out += s } else { out.append("%"); out.append(spec) }
        }
        return out
    }
}
