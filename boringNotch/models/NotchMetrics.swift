//
//  NotchMetrics.swift
//  boringNotch
//
//  Shared spacing, radii and motion, so the opened notch reads as one design
//  rather than a pile of independently-tuned views.
//

import SwiftUI

enum NotchMetrics {
    // MARK: Spacing — a 4pt rhythm

    static let tileSpacing: CGFloat = 8
    static let panelSpacing: CGFloat = 12
    static let panelPadding: CGFloat = 10

    // MARK: Radii
    // Concentric with the notch's own opened corner radius (19pt): a panel card
    // inset by `panelPadding` wants a proportionally smaller radius or the
    // corners look wrong nested inside each other.

    static let panelRadius: CGFloat = 13
    static let tileRadius: CGFloat = 11

    // MARK: Panel chrome

    static let panelFill = Color.white.opacity(0.055)
    static let panelStroke = Color.white.opacity(0.09)

    // MARK: Motion
    // Springs rather than eases: matches the notch's own open/close feel and
    // stays interruptible mid-flight.

    static let hoverAnimation: Animation = .spring(response: 0.25, dampingFraction: 0.8)
    static let pressAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.62)
    static let layoutAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.85)
}

/// The card treatment shared by every panel in the opened notch.
struct NotchPanelCard: ViewModifier {
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(NotchMetrics.panelPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: NotchMetrics.panelRadius, style: .continuous)
                        .fill(NotchMetrics.panelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: NotchMetrics.panelRadius, style: .continuous)
                                .strokeBorder(NotchMetrics.panelStroke, lineWidth: 0.8)
                        }
                }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    func notchPanelCard(_ isEnabled: Bool = true) -> some View {
        modifier(NotchPanelCard(isEnabled: isEnabled))
    }
}
