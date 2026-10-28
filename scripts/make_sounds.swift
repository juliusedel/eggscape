#!/usr/bin/env swift
// Synthesizes all of Eggscape's sound effects into .caf files (16-bit PCM, 44.1 kHz, mono).
// Everything is generated from code with a fixed seed, so the output is reproducible and needs no third-party audio.
//
// usage: swift scripts/make_sounds.swift App/Resources/Sounds

import AVFoundation
import Foundation

let sampleRate = 44100.0

// MARK: - Building blocks

/// Deterministic white noise (SplitMix64).
struct Noise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * 0x1.0p-53 * 2 - 1
    }
}

/// RBJ biquad filter.
struct Biquad {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    enum Kind {
        case lowPass, highPass, bandPass
    }

    init(_ kind: Kind, frequency: Double, q: Double = 0.707) {
        set(kind, frequency: frequency, q: q)
    }

    mutating func set(_ kind: Kind, frequency: Double, q: Double) {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0: Double
        switch kind {
        case .lowPass:
            b0 = (1 - cosW0) / 2
            b1 = 1 - cosW0
            b2 = (1 - cosW0) / 2
        case .highPass:
            b0 = (1 + cosW0) / 2
            b1 = -(1 + cosW0)
            b2 = (1 + cosW0) / 2
        case .bandPass:
            b0 = alpha
            b1 = 0
            b2 = -alpha
        }
        a0 = 1 + alpha
        a1 = -2 * cosW0 / a0
        a2 = (1 - alpha) / a0
        b0 /= a0
        b1 /= a0
        b2 /= a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

func samples(_ seconds: Double) -> Int {
    Int(seconds * sampleRate)
}

/// Exponential decay envelope with a short linear attack.
func envelope(_ t: Double, attack: Double = 0.002, decay: Double) -> Double {
    t < attack ? t / attack : exp(-(t - attack) / decay)
}

func tone(_ t: Double, frequency: Double) -> Double {
    sin(2 * Double.pi * frequency * t)
}

/// A soft bell: fundamental plus decaying partials.
func bell(_ t: Double, frequency: Double, decay: Double) -> Double {
    let partials: [(Double, Double, Double)] = [(1, 1, 1), (2.01, 0.35, 0.6), (3.02, 0.15, 0.35), (4.2, 0.06, 0.2)]
    return partials.reduce(0) { sum, partial in
        sum + partial.1 * tone(t, frequency: frequency * partial.0) * envelope(
            t,
            attack: 0.003,
            decay: decay * partial.2
        )
    }
}

func normalize(_ buffer: [Double], peak: Double) -> [Double] {
    let maximum = buffer.map(abs).max() ?? 0
    guard maximum > 0 else { return buffer }
    return buffer.map { $0 / maximum * peak }
}

/// Short fades at both ends so no sound starts or stops with a click.
func faded(_ buffer: [Double], fadeIn: Double = 0.002, fadeOut: Double = 0.01) -> [Double] {
    var output = buffer
    let inCount = min(samples(fadeIn), output.count)
    let outCount = min(samples(fadeOut), output.count)
    for index in 0 ..< inCount {
        output[index] *= Double(index) / Double(max(inCount, 1))
    }
    for index in 0 ..< outCount {
        output[output.count - 1 - index] *= Double(index) / Double(max(outCount, 1))
    }
    return output
}

/// Makes a buffer loop seamlessly by cross-fading its tail into its head.
func looped(_ buffer: [Double], crossfade: Double) -> [Double] {
    let fade = samples(crossfade)
    let body = Array(buffer[0 ..< (buffer.count - fade)])
    var output = body
    for index in 0 ..< fade {
        let mix = Double(index) / Double(fade)
        output[index] = body[index] * mix + buffer[buffer.count - fade + index] * (1 - mix)
    }
    return output
}

// MARK: - Sounds

func footstep() -> [Double] {
    var noise = Noise(seed: 11)
    var crunch = Biquad(.lowPass, frequency: 1400)
    return (0 ..< samples(0.14)).map { index in
        let t = Double(index) / sampleRate
        let thump = tone(t, frequency: 75 - 35 * min(t / 0.06, 1)) * envelope(t, attack: 0.003, decay: 0.03)
        let grit = crunch.process(noise.next()) * envelope(t, attack: 0.001, decay: 0.035)
        return thump * 0.9 + grit * 0.45
    }
}

func crack() -> [Double] {
    var noise = Noise(seed: 21)
    var highPass = Biquad(.highPass, frequency: 2200)
    var ring = Biquad(.bandPass, frequency: 3800, q: 9)
    let clicks: [(Double, Double)] = [(0, 1), (0.018, 0.7), (0.031, 0.85), (0.058, 0.5), (0.09, 0.35), (0.13, 0.2)]
    return (0 ..< samples(0.35)).map { index in
        let t = Double(index) / sampleRate
        let burst = clicks.reduce(0.0) { sum, click in
            t >= click.0 ? sum + click.1 * envelope(t - click.0, attack: 0.0004, decay: 0.006) : sum
        }
        let raw = noise.next() * burst
        return highPass.process(raw) + ring.process(raw) * 0.6
    }
}

func splat() -> [Double] {
    var noise = Noise(seed: 31)
    var lowPass = Biquad(.lowPass, frequency: 900)
    var bubbles = Noise(seed: 32)
    var bubbleStarts: [Double] = []
    for _ in 0 ..< 6 {
        bubbleStarts.append(0.05 + (bubbles.next() + 1) * 0.12)
    }
    return (0 ..< samples(0.5)).map { index in
        let t = Double(index) / sampleRate
        let wet = lowPass.process(noise.next()) * envelope(t, attack: 0.004, decay: 0.09)
        let blop = tone(t, frequency: 320 * exp(-t * 9) + 70) * envelope(t, attack: 0.003, decay: 0.07)
        let pops = bubbleStarts.enumerated().reduce(0.0) { sum, item in
            let local = t - item.element
            guard local >= 0 else { return sum }
            let frequency = 900 + Double(item.offset) * 230
            return sum + tone(local, frequency: frequency * (1 + local * 6)) * envelope(
                local,
                attack: 0.001,
                decay: 0.012
            ) * 0.25
        }
        return wet * 1.2 + blop * 0.8 + pops
    }
}

func plop() -> [Double] {
    (0 ..< samples(0.22)).map { index in
        let t = Double(index) / sampleRate
        let pitch = 560 * (1 - 0.15 * min(t / 0.05, 1))
        return (tone(t, frequency: pitch) + 0.3 * tone(t, frequency: pitch * 2.02)) * envelope(
            t,
            attack: 0.002,
            decay: 0.045
        )
    }
}

func beep(frequency: Double, length: Double) -> [Double] {
    (0 ..< samples(length)).map { index in
        let t = Double(index) / sampleRate
        let body = tone(t, frequency: frequency) + 0.25 * tone(t, frequency: frequency * 2) + 0.1 * tone(
            t,
            frequency: frequency * 3
        )
        return body * envelope(t, attack: 0.005, decay: length * 0.45)
    }
}

func arpeggio(_ notes: [Double], step: Double, decay: Double, length: Double) -> [Double] {
    (0 ..< samples(length)).map { index in
        let t = Double(index) / sampleRate
        return notes.enumerated().reduce(0.0) { sum, note in
            let local = t - Double(note.offset) * step
            return local >= 0 ? sum + bell(local, frequency: note.element, decay: decay) : sum
        }
    }
}

func fail() -> [Double] {
    let notes = [392.0, 329.6, 261.6]
    return (0 ..< samples(1.1)).map { index in
        let t = Double(index) / sampleRate
        return notes.enumerated().reduce(0.0) { sum, note in
            let local = t - Double(note.offset) * 0.22
            guard local >= 0 else { return sum }
            let wobble = 1 + 0.012 * sin(2 * Double.pi * 5.5 * local)
            let voice = tone(local, frequency: note.element * wobble) + 0.4 * tone(
                local,
                frequency: note.element * 2 * wobble
            )
            return sum + voice * envelope(local, attack: 0.01, decay: note.offset == notes.count - 1 ? 0.35 : 0.16)
        }
    }
}

func splash() -> [Double] {
    var noise = Noise(seed: 41)
    var band = Biquad(.bandPass, frequency: 1800, q: 0.8)
    var drops = Noise(seed: 42)
    var dropStarts: [(Double, Double)] = []
    for _ in 0 ..< 10 {
        dropStarts.append((0.03 + (drops.next() + 1) * 0.2, 1400 + (drops.next() + 1) * 1200))
    }
    return (0 ..< samples(0.55)).map { index in
        let t = Double(index) / sampleRate
        let rush = band.process(noise.next()) * envelope(t, attack: 0.008, decay: 0.12)
        let droplets = dropStarts.reduce(0.0) { sum, drop in
            let local = t - drop.0
            guard local >= 0 else { return sum }
            return sum + tone(local, frequency: drop.1 * (1 + local * 4)) * envelope(
                local,
                attack: 0.0005,
                decay: 0.01
            ) * 0.3
        }
        return rush * 1.4 + droplets
    }
}

func thunder() -> [Double] {
    var noise = Noise(seed: 51)
    var brown = 0.0
    var rumbleFilter = Biquad(.lowPass, frequency: 180, q: 0.6)
    var crackFilter = Biquad(.lowPass, frequency: 3200)
    var modulation = Noise(seed: 52)
    var modulator = 0.0
    var modulatorFilter = Biquad(.lowPass, frequency: 6)
    return (0 ..< samples(3)).map { index in
        let t = Double(index) / sampleRate
        let white = noise.next()
        brown = (brown + white * 0.02) * 0.998
        modulator = modulatorFilter.process(modulation.next())
        let rumble = rumbleFilter.process(brown) * (0.6 + 2.5 * abs(modulator)) * envelope(t, attack: 0.15, decay: 0.9)
        let crackle = crackFilter.process(white) * envelope(t, attack: 0.002, decay: 0.08)
        return rumble * 6 + crackle * 0.5
    }
}

func rainLoop() -> [Double] {
    var noise = Noise(seed: 61)
    var highPass = Biquad(.highPass, frequency: 500)
    var lowPass = Biquad(.lowPass, frequency: 6000)
    var drops = Noise(seed: 62)
    let length = 4.5
    var dropTimes: [(Double, Double)] = []
    var cursor = 0.0
    while cursor < length {
        cursor += 0.01 + (drops.next() + 1) * 0.03
        dropTimes.append((cursor, 2500 + (drops.next() + 1) * 2500))
    }
    var withDrops = (0 ..< samples(length)).map { _ in
        lowPass.process(highPass.process(noise.next())) * 0.35
    }
    for drop in dropTimes {
        let start = samples(drop.0)
        for offset in 0 ..< samples(0.006) where start + offset < withDrops.count {
            let local = Double(offset) / sampleRate
            withDrops[start + offset] += tone(local, frequency: drop.1) * envelope(
                local,
                attack: 0.0003,
                decay: 0.0015
            ) * 0.25
        }
    }
    return looped(withDrops, crossfade: 0.5)
}

func windLoop() -> [Double] {
    var noise = Noise(seed: 71)
    var band = Biquad(.bandPass, frequency: 500, q: 1.4)
    let length = 5.0
    let raw = (0 ..< samples(length)).map { index in
        let t = Double(index) / sampleRate
        let sweep = 420 + 260 * sin(2 * Double.pi * t / length) + 90 * sin(2 * Double.pi * 3 * t / length)
        if index % 64 == 0 {
            band.set(.bandPass, frequency: sweep, q: 1.4)
        }
        let swell = 0.55 + 0.45 * sin(2 * Double.pi * 2 * t / length)
        return band.process(noise.next()) * swell
    }
    return looped(raw, crossfade: 0.6)
}

func coin() -> [Double] {
    (0 ..< samples(0.45)).map { index in
        let t = Double(index) / sampleRate
        let first = t < 0.07 ? bell(t, frequency: 988, decay: 0.05) : 0
        let second = t >= 0.07 ? bell(t - 0.07, frequency: 1319, decay: 0.16) : 0
        return first + second
    }
}

// MARK: - Output

func write(_ buffer: [Double], name: String, to directory: URL, peak: Double = 0.85) throws {
    let url = directory.appendingPathComponent("\(name).caf")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)),
          let channel = pcm.floatChannelData?[0]
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    let output = faded(normalize(buffer, peak: peak))
    pcm.frameLength = AVAudioFrameCount(output.count)
    for (index, value) in output.enumerated() {
        channel[index] = Float(value)
    }
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: pcm)
    print("wrote \(url.lastPathComponent) (\(String(format: "%.2f", Double(output.count) / sampleRate)) s)")
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make_sounds.swift <output directory>\n".utf8))
    exit(64)
}

let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

try write(footstep(), name: "step", to: directory, peak: 0.6)
try write(crack(), name: "crack", to: directory)
try write(splat(), name: "splat", to: directory)
try write(plop(), name: "plop", to: directory, peak: 0.7)
try write(beep(frequency: 660, length: 0.2), name: "beep", to: directory, peak: 0.7)
try write(beep(frequency: 990, length: 0.4), name: "go", to: directory, peak: 0.75)
try write(arpeggio([523.3, 659.3, 784.0, 1046.5], step: 0.11, decay: 0.45, length: 1.3), name: "finish", to: directory)
try write(fail(), name: "fail", to: directory, peak: 0.75)
try write(splash(), name: "splash", to: directory)
try write(thunder(), name: "thunder", to: directory, peak: 0.95)
try write(rainLoop(), name: "rain", to: directory, peak: 0.5)
try write(windLoop(), name: "wind", to: directory, peak: 0.55)
try write(coin(), name: "coin", to: directory, peak: 0.7)
