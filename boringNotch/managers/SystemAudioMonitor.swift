//
//  SystemAudioMonitor.swift
//  boringNotch
//
//  Taps the system audio output and turns it into frequency band levels, so the
//  visualiser can react to what is actually playing rather than to a random
//  number generator.
//

import Accelerate
import AudioToolbox
import CoreAudio
import Defaults
import Foundation
import OSLog

@MainActor
final class SystemAudioMonitor: ObservableObject {
    static let shared = SystemAudioMonitor()

    enum Status: Equatable {
        case idle
        case running
        /// The OS refused the tap. Almost always the missing privacy grant.
        case denied
        /// The tap is running but every sample is zero. macOS hands out a
        /// working tap and silently zeroes it when the privacy grant is
        /// missing, so this is what an ungranted tap actually looks like.
        case silent
        /// Needs macOS 14.2 for the process-tap API.
        case unsupported
        case failed(String)
    }

    /// Normalised 0...1 magnitudes, low frequency first. Published at UI rate,
    /// not at audio rate.
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var status: Status = .idle

    /// Bands the UI can ask for. Five covers the widest visualiser style.
    nonisolated static let bandCount = 5

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    // Audio arrives on a realtime thread. It only memcpys into this buffer; the
    // FFT happens on a timer, because allocating or doing heavy work on that
    // thread is how you get audio glitches.
    private nonisolated static let fftSize = 1024

    private var fftSetup: FFTSetup?
    private var window = [Float](repeating: 0, count: fftSize)
    private var pollTimer: Timer?
    /// Rolling ceiling so quiet tracks still fill the bars; decays back so a
    /// single loud moment doesn't flatten everything after it.
    private var ceiling: Float = 0.02
    /// Tracks whether any real signal has ever arrived, so a permanently silent
    /// tap can be reported rather than sitting there looking healthy.
    private var everHadSignal = false
    private var startedAt: Date = .distantPast
    /// Smoothed band values. Raw FFT magnitudes jitter hard frame to frame;
    /// a fast attack and slow release is what makes a meter look like a meter
    /// rather than static.
    private var smoothed = [Float](repeating: 0, count: SystemAudioMonitor.bandCount)
    private static let attack: Float = 0.45
    private static let release: Float = 0.12
    /// Per-band ceilings, in dB. Each band is measured against its own history.
    private var bandCeilings = [Float](repeating: -120, count: SystemAudioMonitor.bandCount)
    /// How much louder each successive band is treated as, to offset the
    /// downward spectral slope of most music.
    private static let tiltPerBandDB: Float = 6
    /// dB window mapped onto the bar's full travel.
    private static let dynamicRangeDB: Float = 34
    /// How fast a band's ceiling falls back, in dB per frame at 25Hz.
    private static let ceilingDecayDB: Float = 0.35
    /// Ceilings never drop below this, so silence stays still.
    private static let floorGuardDB: Float = -66
    /// Below this overall level the bars are gated off.
    private static let gateDB: Float = -70

    /// The device's sample rate, read when the tap starts. Band edges are
    /// derived from frequency, not from bin indices — on this Mac the output
    /// runs at 96kHz, where blindly spanning to Nyquist put the top band at
    /// 13.7-47.9kHz, i.e. almost entirely empty spectrum.
    private var sampleRate: Double = 48_000
    /// Analysed range. Nothing musical lives above ~16kHz, and below ~40Hz is
    /// mostly rumble.
    private static let lowestHz: Double = 40
    private static let highestHz: Double = 16_000
    /// Decaying peak used to scale the oscilloscope trace.
    private var waveformPeak: Float = 0.05
    /// Previous trace, blended with the new one so the line eases between
    /// frames rather than snapping.
    private var previousWaveform: [CGFloat] = []

    /// Eases the trace toward the newest capture. Even with triggering, raw
    /// frame-to-frame changes read as jitter at this size.
    private func blendWaveform(_ incoming: [CGFloat]) -> [CGFloat] {
        guard !incoming.isEmpty else { return [] }
        guard previousWaveform.count == incoming.count else {
            previousWaveform = incoming
            return incoming
        }
        for index in incoming.indices {
            previousWaveform[index] += (incoming[index] - previousWaveform[index]) * 0.35
        }
        return previousWaveform
    }

    private let log = Logger(subsystem: "com.superboringnotch", category: "audio")

