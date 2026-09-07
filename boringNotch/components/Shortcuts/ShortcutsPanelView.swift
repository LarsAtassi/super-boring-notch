//
//  ShortcutsPanelView.swift
//  boringNotch
//
//  Grid of tiles in the opened notch that run Apple Shortcuts.
//

import Defaults
import SwiftUI

struct ShortcutsPanelView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.shortcutItems) var shortcutItems
    @Default(.closeNotchAfterShortcut) var closeAfterRun
    @Default(.shortcutTileHeight) var tileHeight

    /// Set while a shortcut is firing, purely so the tile can acknowledge the tap.
    @State private var firingID: UUID?

    var body: some View {
        Group {
            if shortcutItems.isEmpty {
                emptyState
            } else {
                // The tile size is solved against the real available area rather
                // than fixed, so the panel fills whatever space the grid cell and
                // the notch height give it instead of leaving a dead margin.
                GeometryReader { geo in
                    let solution = ShortcutGridLayout.solve(
                        count: shortcutItems.count,
                        size: geo.size,
                        spacing: NotchMetrics.tileSpacing,
                        preferredTile: tileHeight
                    )

                    if let solution {
                        if solution.scrolls {
                            // Too many tiles for the space at a legible size —
                            // scroll rather than overflow the panel.
                            ScrollView(.vertical, showsIndicators: false) {
                                tileGrid(solution)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        } else {
                            tileGrid(solution)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tileGrid(_ solution: ShortcutGridSolution) -> some View {
        let rows = stride(from: 0, to: shortcutItems.count, by: solution.columns).map { start in
            Array(shortcutItems[start..<min(start + solution.columns, shortcutItems.count)])
        }

        return VStack(alignment: .leading, spacing: NotchMetrics.tileSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: NotchMetrics.tileSpacing) {
                    ForEach(row) { item in
                        ShortcutTile(
                            item: item,
                            isFiring: firingID == item.id,
                            height: solution.tileHeight,
                            action: { run(item) }
                        )
                        .frame(width: solution.tileWidth)
                    }
                }
            }
        }
        .animation(NotchMetrics.layoutAnimation, value: solution)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tertiary)
            Text("No shortcuts")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add them in Settings")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    private func run(_ item: ShortcutItem) {
        firingID = item.id
        ShortcutsRunner.run(item)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            firingID = nil
            if closeAfterRun {
                vm.close()
            }
        }
    }
}

/// A tile modelled on the cards in Shortcuts.app: a tinted face, the glyph
/// top-left, the name bottom-left.
struct ShortcutTile: View {
    let item: ShortcutItem
    var isFiring: Bool = false
    var height: CGFloat = 62
    /// Previews in settings shouldn't react to the pointer.
    var isInteractive: Bool = true
    var action: () -> Void = {}

    @State private var isHovering = false

    private var base: Color { item.color }

    /// Outline tiles sit on a dark face, so their content takes the tint.
    private var contentColor: Color {
        item.style == .outline ? base : .white
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(contentColor)
                    .shadow(color: .black.opacity(item.style == .outline ? 0 : 0.25), radius: 1, y: 0.5)

                if item.showsLabel {
                    Spacer(minLength: 4)
                    Text(item.displayLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(contentColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.showsLabel ? .topLeading : .center)
            .frame(height: height)
            .background { face }
            .scaleEffect(isFiring ? 0.94 : (isHovering ? 1.03 : 1.0))
        }
        .buttonStyle(.plain)
        .help(item.displayLabel)
        .allowsHitTesting(isInteractive)
        .onHover { hovering in
            guard isInteractive else { return }
            withAnimation(NotchMetrics.hoverAnimation) { isHovering = hovering }
        }
        .animation(NotchMetrics.pressAnimation, value: isFiring)
    }

    @ViewBuilder
    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: NotchMetrics.tileRadius, style: .continuous)
        let lift = isHovering ? 1.0 : 0.0

        switch item.style {
        case .gradient:
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            base.opacity(0.92 + 0.08 * lift),
                            base.opacity(0.66 + 0.12 * lift)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay { topEdgeHighlight(shape) }
                .shadow(color: base.opacity(0.35 * lift), radius: 6, y: 2)

        case .filled:
            shape
                .fill(base.opacity(0.88 + 0.12 * lift))
                .overlay { topEdgeHighlight(shape) }
                .shadow(color: base.opacity(0.35 * lift), radius: 6, y: 2)

        case .glass:
            shape
                .fill(base.opacity(0.20 + 0.12 * lift))
                .overlay {
                    shape.strokeBorder(base.opacity(0.45 + 0.2 * lift), lineWidth: 0.8)
                }

        case .outline:
            shape
                .fill(Color.white.opacity(0.05 + 0.05 * lift))
                .overlay {
                    shape.strokeBorder(base.opacity(0.7 + 0.3 * lift), lineWidth: 1.2)
                }
        }
    }

    /// Hairline highlight along the top edge, the way Apple's tinted cards
    /// catch light.
    private func topEdgeHighlight(_ shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.8
        )
    }
}
