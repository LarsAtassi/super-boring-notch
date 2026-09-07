//
//  WelcomeView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI
import SwiftUIIntrospect

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil

    /// What the app actually does, in the order the panels appear in the notch.
    private let highlights: [(symbol: String, title: String, detail: String)] = [
        ("play.circle", "Media", "Album art, controls and a live activity for whatever is playing"),
        ("square.stack.3d.up", "Shortcuts", "Run your Apple Shortcuts straight from the notch"),
        ("calendar", "Calendar", "Your next events without leaving what you're doing"),
        ("tray.full", "Shelf", "Drag files onto the notch to carry them between apps")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Image("spotlight")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.bottom)
                    .blur(radius: 3)
                    .offset(y: -5)
                    .background(SparkleView().opacity(0.6))

                VStack(spacing: 0) {
                    // The real app icon, not a bundled logo image, so this can
                    // never drift from whatever the app is actually shipping.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 10)

                    Text(AppInfo.name)
                        .font(.system(.largeTitle, design: .default))
                        .fontWeight(.semibold)

                    Text("Your notch, put to work")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 26)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(highlights, id: \.title) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.effectiveAccent)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(.body, weight: .semibold))
                                    Text(item.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 380, alignment: .leading)
                    .padding(.bottom, 30)

                    Button {
                        onGetStarted?()
                    } label: {
                        Text("Get started")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())

                    Text("The next few screens ask for the permissions each feature needs. You can skip any of them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .padding(.top, 12)
                }
                .padding(.top)
            }

            // Upstream's team logo used to sit here. Credit belongs in About,
            // and putting someone else's mark on this app's welcome screen
            // misrepresents who made it.
            Text("Version \(AppInfo.version) · based on \(AppInfo.upstreamName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding()
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    WelcomeView()
}
