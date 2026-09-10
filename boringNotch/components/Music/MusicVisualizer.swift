//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import Defaults
import SwiftUI

/// Shapes the live-activity animation can take.
enum VisualizerStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    /// Four bars at random heights — upstream's original.
    case bars
    /// Symmetric bars growing from the centre outwards.
    case levels
    /// A sine wave travelling across the bars.
    case wave
    /// A single dot breathing in and out.
    case pulse
    /// Three dots bouncing in sequence.
    case bounce
    /// Classic equaliser: bars rooted at the bottom rather than the centre.
    case equalizer
    /// Segmented LED meter, like a rack VU.
    case ladder
    /// The signal itself, drawn as an oscilloscope trace.
    case waveform
    /// A ring that breathes with the overall level.
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .levels: return "Levels"
        case .wave: return "Wave"
        case .pulse: return "Pulse"
        case .bounce: return "Bounce"
        case .equalizer: return "Equaliser"
        case .ladder: return "Ladder"
        case .waveform: return "Waveform"
        case .ring: return "Ring"
        }
    }

    var elementCount: Int {
        switch self {
        case .bars: return 4
        case .levels, .wave: return 5
        case .pulse: return 1
        case .bounce: return 3
        case .equalizer: return 5
        case .ladder: return 4
        case .waveform, .ring: return 1
        }
    }

    /// Dots are round and squat; bars are tall and thin.
    var isDotStyle: Bool {
        self == .pulse || self == .bounce
    }

    /// Bars rooted at the bottom instead of growing from the centre.
    var isBottomAnchored: Bool {
        self == .equalizer || self == .ladder
    }

    /// Styles that draw their own path each frame rather than scaling layers.
    var isPathStyle: Bool {
        self == .waveform || self == .ring
    }

    /// Segments per column, for the LED-style meter.
    var segmentCount: Int { self == .ladder ? 5 : 1 }

    /// Seconds between animation steps.
    var tickInterval: TimeInterval {
        switch self {
        case .bars: return 0.3
        case .levels: return 0.28
        case .wave: return 0.14
        case .pulse: return 0.5
        case .bounce: return 0.18
        case .equalizer: return 0.22
        case .ladder: return 0.2
        case .waveform: return 0.06
        case .ring: return 0.3
        }
    }
}

