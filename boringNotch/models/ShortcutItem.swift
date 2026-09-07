//
//  ShortcutItem.swift
//  boringNotch
//
//  User-configured Apple Shortcuts, surfaced as tiles in the opened notch.
//

import Defaults
import SwiftUI

/// Preset tile colours, picked to sit in the same family as the cards in
/// Shortcuts.app rather than the raw system palette, which reads harsher on the
/// notch's black background.
enum ShortcutTint: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case accent
    case red, orange, yellow, lime, green, mint, teal
    case skyBlue, blue, indigo, purple, magenta, pink
    case brown, taupe, slate, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .accent: return .effectiveAccent
        case .red: return Color(hex: "F2645F")
        case .orange: return Color(hex: "F0894F")
        case .yellow: return Color(hex: "F2C230")
        case .lime: return Color(hex: "A8C93A")
        case .green: return Color(hex: "3BB85C")
        case .mint: return Color(hex: "38C7A8")
        case .teal: return Color(hex: "1FADA8")
        case .skyBlue: return Color(hex: "35A9E8")
        case .blue: return Color(hex: "2A87E0")
        case .indigo: return Color(hex: "5A63D6")
        case .purple: return Color(hex: "8A5CD6")
        case .magenta: return Color(hex: "B060D6")
        case .pink: return Color(hex: "EE6A8C")
        case .brown: return Color(hex: "A98262")
        case .taupe: return Color(hex: "BFAE92")
        case .slate: return Color(hex: "8C98A6")
        case .gray: return Color(hex: "8E8E93")
        }
    }

    var title: String {
        switch self {
        case .accent: return "Accent"
        case .skyBlue: return "Sky Blue"
        default: return rawValue.capitalized
        }
    }
}

/// How a tile's face is painted.
enum ShortcutTileStyle: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
    /// Shortcuts.app's look: a saturated diagonal gradient.
    case gradient
    /// Flat, fully saturated.
    case filled
    /// Translucent tinted panel — quietest against album art.
    case glass
    /// Dark face, coloured border and glyph.
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient: return "Gradient"
        case .filled: return "Filled"
        case .glass: return "Glass"
        case .outline: return "Outline"
        }
    }
}

struct ShortcutItem: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: UUID = UUID()
    /// Must match the shortcut's name in Shortcuts.app — this is what gets run.
    var name: String
    /// Label shown in the notch. Falls back to `name` when blank.
    var label: String = ""
    var symbol: String = "bolt.fill"
    var tint: ShortcutTint = .accent
    /// Overrides `tint` when set. Stored as "RRGGBB".
    var colorHex: String? = nil
    var style: ShortcutTileStyle = .gradient
    var showsLabel: Bool = true

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    var color: Color {
        if let colorHex, let custom = Color(hexOrNil: colorHex) { return custom }
        return tint.color
    }

    // Decoded leniently: items saved before these fields existed are missing the
    // keys entirely, and the synthesised initialiser would reject them outright.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "bolt.fill"
        // `try?` rather than `try` on the enums: a present-but-unrecognised value
        // (a hand-edited plist, or a tint removed in a later version) would
        // otherwise throw, and because these are stored as one array in Defaults
        // a single bad field would take every shortcut down with it. Falling back
        // to a default loses one attribute instead of the whole list.
        tint = (try? c.decodeIfPresent(ShortcutTint.self, forKey: .tint)) ?? .accent
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? nil
        style = (try? c.decodeIfPresent(ShortcutTileStyle.self, forKey: .style)) ?? .gradient
        showsLabel = (try? c.decodeIfPresent(Bool.self, forKey: .showsLabel)) ?? true
    }

    init(
        id: UUID = UUID(),
        name: String,
        label: String = "",
        symbol: String = "bolt.fill",
        tint: ShortcutTint = .accent,
        colorHex: String? = nil,
        style: ShortcutTileStyle = .gradient,
        showsLabel: Bool = true
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.symbol = symbol
        self.tint = tint
        self.colorHex = colorHex
        self.style = style
        self.showsLabel = showsLabel
    }
}

// MARK: - Hex colour helpers

extension Color {
    init(hex: String) {
        self = Color(hexOrNil: hex) ?? .gray
    }

