//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    /// Draws the macOS "toggled on" treatment: a filled capsule behind the
    /// glyph, the way a selected toolbar button reads. Used instead of tinting
    /// the glyph — a coloured icon looks like a warning rather than a state,
    /// and it stops working for anyone who can't separate the two colours.
    var isActive: Bool = false
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;

    @State private var isHovering = false

    private var backgroundFill: Color {
        if isActive { return .white.opacity(isHovering ? 0.30 : 0.22) }
        return isHovering ? Color.gray.opacity(0.2) : .clear
    }

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(backgroundFill)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                // Active glyphs go full strength, inactive ones
                                // sit back, so the state reads even in greyscale.
                                .foregroundColor(iconColor)
                                .opacity(isActive ? 1 : 0.75)
                                .fontWeight(isActive ? .semibold : .regular)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .animation(.smooth(duration: 0.25), value: isActive)
    }
}