    private init() {
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(Self.fftSize))), FFTRadix(kFFTRadix2))
    }

    // MARK: - Lifecycle

    func start() {
        guard status != .running else { return }
        guard #available(macOS 14.2, *) else {
            status = .unsupported
            return
        }
        do {
            try createTap()
            try createAggregateDevice()
            sampleRate = aggregateSampleRate() ?? 48_000
            try startIO()
            startPolling()
            everHadSignal = false
            startedAt = Date()
            status = .running
        } catch {
            teardown()
            let message = (error as NSError).localizedDescription
            // A refused tap is overwhelmingly a missing privacy grant rather
            // than a genuine failure, and the two need different UI.
            status = message.contains("denied") || (error as NSError).code == kAudioHardwareIllegalOperationError
                ? .denied
                : .failed(message)
            log.error("system audio tap failed: \(message, privacy: .public)")
        }
    }

    func stop() {
        teardown()
        latestLevels = []
        latestWaveform = []
        smoothed = [Float](repeating: 0, count: Self.bandCount)
        bandCeilings = [Float](repeating: -120, count: Self.bandCount)
        previousWaveform = []
        waveformPeak = 0.05
        levels = []
        status = .idle
    }

    private func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil

        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        hasSamplesStorage = false
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Core Audio plumbing

    @available(macOS 14.2, *)
    private func createTap() throws {
        // Mono mixdown of everything: we only need magnitudes, and excluding no
        // processes means it follows whatever the user is actually listening to.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Super Boring Notch Visualiser"
        // Critical: the tap must not mute or alter what the user hears.
        description.muteBehavior = .unmuted
        description.isPrivate = true

        let result = AudioHardwareCreateProcessTap(description, &tapID)
        guard result == noErr, tapID != kAudioObjectUnknown else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }

    private func createAggregateDevice() throws {
        guard let outputUID = defaultOutputDeviceUID() else {
            throw NSError(domain: "SystemAudioMonitor", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "no default output device"])
        }
        let tapUUID = tapUUIDString() ?? UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SuperBoringNotch Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            // Private keeps it out of the user's Sound settings.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard result == noErr, aggregateID != kAudioObjectUnknown else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }

    private func startIO() throws {
        var procID: AudioDeviceIOProcID?
        let result = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
            [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        guard result == noErr, let procID else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        ioProcID = procID

        let startResult = AudioDeviceStart(aggregateID, procID)
        guard startResult == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(startResult))
        }
    }

    /// Runs on Core Audio's realtime thread. Copy only — no allocation, no
    /// locking beyond a spinlock, no Swift runtime work that could block.
    private nonisolated func consume(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = buffers.first,
              let raw = first.mData else { return }

        let available = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard available > 0 else { return }

        let samples = raw.assumingMemoryBound(to: Float.self)
        let count = min(available, Self.fftSize)

        withUnsafeMutablePointer(to: &self.bufferLockStorage) { lockPtr in
            os_unfair_lock_lock(lockPtr)
            self.sampleStorage.withUnsafeMutableBufferPointer { dest in
                if let base = dest.baseAddress {
                    // Keep the most recent window of samples.
                    base.update(from: samples, count: count)
                    if count < Self.fftSize {
                        (base + count).update(repeating: 0, count: Self.fftSize - count)
                    }
                }
            }
            self.hasSamplesStorage = true
            os_unfair_lock_unlock(lockPtr)
        }
    }

    // MARK: - Analysis

    private func startPolling() {
        // 25Hz is well above what the eye needs for a 16pt ornament and keeps
        // the FFT cost negligible.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.analyse() }
        }
    }

    private func analyse() {
        guard let fftSetup else { return }

        var samples = [Float](repeating: 0, count: Self.fftSize)
        var ready = false
        withUnsafeMutablePointer(to: &bufferLockStorage) { lockPtr in
            os_unfair_lock_lock(lockPtr)
            ready = hasSamplesStorage
            if ready { samples = sampleStorage }
            os_unfair_lock_unlock(lockPtr)
        }
        guard ready else { return }

        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(Self.fftSize))

        let half = Self.fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                samples.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { typed in
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Float(Self.fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Log-spaced bands: music energy is concentrated low, so linear bands
        // would leave the top ones permanently dead.
        var bands = [Float](repeating: 0, count: Self.bandCount)
        // Convert the analysis range into bins for this device's rate.
        let binHz = sampleRate / Double(Self.fftSize)
        let minBin = Swift.max(1, Int(Self.lowestHz / binHz))
        let maxBin = Swift.min(half - 1, Swift.max(minBin + Self.bandCount,
                                                   Int(Self.highestHz / binHz)))
        for band in 0 ..< Self.bandCount {
            let lo = Self.binIndex(for: band, of: Self.bandCount, min: minBin, max: maxBin)
            let hi = max(lo + 1, Self.binIndex(for: band + 1, of: Self.bandCount, min: minBin, max: maxBin))
            var sum: Float = 0
            vDSP_sve(Array(magnitudes[lo ..< min(hi, half)]), 1, &sum, vDSP_Length(min(hi, half) - lo))
            bands[band] = sum / Float(min(hi, half) - lo)
        }

        let peak = bands.max() ?? 0
        if peak > 0.00001 {
            everHadSignal = true
            if status == .silent { status = .running }
        } else if !everHadSignal,
                  status == .running,
                  Date().timeIntervalSince(startedAt) > 4,
                  MusicManager.shared.isPlaying {
            // Something is playing but the tap has produced nothing but zeros.
            status = .silent
        }

        // Everything below works in dB. Hearing is logarithmic, and linear
        // magnitudes made anything but the bass invisible.
        let gain = Float(Defaults[.visualizerSensitivity])
        var normalised = [Float](repeating: 0, count: Self.bandCount)

        for index in bands.indices {
            // Blend lightly with neighbours first — adjacent FFT bins are
            // correlated, so this removes twitch without dulling transients.
            let previous = bands[Swift.max(0, index - 1)]
            let next = bands[Swift.min(bands.count - 1, index + 1)]
            let blended = (previous + 2 * bands[index] + next) / 4

            var db = 20 * log10(Swift.max(blended, 1e-9))
            // Music slopes downward with frequency, so without a tilt the top
            // bands sit at the floor forever. Roughly +6dB per band, which is
            // about the pink-noise slope over two octaves.
            db += Float(index) * Self.tiltPerBandDB
            db += gain

            // Each band tracks its own ceiling. A single global ceiling was the
            // bug: it followed the bass, and every other band was measured
            // against a reference 20-40dB louder than anything it ever produces.
            bandCeilings[index] = Swift.max(db, bandCeilings[index] - Self.ceilingDecayDB)
            // Never let the ceiling fall so far that silence looks loud.
            bandCeilings[index] = Swift.max(bandCeilings[index], Self.floorGuardDB)

            let bottom = bandCeilings[index] - Self.dynamicRangeDB
            let value = (db - bottom) / Self.dynamicRangeDB
            normalised[index] = Swift.min(1, Swift.max(0, value))
        }

        // Global gate: if nothing is really playing, sit still rather than
        // amplifying the noise floor into a light show.
        let overallDB = 20 * log10(Swift.max(peak, 1e-9)) + gain
        let gate = Swift.min(1, Swift.max(0, (overallDB - Self.gateDB) / 10))

        for index in normalised.indices {
            let target = normalised[index] * gate
            let rate = target > smoothed[index] ? Self.attack : Self.release
            smoothed[index] += (target - smoothed[index]) * rate
        }

        let computed = smoothed.map { value -> CGFloat in
            CGFloat(Swift.min(1, Swift.max(0, value)))
        }
        levels = computed
        latestLevels = computed
        latestWaveform = blendWaveform(makeWaveform(samples))
    }

    private static func binIndex(for band: Int, of count: Int, min lo: Int, max hi: Int) -> Int {
        let fraction = Double(band) / Double(count)
        let value = Double(lo) * pow(Double(hi) / Double(lo), fraction)
        return Swift.min(hi, Swift.max(lo, Int(value)))
    }

    // MARK: - Device helpers

    /// Nominal rate of the aggregate we are reading from.
    private func aggregateSampleRate() -> Double? {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &rate) == noErr,
              rate > 0 else { return nil }
        return Double(rate)
    }

    private func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }

        var uid: Unmanaged<CFString>? = nil
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr else {
            return nil
        }
        return uid?.takeRetainedValue() as String?
    }

    private func tapUUIDString() -> String? {
        var uid: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    /// Snapshot for callers that run on the main thread but outside actor
    /// isolation, such as the AppKit visualiser view.
    private nonisolated(unsafe) var latestLevels: [CGFloat] = []
    private nonisolated(unsafe) var latestWaveform: [CGFloat] = []
    nonisolated func currentLevels() -> [CGFloat] { latestLevels }
    nonisolated func currentWaveform() -> [CGFloat] { latestWaveform }

    /// A stabilised oscilloscope trace, signed, in -1...1.
    ///
    /// Two things matter here. The samples must stay *signed* — an earlier
    /// version used `vDSP_maxmgv`, which returns absolute magnitude, so the
    /// trace could only ever go one way and, with a fixed 6x gain, sat
    /// saturated at the top. And the window must be *triggered*: each frame
    /// holds a fresh buffer captured at an arbitrary phase, so drawing it
    /// as-is makes the trace leap around. Starting at a rising zero crossing
    /// is what makes a real scope's trace sit still.
    private func makeWaveform(_ samples: [Float], points: Int = 32) -> [CGFloat] {
        guard samples.count >= points * 2 else { return [] }

        let searchLimit = samples.count / 2
        var trigger = 0
        for index in 1 ..< searchLimit where samples[index - 1] <= 0 && samples[index] > 0 {
            trigger = index
            break
        }

        let available = samples.count - trigger
        let stride = Swift.max(1, available / points)

        // Normalise against a decaying peak so the trace fills the height
        // without clipping, instead of a blind fixed gain.
        var peak: Float = 0
        vDSP_maxmgv(Array(samples[trigger...]), 1, &peak, vDSP_Length(available))
        waveformPeak = Swift.max(peak, waveformPeak * 0.92)
        let scale = Swift.max(waveformPeak, 0.02)

        var out = [CGFloat]()
        out.reserveCapacity(points)
        for index in 0 ..< points {
            let position = trigger + index * stride
            guard position < samples.count else { break }
            out.append(CGFloat(Swift.min(1, Swift.max(-1, samples[position] / scale))))
        }
        return out
    }

    nonisolated var isRunning: Bool { !latestLevels.isEmpty }

    // Storage reached from the realtime thread, kept outside actor isolation.
    private nonisolated(unsafe) var sampleStorage = [Float](repeating: 0, count: SystemAudioMonitor.fftSize)
    private nonisolated(unsafe) var hasSamplesStorage = false
    private nonisolated(unsafe) var bufferLockStorage = os_unfair_lock_s()
}