    init?(hexOrNil hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// "RRGGBB", or nil if the colour has no sRGB representation.
    var hexString: String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((components.redComponent * 255).rounded())
        let g = Int((components.greenComponent * 255).rounded())
        let b = Int((components.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension Defaults.Keys {
    static let shortcutItems = Key<[ShortcutItem]>("shortcutItems", default: [])
    static let showShortcutsPanel = Key<Bool>("showShortcutsPanel", default: false)
    static let showMusicPanel = Key<Bool>("showMusicPanel", default: true)
    /// Close the notch after firing a shortcut, so it behaves like a launcher.
    static let closeNotchAfterShortcut = Key<Bool>("closeNotchAfterShortcut", default: true)
    /// Tile size in the notch's shortcut grid.
    static let shortcutTileHeight = Key<CGFloat>("shortcutTileHeight", default: 62)
}

enum ShortcutsRunner {
    /// Runs a shortcut via the `shortcuts://` URL scheme.
    ///
    /// This is used in preference to spawning `/usr/bin/shortcuts` because the
    /// app is sandboxed: a child process inherits the sandbox and cannot read
    /// the Shortcuts database, whereas opening a URL is always permitted.
    @MainActor
    static func run(_ item: ShortcutItem) {
        guard let url = runURL(for: item.name) else { return }
        NSWorkspace.shared.open(url)
    }

    static func runURL(for name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Encode the name by hand rather than via URLQueryItem. URLComponents
        // leaves "+" literal, and a receiver that treats the query as form-encoded
        // would read that as a space — so a shortcut named "Focus +1" would fail to
        // match. Escaping everything outside the unreserved set avoids the whole
        // class of problem.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    }

    /// Opens Shortcuts.app so the user can look up or create a shortcut.
    @MainActor
    static func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Best-effort list of the user's shortcuts, for the settings picker.
    ///
    /// Returns an empty array under the sandbox, where the CLI cannot reach the
    /// Shortcuts database — callers must keep manual name entry available.
    static func installedShortcuts() -> [String] {
        let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return [] }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// Glyphs offered in the picker, grouped the way Shortcuts.app groups its own.
/// Any SF Symbol name can still be typed in by hand.
enum ShortcutSymbolLibrary {
    static let groups: [(name: String, symbols: [String])] = [
        ("Suggested", [
            "bolt.fill", "star.fill", "heart.fill", "flame.fill", "sparkles",
            "wand.and.stars", "checkmark.circle.fill", "play.fill", "arrow.clockwise", "power"
        ]),
        ("Apps & Web", [
            "safari.fill", "globe", "envelope.fill", "message.fill", "phone.fill",
            "video.fill", "music.note", "photo.fill", "book.fill", "newspaper.fill",
            "cart.fill", "creditcard.fill", "bag.fill", "gamecontroller.fill"
        ]),
        ("Devices", [
            "desktopcomputer", "laptopcomputer", "iphone", "ipad", "applewatch",
            "airpods", "homepod.fill", "tv.fill", "printer.fill", "externaldrive.fill",
            "server.rack", "terminal.fill", "keyboard", "display"
        ]),
        ("Home & Places", [
            "house.fill", "building.2.fill", "bed.double.fill", "sofa.fill",
            "lightbulb.fill", "lamp.desk.fill", "fan.fill", "thermometer.medium",
            "location.fill", "map.fill", "car.fill", "airplane", "tram.fill", "bicycle"
        ]),
        ("Time & Work", [
            "calendar", "clock.fill", "timer", "alarm.fill", "hourglass",
            "list.bullet", "checklist", "doc.fill", "folder.fill", "tray.fill",
            "paperclip", "chart.bar.fill", "briefcase.fill"
        ]),
        ("Media & Audio", [
            "speaker.wave.2.fill", "speaker.slash.fill", "mic.fill", "mic.slash.fill",
            "headphones", "camera.fill", "wave.3.right", "airplayaudio", "airplayvideo",
            "record.circle", "waveform"
        ]),
        ("System", [
            "wifi", "antenna.radiowaves.left.and.right", "bluetooth", "battery.100",
            "moon.fill", "sun.max.fill", "gear", "slider.horizontal.3", "lock.fill",
            "lock.open.fill", "eye.fill", "eye.slash.fill", "trash.fill", "arrow.down.circle.fill"
        ]),
        ("Health & Life", [
            "figure.walk", "figure.run", "dumbbell.fill", "drop.fill", "cup.and.saucer.fill",
            "fork.knife", "pills.fill", "bandage.fill", "leaf.fill", "pawprint.fill"
        ])
    ]

    static let all: [String] = groups.flatMap(\.symbols)

    static func search(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return all.filter { $0.contains(trimmed) }
    }
}
