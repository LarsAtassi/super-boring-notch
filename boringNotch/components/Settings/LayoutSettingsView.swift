//
//  LayoutSettingsView.swift
//  boringNotch
//
//  Size of the opened notch, and which panels appear in it.
//

import Defaults
import SwiftUI

struct LayoutSettings: View {
    @Default(.openNotchWidth) var openWidth
    @Default(.openNotchHeight) var openHeight
    @Default(.notchPanelOrder) var panelOrder
    @Default(.notchGridColumns) var gridColumns
    @Default(.notchPanelSpans) private var panelSpans
    @Default(.notchPanelCards) private var panelCards

    // Panel toggles write through to their own Defaults keys, which SwiftUI does
    // not observe via `panelOrder`. This forces a redraw when one flips.
    @Default(.showMusicPanel) private var showMusic
    @Default(.showCalendar) private var showCalendar
    @Default(.showShortcutsPanel) private var showShortcuts
    @Default(.showMirror) private var showMirror

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(
                        value: $openWidth,
                        in: OpenNotchSizeLimits.widthRange,
                        step: 10
                    ) {
                        Text("Width — \(openWidth, specifier: "%.0f") pt")
                    }
                    .onChange(of: openWidth) { postSizeChange() }

                    Slider(
                        value: $openHeight,
                        in: OpenNotchSizeLimits.heightRange,
                        step: 5
                    ) {
                        Text("Height — \(openHeight, specifier: "%.0f") pt")
                    }
                    .onChange(of: openHeight) { postSizeChange() }
                }

                HStack {
                    Button("Reset to default") {
                        openWidth = OpenNotchSizeLimits.defaultWidth
                        openHeight = OpenNotchSizeLimits.defaultHeight
                        postSizeChange()
                    }
                    Spacer()
                    Button("Preview") {
                        NotchPreviewer.showNotch()
                    }
                }
            } header: {
                Text("Opened notch size")
            } footer: {
                Text("Applies to the notch when it is expanded. The closed notch keeps its real size, which is set under Appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Columns", selection: $gridColumns) {
                    ForEach(Array(NotchGrid.columnRange), id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)

                Defaults.Toggle(key: .notchPanelCards) {
                    Text("Show panels on cards")
                }

                GridPreview(
                    columns: gridColumns,
                    panels: enabledPanels,
                    spans: enabledPanels.map(\.span)
                )
                    .frame(height: 74)
                    .padding(.vertical, 4)
            } header: {
                Text("Grid")
            } footer: {
                Text("Panels fill the row in order and wrap onto the next row when they run out of columns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(panels.enumerated()), id: \.element.id) { index, panel in
                    HStack(spacing: 10) {
                        ReorderButtons(
                            canMoveUp: index > 0,
                            canMoveDown: index < panels.count - 1,
                            moveUp: { move(from: index, to: index - 1) },
                            moveDown: { move(from: index, to: index + 1) }
                        )

                        Image(systemName: panel.systemImage)
                            .frame(width: 20)
                            .foregroundStyle(panel.isEnabled ? Color.effectiveAccent : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(panel.title)
                            Text(panel.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: spanBinding(for: panel)) {
                            ForEach(Array(NotchGrid.spanRange), id: \.self) { span in
                                Text(span == 1 ? "1 col" : "\(span) cols").tag(span)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 88)
                        .disabled(!panel.isEnabled)

                        Toggle("", isOn: binding(for: panel))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Panels in the opened notch")
            } footer: {
                Text("Use the arrows to reorder. Width is set in grid columns. The mirror also needs a camera and the mirror button in the notch header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var panels: [NotchPanel] {
        NotchPanelLayout.orderedPanels
    }

    private var enabledPanels: [NotchPanel] {
        panels.filter(\.isEnabled)
    }

    private func binding(for panel: NotchPanel) -> Binding<Bool> {
        Binding(
            get: { panel.isEnabled },
            set: { panel.isEnabled = $0 }
        )
    }

    private func spanBinding(for panel: NotchPanel) -> Binding<Int> {
        Binding(
            get: { panel.span },
            set: { panel.span = $0 }
        )
    }

    private func move(from: Int, to: Int) {
        var order = panels
        guard order.indices.contains(from), order.indices.contains(to) else { return }
        order.swapAt(from, to)
        NotchPanelLayout.setOrder(order)
    }

    private func postSizeChange() {
        NotificationCenter.default.post(name: Notification.Name.openNotchSizeChanged, object: nil)
    }
}

/// Opens the notch so a size change can be seen straight away.
enum NotchPreviewer {
    @MainActor
    static func showNotch() {
        BoringViewCoordinator.shared.currentView = .home
        NotificationCenter.default.post(name: Notification.Name.previewOpenNotch, object: nil)
    }
}

extension Notification.Name {
    static let previewOpenNotch = Notification.Name("PreviewOpenNotch")
}

/// Miniature of the notch grid, so the effect of columns and spans is visible
/// without opening the notch.
private struct GridPreview: View {
    let columns: Int
    let panels: [NotchPanel]
    /// Passed in rather than read from each panel so that changing a span
    /// actually changes this view's inputs — otherwise SwiftUI sees identical
    /// stored properties and skips the update, and the preview goes stale.
    let spans: [Int]

    var body: some View {
        GeometryReader { geo in
            let rows = NotchGrid.packRows(spans: spans, columns: columns)
            let spacing: CGFloat = 4
            let cellWidth = max(1, (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let rowHeight = rows.isEmpty
                ? geo.size.height
                : max(1, (geo.size.height - spacing * CGFloat(rows.count - 1)) / CGFloat(rows.count))

            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.self) { index in
                            let panel = panels[index]
                            let span = min(spans[index], columns)
                            let width = cellWidth * CGFloat(span) + spacing * CGFloat(span - 1)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.effectiveAccent.opacity(0.22))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.effectiveAccent.opacity(0.45), lineWidth: 0.8)
                                }
                                .overlay {
                                    Image(systemName: panel.systemImage)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.effectiveAccent)
                                }
                                .frame(width: width, height: rowHeight)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if rows.isEmpty {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                        .foregroundStyle(.tertiary)
                        .overlay {
                            Text("No panels enabled")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
        }
    }
}
