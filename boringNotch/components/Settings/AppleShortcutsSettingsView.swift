//
//  AppleShortcutsSettingsView.swift
//  boringNotch
//
//  Manage the Apple Shortcuts exposed as buttons in the opened notch.
//

import Defaults
import SwiftUI

struct AppleShortcutsSettings: View {
    @Default(.shortcutItems) var items
    @Default(.showShortcutsPanel) var showPanel
    @Default(.closeNotchAfterShortcut) var closeAfterRun
    @Default(.shortcutTileHeight) var tileHeight

    @State private var editing: ShortcutItem?
    @State private var isAdding = false
    /// Populated only if the `shortcuts` CLI is reachable; under the sandbox it
    /// usually is not, so this stays empty and manual entry is the path.
    @State private var discovered: [String] = []
    @State private var didAttemptDiscovery = false

    private func rowButton(
        _ symbol: String,
        help: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        RowIconButton(symbol: symbol, help: help, isDestructive: isDestructive, action: action)
    }

    /// A copy of the item rendered without its label, for the small row preview.
    private func swatch(_ item: ShortcutItem) -> ShortcutItem {
        var copy = item
        copy.showsLabel = false
        return copy
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showShortcutsPanel) {
                    Text("Show shortcuts in the opened notch")
                }
                Defaults.Toggle(key: .closeNotchAfterShortcut) {
                    Text("Close the notch after running a shortcut")
                }
                LabeledContent("Tile size") {
                    HStack(spacing: 10) {
                        Slider(value: $tileHeight, in: 40...96)
                            .onChange(of: tileHeight) { _, value in
                                let snapped = (value / 2).rounded() * 2
                                if snapped != value { tileHeight = snapped }
                            }
                        Text("\(tileHeight, specifier: "%.0f") pt")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("Tiles stretch to fill the panel; this sets how big they aim to be, and so how many fit per row. Panel order is set under Layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if items.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No shortcuts added")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            ReorderButtons(
                                canMoveUp: index > 0,
                                canMoveDown: index < items.count - 1,
                                moveUp: { items.swapAt(index, index - 1) },
                                moveDown: { items.swapAt(index, index + 1) }
                            )

                            // Label suppressed: at 30pt the text has nowhere to go.
                            ShortcutTile(item: swatch(item), height: 30, isInteractive: false)
                                .frame(width: 38)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayLabel)
                                // Only worth a second line when the label and the
                                // shortcut's real name actually differ.
                                if item.displayLabel != item.name {
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            HStack(spacing: 2) {
                                rowButton("play.fill", help: "Run now") {
                                    ShortcutsRunner.run(item)
                                }
                                rowButton("pencil", help: "Edit") {
                                    editing = item
                                }
                                rowButton("trash", help: "Remove", isDestructive: true) {
                                    items.removeAll { $0.id == item.id }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add shortcut", systemImage: "plus")
                    }
                    Spacer()
                    Button("Open Shortcuts app") {
                        ShortcutsRunner.openShortcutsApp()
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("The name must match the shortcut exactly as it appears in Shortcuts.app. Use ▶︎ to run one and check it works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isAdding) {
            ShortcutEditor(
                item: ShortcutItem(name: ""),
                suggestions: discovered,
                title: "Add shortcut"
            ) { saved in
                items.append(saved)
            }
        }
        .sheet(item: $editing) { item in
            ShortcutEditor(
                item: item,
                suggestions: discovered,
                title: "Edit shortcut"
            ) { saved in
                if let index = items.firstIndex(where: { $0.id == saved.id }) {
                    items[index] = saved
                }
            }
        }
        .task {
            guard !didAttemptDiscovery else { return }
            didAttemptDiscovery = true
            let found = await Task.detached(priority: .utility) {
                ShortcutsRunner.installedShortcuts()
            }.value
            discovered = found
        }
    }
}


private struct ShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var item: ShortcutItem
    let suggestions: [String]
    let title: String
    let onSave: (ShortcutItem) -> Void

    @State private var symbolQuery = ""
    @State private var useCustomColor = false
    @State private var customColor: Color = .blue

    private var isValid: Bool {
        !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [String] {
        ShortcutSymbolLibrary.search(symbolQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameSection
                    styleSection
                    colorSection
                    symbolSection
                }
                .padding(20)
            }
            .frame(height: 420)

            Divider()

            footer
        }
        .frame(width: 480)
        .onAppear {
            if let hex = item.colorHex, let color = Color(hexOrNil: hex) {
                useCustomColor = true
                customColor = color
            }
        }
    }

    // MARK: Header — the live preview doubles as the title bar

    private var header: some View {
        HStack(spacing: 14) {
            ShortcutTile(item: item, height: 62, isInteractive: false)
                .frame(width: 78)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(item.name.isEmpty ? "Choose a shortcut" : item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(20)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Shortcut")
            TextField("Name in Shortcuts.app", text: $item.name)
                .textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                Picker("Installed", selection: $item.name) {
                    Text("—").tag("")
                    ForEach(suggestions, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("Label shown in the notch (optional)", text: $item.label)
                .textFieldStyle(.roundedBorder)
            Toggle("Show label on the tile", isOn: $item.showsLabel)
            Text(suggestions.isEmpty
                 ? "The name must match Shortcuts.app exactly. Use Test below to check it."
                 : "Pick an installed shortcut, or type a name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Style")
            HStack(spacing: 10) {
                ForEach(ShortcutTileStyle.allCases) { style in
                    let sample = previewItem(style: style)
                    VStack(spacing: 5) {
                        ShortcutTile(item: sample, height: 46, isInteractive: false)
                            .frame(width: 58)
                            .overlay {
                                RoundedRectangle(cornerRadius: NotchMetrics.tileRadius + 3, style: .continuous)
                                    .strokeBorder(
                                        item.style == style ? Color.effectiveAccent : .clear,
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            }
                        Text(style.title)
                            .font(.caption2)
                            .foregroundStyle(item.style == style ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { item.style = style }
                }
                Spacer()
            }
            // Tiles render on the notch's black face, so preview them that way.
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black))
        }
    }

    private func previewItem(style: ShortcutTileStyle) -> ShortcutItem {
        var copy = item
        copy.style = style
        copy.label = ""
        copy.name = "Aa"
        copy.showsLabel = false
        return copy
    }

    // MARK: Colour

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Colour")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], spacing: 8) {
                ForEach(ShortcutTint.allCases) { tint in
                    Circle()
                        .fill(tint.color)
                        .frame(height: 26)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
                        }
                        .overlay {
                            if !useCustomColor && item.tint == tint {
                                Circle()
                                    .strokeBorder(Color.effectiveAccent, lineWidth: 2)
                                    .padding(-3)
                            }
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            useCustomColor = false
                            item.colorHex = nil
                            item.tint = tint
                        }
                        .help(tint.title)
                }
            }

            HStack(spacing: 10) {
                Toggle("Custom colour", isOn: $useCustomColor)
                    .onChange(of: useCustomColor) { _, on in
                        item.colorHex = on ? customColor.hexString : nil
                    }
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!useCustomColor)
                    .onChange(of: customColor) { _, color in
                        if useCustomColor { item.colorHex = color.hexString }
                    }
                if useCustomColor, let hex = item.colorHex {
                    Text("#\(hex)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Symbol

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Icon")

            HStack {
                TextField("Search, or type any SF Symbol name", text: $symbolQuery)
                    .textFieldStyle(.roundedBorder)
                if !symbolQuery.isEmpty {
                    Button("Use") { item.symbol = symbolQuery }
                        .disabled(NSImage(systemSymbolName: symbolQuery, accessibilityDescription: nil) == nil)
                }
            }

            if !symbolQuery.isEmpty {
                if searchResults.isEmpty {
                    Text(NSImage(systemSymbolName: symbolQuery, accessibilityDescription: nil) == nil
                         ? "No match, and “\(symbolQuery)” isn't an SF Symbol on this Mac."
                         : "No match in the library, but “\(symbolQuery)” is a valid SF Symbol — press Use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    symbolGrid(searchResults)
                }
            } else {
                ForEach(ShortcutSymbolLibrary.groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        symbolGrid(group.symbols)
                    }
                }
            }
        }
    }

    private func symbolGrid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    item.symbol = symbol
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(item.symbol == symbol
                                  ? item.color.opacity(0.3)
                                  : Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(item.symbol == symbol ? item.color : .clear, lineWidth: 1.5)
                        Image(systemName: symbol)
                            .foregroundStyle(item.symbol == symbol ? item.color : .secondary)
                    }
                    .frame(height: 32)
                }
                .buttonStyle(.plain)
                .help(symbol)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .semibold))
    }

    private var footer: some View {
        HStack {
            Button("Test") { ShortcutsRunner.run(item) }
                .disabled(!isValid)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") {
                onSave(item)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding(20)
    }
}


/// Up/down reorder control. Used instead of drag-to-reorder because `.onMove`
/// has no effect on a `ForEach` inside a `Form` on macOS — the grip it would
/// need is there, but nothing picks up the drag.
struct ReorderButtons: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .opacity(canMoveUp ? 1 : 0.25)

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .opacity(canMoveDown ? 1 : 0.25)
        }
        .foregroundStyle(.secondary)
        .frame(width: 14)
    }
}

/// A trailing icon button for a settings list row. Stays quiet until hovered —
/// a permanently red trash is louder than the action warrants.
struct RowIconButton: View {
    let symbol: String
    let help: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(
            isHovering
                ? (isDestructive ? Color.red : Color.primary)
                : Color.secondary
        )
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
    }
}
