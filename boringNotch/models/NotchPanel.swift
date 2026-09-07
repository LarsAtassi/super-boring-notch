//
//  NotchPanel.swift
//  boringNotch
//
//  Panels that can appear in the opened notch, and the user's chosen order.
//

import Defaults
import SwiftUI

/// A section of the opened notch's home view.
///
/// Enabled state deliberately reads and writes the pre-existing `Defaults` keys
/// (`showCalendar`, `showMirror`, ...) rather than storing a second copy. Those
/// keys still gate things outside the home layout — the mirror button in the
/// header, the calendar permission sub-settings — so keeping one source of truth
/// avoids the layout and the rest of the app disagreeing.
enum NotchPanel: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case music
    case calendar
    case shortcuts
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .shortcuts: return "square.stack.3d.up.fill"
        case .mirror: return "web.camera"
        }
    }

    var subtitle: String {
        switch self {
        case .music: return "Album art, track info and playback controls"
        case .calendar: return "Your upcoming events and reminders"
        case .shortcuts: return "Buttons that run your Apple Shortcuts"
        case .mirror: return "Live camera preview"
        }
    }

    var isEnabled: Bool {
        get {
            switch self {
            case .music: return Defaults[.showMusicPanel]
            case .calendar: return Defaults[.showCalendar]
            case .shortcuts: return Defaults[.showShortcutsPanel]
            case .mirror: return Defaults[.showMirror]
            }
        }
        nonmutating set {
            switch self {
            case .music: Defaults[.showMusicPanel] = newValue
            case .calendar: Defaults[.showCalendar] = newValue
            case .shortcuts: Defaults[.showShortcutsPanel] = newValue
            case .mirror: Defaults[.showMirror] = newValue
            }
        }
    }
}

extension Defaults.Keys {
    /// Order only — whether a panel is on lives in that panel's own key.
    static let notchPanelOrder = Key<[NotchPanel]>(
        "notchPanelOrder",
        default: [.music, .calendar, .shortcuts, .mirror]
    )

    /// Columns in the opened notch's grid.
    static let notchGridColumns = Key<Int>("notchGridColumns", default: 3)

    /// How many columns each panel occupies, keyed by `NotchPanel.rawValue`.
    /// Anything missing falls back to `NotchPanel.defaultSpan`.
    static let notchPanelSpans = Key<[String: Int]>("notchPanelSpans", default: [:])

    /// Draw each panel on its own bordered card. Off by default: the notch reads
    /// cleaner when the panels float on the black face with no frame.
    static let notchPanelCards = Key<Bool>("notchPanelCards", default: false)
}

extension NotchPanel {
    /// Music needs room for album art plus controls; the rest read fine narrow.
    var defaultSpan: Int {
        switch self {
        case .music: return 2
        case .calendar, .shortcuts, .mirror: return 1
        }
    }

    /// The mirror is already a solid rounded image; a card behind it just adds a
    /// second border and eats space with padding.
    var wantsCard: Bool {
        self != .mirror
    }

    var span: Int {
        get {
            let stored = Defaults[.notchPanelSpans][rawValue] ?? defaultSpan
            return stored.clamped(to: NotchGrid.spanRange)
        }
        nonmutating set {
            var spans = Defaults[.notchPanelSpans]
            spans[rawValue] = newValue.clamped(to: NotchGrid.spanRange)
            Defaults[.notchPanelSpans] = spans
        }
    }
}

enum NotchGrid {
    static let columnRange: ClosedRange<Int> = 2...6
    static let spanRange: ClosedRange<Int> = 1...4

    /// Packs spans into rows, keeping order and never splitting an item across
    /// rows. A span wider than the grid is clamped to full width rather than
    /// dropped. Pure and index-based so it can be tested without `Defaults`.
    static func packRows(spans: [Int], columns: Int) -> [[Int]] {
        let columns = max(1, columns)
        var rows: [[Int]] = []
        var current: [Int] = []
        var used = 0

        for (index, rawSpan) in spans.enumerated() {
            let span = min(max(1, rawSpan), columns)
            if used + span > columns, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(index)
            used += span
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func rows(for panels: [NotchPanel], columns: Int) -> [[NotchPanel]] {
        packRows(spans: panels.map(\.span), columns: columns)
            .map { $0.map { panels[$0] } }
    }

    /// Columns actually consumed by a row.
    static func usedColumns(in row: [NotchPanel], columns: Int) -> Int {
        row.reduce(0) { $0 + min($1.span, columns) }
    }

    /// Grows a row's spans until they fill the grid exactly.
    ///
    /// A row that uses 3 of 4 columns would otherwise leave a dead column, which
    /// is just dead space by another name. Leftover columns go to the widest
    /// panel first, so the row's proportions stay close to what was configured.
    /// Pure and index-based so it can be tested without `Defaults`.
    static func expandSpans(_ spans: [Int], columns: Int) -> [Int] {
        let columns = max(1, columns)
        guard !spans.isEmpty else { return [] }

        var result = spans.map { min(max(1, $0), columns) }
        var used = result.reduce(0, +)

        // Too wide for the row (a single oversized panel): clamp to the grid.
        if used > columns, result.count == 1 {
            return [columns]
        }

        // Spread the leftover columns round-robin rather than piling them onto
        // one panel: two equal panels in a 4-column grid should end up 2 and 2,
        // not 3 and 1.
        var cursor = 0
        while used < columns {
            result[cursor % result.count] += 1
            cursor += 1
            used += 1
        }
        return result
    }

    /// Rebalances a set of spans after one of them is set explicitly.
    ///
    /// `fixed` is the index the user just changed; it keeps exactly the span they
    /// asked for. The others share what's left, as evenly as possible and never
    /// below one column. Returns nil when the remainder can't cover the others —
    /// the caller should leave them alone and let the rows wrap instead.
    static func rebalance(spans: [Int], fixed: Int, to newSpan: Int, columns: Int) -> [Int]? {
        let columns = max(1, columns)
        guard spans.indices.contains(fixed) else { return nil }

        let others = spans.indices.filter { $0 != fixed }
        let clamped = min(max(1, newSpan), columns)
        guard !others.isEmpty else { return [columns] }

        let remaining = columns - clamped
        // Not enough room to give every other panel a column: don't fight the
        // user's choice, just let the layout wrap onto another row.
        guard remaining >= others.count else { return nil }

        var result = spans
        result[fixed] = clamped

        let base = remaining / others.count
        var extra = remaining % others.count
        for index in others {
            result[index] = base + (extra > 0 ? 1 : 0)
            if extra > 0 { extra -= 1 }
        }
        return result
    }

    @MainActor
    static func effectiveSpan(for panel: NotchPanel, in row: [NotchPanel], columns: Int) -> Int {
        let expanded = expandSpans(row.map(\.span), columns: columns)
        guard let index = row.firstIndex(of: panel), expanded.indices.contains(index) else {
            return min(panel.span, columns)
        }
        return expanded[index]
    }
}

enum NotchPanelLayout {
    /// The stored order, repaired against the current set of panels: unknown
    /// entries dropped, panels added since the order was saved appended. Without
    /// this a panel added in a later version would silently never render.
    @MainActor
    static var orderedPanels: [NotchPanel] {
        let stored = Defaults[.notchPanelOrder]
        let known = stored.filter { NotchPanel.allCases.contains($0) }
        let missing = NotchPanel.allCases.filter { !known.contains($0) }
        return known + missing
    }

    @MainActor
    static func setOrder(_ panels: [NotchPanel]) {
        Defaults[.notchPanelOrder] = panels
    }
}