extension Defaults.Keys {
    static let visualizerStyle = Key<VisualizerStyle>("visualizerStyle", default: .bars)
    /// Drive the animation from the actual system audio rather than from a
    /// random number generator. Off by default: switching it on asks macOS for
    /// permission to record system audio.
    static let reactiveVisualizer = Key<Bool>("reactiveVisualizer", default: false)
    /// Extra gain in dB applied before normalisation. Lets quiet sources be
    /// dialled up without rebuilding.
    static let visualizerSensitivity = Key<Double>("visualizerSensitivity", default: 0)
}

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    /// Advances every tick; drives the travelling wave and the bounce sequence.
    private var phase: CGFloat = 0
    /// When the canned animation last advanced, so it keeps its own cadence
    /// even while the faster audio-reactive timer is driving `step()`.
    private var lastCannedStep: CFTimeInterval = 0

    /// The bars mask a gradient layer rather than being drawn as flat shapes,
    /// and both live in Core Animation. Previously the caller masked a SwiftUI
    /// gradient with this view, which made SwiftUI re-rasterise the mask on
    /// every animation frame — that cost ~13% CPU for the whole app while music
    /// played. Keeping the mask inside the layer tree keeps it on the GPU.
    private let gradientLayer = CAGradientLayer()
    private let barsContainer = CALayer()

    private static let designSize = CGSize(width: 16, height: 14)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        rebuild()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        rebuild()
    }

    var style: VisualizerStyle = .bars {
        didSet {
            guard style != oldValue else { return }
            rebuild()
            if isPlaying { restartAnimating() }
        }
    }

    /// Colour the bars take. Set from the album art's average colour.
    var tint: NSColor = .white {
        didSet { applyTint() }
    }

    private func rebuild() {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        barScales.removeAll()
        phase = 0

        let size = Self.designSize
        frame.size = size

        if style.isPathStyle {
            // One layer whose path is redrawn each frame.
            let layer = CAShapeLayer()
            layer.frame = CGRect(origin: .zero, size: size)
            layer.fillColor = NSColor.clear.cgColor
            layer.strokeColor = NSColor.white.cgColor
            layer.lineWidth = style == .ring ? 2 : 1.4
            layer.lineCap = .round
            layer.lineJoin = .round
            barLayers.append(layer)
            barScales.append(0)
            barsContainer.addSublayer(layer)
        } else {
            let columns = style.elementCount
            let segments = style.segmentCount
            let elementWidth: CGFloat = style.isDotStyle
                ? min(4, size.width / CGFloat(columns) - 1)
                : (style == .ladder ? 2.6 : 2)
            let spacing = columns > 1
                ? (size.width - CGFloat(columns) * elementWidth) / CGFloat(columns - 1)
                : 0
            let startX = columns > 1 ? 0 : (size.width - elementWidth) / 2

            for column in 0 ..< columns {
                let x = startX + CGFloat(column) * (elementWidth + spacing)

                for segment in 0 ..< segments {
                    let layer = CAShapeLayer()
                    let segmentHeight: CGFloat = {
                        if style.isDotStyle { return elementWidth }
                        if segments > 1 {
                            // Leave a gap between LED segments.
                            return (size.height - CGFloat(segments - 1) * 1.2) / CGFloat(segments)
                        }
                        return size.height
                    }()
                    let y: CGFloat = {
                        if segments > 1 { return CGFloat(segment) * (segmentHeight + 1.2) }
                        if style.isBottomAnchored { return 0 }
                        return (size.height - segmentHeight) / 2
                    }()

                    let rect = CGRect(x: 0, y: 0, width: elementWidth, height: segmentHeight)
                    layer.frame = CGRect(x: x, y: y, width: elementWidth, height: segmentHeight)
                    // Bottom-anchored styles scale up from their base; the rest
                    // grow symmetrically about the middle.
                    let anchorY: CGFloat = (style.isBottomAnchored && segments == 1) ? 0 : 0.5
                    layer.anchorPoint = CGPoint(x: 0.5, y: anchorY)
                    layer.position = CGPoint(x: x + elementWidth / 2,
                                             y: y + segmentHeight * anchorY)
                    layer.fillColor = NSColor.white.cgColor
                    layer.masksToBounds = true
                    layer.path = NSBezierPath(
                        roundedRect: rect,
                        xRadius: elementWidth / 2,
                        yRadius: style.isDotStyle ? segmentHeight / 2 : min(elementWidth, segmentHeight) / 2
                    ).cgPath
                    barLayers.append(layer)
                    barScales.append(style.isDotStyle ? 1.0 : 0.35)
                    barsContainer.addSublayer(layer)
                }
            }
        }

        barsContainer.frame = CGRect(origin: .zero, size: size)
        gradientLayer.frame = CGRect(origin: .zero, size: size)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.mask = barsContainer
        if gradientLayer.superlayer == nil {
            layer?.addSublayer(gradientLayer)
        }
        applyTint()
        resetBars()
    }

    private func applyTint() {
        guard let base = tint.usingColorSpace(.sRGB) else { return }
        let top = base.blended(withFraction: 0.25, of: .white) ?? base
        // Colour changes shouldn't animate implicitly; that would add work on
        // every album change for no visual benefit.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = [top.cgColor, base.cgColor]
        CATransaction.commit()
    }

    private func restartAnimating() {
        stopAnimating()
        startAnimating()
    }

    private var isReactive: Bool {
        Defaults[.reactiveVisualizer] && SystemAudioMonitor.shared.isRunning
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        // Audio-reactive needs UI-rate updates; the canned animations are
        // deliberately lazier.
        let interval = Defaults[.reactiveVisualizer] ? 1.0 / 25.0 : style.tickInterval
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.step()
        }
        step()
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func step() {
        if isReactive, stepFromAudio() { return }

        // Falling back to a canned animation. The reactive timer ticks at
        // 25Hz, far faster than these animations run, and driving them at
        // that rate restarts each one before it finishes. Let them keep their
        // own pace instead.
        let now = CACurrentMediaTime()
        guard now - lastCannedStep >= style.tickInterval - 0.005 else { return }
        lastCannedStep = now

        phase += 1

        let duration = style.tickInterval

        switch style {
        case .bars:
            for (index, layer) in barLayers.enumerated() {
                animateScaleY(layer, from: barScales[index],
                              to: setScale(index, .random(in: 0.35 ... 1.0)),
                              duration: duration, autoreverses: true)
            }

        case .levels:
            // Symmetric about the centre, so it reads as a level meter.
            let half = (barLayers.count + 1) / 2
            var targets = (0 ..< half).map { _ in CGFloat.random(in: 0.35 ... 1.0) }
            targets += targets.reversed().dropFirst(barLayers.count % 2 == 0 ? 0 : 1)
            for (index, layer) in barLayers.enumerated() where index < targets.count {
                animateScaleY(layer, from: barScales[index],
                              to: setScale(index, targets[index]),
                              duration: duration, autoreverses: false)
            }

        case .wave:
            for (index, layer) in barLayers.enumerated() {
                let angle = (phase + CGFloat(index)) * 0.9
                let target = 0.35 + 0.65 * (sin(angle) + 1) / 2
                animateScaleY(layer, from: barScales[index],
                              to: setScale(index, target),
                              duration: duration, autoreverses: false)
            }

        case .pulse:
            guard let layer = barLayers.first else { return }
            let target: CGFloat = barScales[0] > 0.75 ? 0.55 : 1.0
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = barScales[0]
            animation.toValue = setScale(0, target)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            applyFrameRateCap(animation)
            layer.add(animation, forKey: "pulse")

        case .equalizer, .ladder:
            for (index, layer) in barLayers.enumerated() {
                animateScaleY(layer, from: barScales[index],
                              to: setScale(index, .random(in: 0.25 ... 1.0)),
                              duration: duration, autoreverses: false)
            }

        case .waveform:
            // Without audio there is no signal to draw, so trace a travelling
            // sine instead of pretending to show one.
            drawWaveform((0 ..< 24).map { i in
                0.5 + 0.5 * sin((phase * 0.35) + Double(i) * 0.5)
            })

        case .ring:
            guard let layer = barLayers.first else { return }
            let target: CGFloat = barScales[0] > 0.75 ? 0.6 : 1.0
            drawRing(level: setScale(0, target), duration: duration)

        case .bounce:
            let active = Int(phase) % max(1, barLayers.count)
            for (index, layer) in barLayers.enumerated() {
                let lift: CGFloat = index == active ? 3.5 : 0
                let animation = CABasicAnimation(keyPath: "transform.translation.y")
                animation.toValue = lift
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                applyFrameRateCap(animation)
                layer.add(animation, forKey: "bounce")
            }
        }
    }

    /// Maps the analyser's bands onto whatever elements this style has.
    /// Returns false when there is nothing to show, so the caller can fall back.
    private func stepFromAudio() -> Bool {
        let levels = SystemAudioMonitor.shared.currentLevels()
        guard !levels.isEmpty, !barLayers.isEmpty else { return false }

        let duration = 1.0 / 25.0

        if style == .waveform {
            let wave = SystemAudioMonitor.shared.currentWaveform()
            guard !wave.isEmpty else { return false }
            // Signed -1...1 mapped onto the canvas with 0 at the middle.
            drawWaveform(wave.map { 0.5 + 0.45 * $0 })
            return true
        }

        if style == .ring {
            let overall = levels.reduce(0, +) / CGFloat(levels.count)
            drawRing(level: 0.55 + 0.45 * overall, duration: duration)
            return true
        }

        if style == .ladder {
            // Segments light up to the level, like a rack meter.
            let segments = style.segmentCount
            let columns = max(1, barLayers.count / segments)
            for column in 0 ..< columns {
                let position = columns == 1 ? 0.0 : Double(column) / Double(columns - 1)
                let bandIndex = Int((position * Double(levels.count - 1)).rounded())
                let level = levels[min(max(0, bandIndex), levels.count - 1)]
                let lit = Int((level * CGFloat(segments)).rounded())
                for segment in 0 ..< segments {
                    let layerIndex = column * segments + segment
                    guard layerIndex < barLayers.count else { continue }
                    // Segment 0 is the top of the column, so count from the end.
                    let isLit = (segments - 1 - segment) < lit
                    let layer = barLayers[layerIndex]
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.toValue = isLit ? 1.0 : 0.12
                    animation.duration = duration
                    animation.fillMode = .forwards
                    animation.isRemovedOnCompletion = false
                    applyFrameRateCap(animation)
                    layer.add(animation, forKey: "lit")
                }
            }
            return true
        }

        for (index, layer) in barLayers.enumerated() {
            // Spread the available bands across however many bars the style has.
            let position = barLayers.count == 1
                ? 0.0
                : Double(index) / Double(barLayers.count - 1)
            let bandIndex = Int((position * Double(levels.count - 1)).rounded())
            let level = levels[min(max(0, bandIndex), levels.count - 1)]

            if style.isDotStyle {
                let target = 0.6 + 0.4 * level
                let animation = CABasicAnimation(keyPath: "transform.scale")
                animation.fromValue = barScales[index]
                animation.toValue = setScale(index, target)
                animation.duration = duration
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                applyFrameRateCap(animation)
                layer.add(animation, forKey: "pulse")
            } else {
                animateScaleY(layer, from: barScales[index],
                              to: setScale(index, 0.18 + 0.82 * level),
                              duration: duration, autoreverses: false)
            }
        }
        return true
    }

    /// Draws the oscilloscope trace. `points` are 0...1 with 0.5 as the centre.
    private func drawWaveform(_ points: [CGFloat]) {
        guard let layer = barLayers.first, points.count > 1 else { return }
        let size = Self.designSize
        let path = CGMutablePath()
        let step = size.width / CGFloat(points.count - 1)
        for (index, value) in points.enumerated() {
            let x = CGFloat(index) * step
            let y = min(max(value, 0), 1) * size.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = path
        CATransaction.commit()
    }

    /// A ring whose radius and stroke weight follow the overall level.
    private func drawRing(level: CGFloat, duration: TimeInterval) {
        guard let layer = barLayers.first else { return }
        let size = Self.designSize
        let maxRadius = min(size.width, size.height) / 2 - 1
        let radius = max(1.5, maxRadius * min(max(level, 0), 1))
        let rect = CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                          width: radius * 2, height: radius * 2)
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        layer.path = CGPath(ellipseIn: rect, transform: nil)
        layer.lineWidth = 1.2 + 1.4 * min(max(level, 0), 1)
        CATransaction.commit()
    }

    private func setScale(_ index: Int, _ value: CGFloat) -> CGFloat {
        barScales[index] = value
        return value
    }

    private func animateScaleY(
        _ layer: CAShapeLayer,
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval,
        autoreverses: Bool
    ) {
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = autoreverses
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        applyFrameRateCap(animation)
        layer.add(animation, forKey: "scaleY")
    }

    /// 24fps is plenty for a 16pt-wide ornament and keeps it off the high-power
    /// display refresh path.
    private func applyFrameRateCap(_ animation: CAAnimation) {
        if #available(macOS 13.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
        }
    }

    private func resetBars() {
        guard !style.isPathStyle else { return }
        for (index, layer) in barLayers.enumerated() {
            layer.removeAllAnimations()
            if style.isDotStyle {
                layer.transform = CATransform3DIdentity
                barScales[index] = 1.0
            } else {
                layer.transform = CATransform3DMakeScale(1, 0.35, 1)
                barScales[index] = 0.35
            }
        }
    }

    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying || (playing && animationTimer == nil) else { return }
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    var tint: Color = .white
    var style: VisualizerStyle = .bars

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.style = style
        spectrum.tint = NSColor(tint)
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.style = style
        let newTint = NSColor(tint)
        if nsView.tint != newTint { nsView.tint = newTint }
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
