// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

struct Trace {
    let name: String
    let x: [Double]
    let y: [Double]
    var color: Color = .blue
    var dashed = false
}

struct Plot: View {
    let title: String
    let traces: [Trace]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let xLabel: String
    var yLabel = "Amplitude (relative)"
    var summary: String
    var isSpectrum = false
    var marker: Double? = nil
    var playing = false
    var start = Date()
    var frozen = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack(spacing: 12) {
                ForEach(traces.indices.filter { !traces[$0].name.isEmpty }, id: \.self) { i in
                    HStack(spacing: 5) {
                        Image(systemName: traces[i].dashed ? "minus" : "waveform.path").foregroundStyle(traces[i].color)
                        Text(traces[i].name).font(.caption)
                    }
                }
            }
            Text(yLabel).font(.caption2).foregroundStyle(.secondary)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing)) { timeline in
                Canvas { context, size in
                    let rect = CGRect(x: 42, y: 7, width: max(1, size.width - 54), height: max(1, size.height - 32))
                    func px(_ x: Double) -> Double { rect.minX + (x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound) * rect.width }
                    func py(_ y: Double) -> Double { rect.maxY - (y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound) * rect.height }
                    for tick in 0...4 {
                        let fraction = Double(tick) / 4
                        let x = xRange.lowerBound + fraction * (xRange.upperBound - xRange.lowerBound)
                        let y = yRange.lowerBound + fraction * (yRange.upperBound - yRange.lowerBound)
                        var grid = Path()
                        grid.move(to: CGPoint(x: px(x), y: rect.minY)); grid.addLine(to: CGPoint(x: px(x), y: rect.maxY))
                        grid.move(to: CGPoint(x: rect.minX, y: py(y))); grid.addLine(to: CGPoint(x: rect.maxX, y: py(y)))
                        context.stroke(grid, with: .color(.secondary.opacity(0.17)), lineWidth: 1)
                        context.draw(Text(Self.label(x)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: px(x), y: rect.maxY + 15))
                        context.draw(Text(Self.label(y)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: rect.minX - 7, y: py(y)), anchor: .trailing)
                    }
                    var clipped = context
                    clipped.clip(to: Path(rect))
                    for trace in traces {
                        var path = Path()
                        var first = true
                        for (x, y) in zip(trace.x, trace.y) where x >= xRange.lowerBound && x <= xRange.upperBound {
                            guard y.isFinite else { first = true; continue }
                            if isSpectrum && !trace.dashed {
                                path.move(to: CGPoint(x: px(x), y: py(0)))
                                path.addLine(to: CGPoint(x: px(x), y: py(y)))
                            } else {
                                let point = CGPoint(x: px(x), y: py(y))
                                if first { path.move(to: point); first = false } else { path.addLine(to: point) }
                            }
                        }
                        clipped.stroke(path, with: .color(trace.color), style: StrokeStyle(lineWidth: 1.7, dash: trace.dashed ? [5, 4] : []))
                    }
                    if let marker, xRange.contains(marker) {
                        var line = Path()
                        line.move(to: CGPoint(x: px(marker), y: rect.minY)); line.addLine(to: CGPoint(x: px(marker), y: rect.maxY))
                        clipped.stroke(line, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if !isSpectrum {
                        let elapsed = frozen + (playing ? timeline.date.timeIntervalSince(start) : 0)
                        let fraction = elapsed.truncatingRemainder(dividingBy: 6) / 6
                        let x = rect.minX + fraction * rect.width
                        var cursor = Path()
                        cursor.move(to: CGPoint(x: x, y: rect.minY)); cursor.addLine(to: CGPoint(x: x, y: rect.maxY))
                        clipped.stroke(cursor, with: .color(.primary.opacity(0.3)), lineWidth: 1)
                    }
                }
            }.frame(height: 160)
            Text(xLabel).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
    }

    static func label(_ value: Double) -> String {
        abs(value) >= 10 ? String(format: "%.0f", value) : String(format: "%.2g", value)
    }
}

func timeTrace(_ name: String, _ values: [Double], rate: Double, color: Color = .blue, dashed: Bool = false) -> Trace {
    Trace(name: name, x: values.indices.map { Double($0) / rate * 1000 }, y: values, color: color, dashed: dashed)
}
func spectrumTrace(_ name: String, _ values: [Double], rate: Double, window: FFTWindow = .rectangular, color: Color = .blue) -> Trace {
    let spectrum = DSP.spectrum(values, sampleRate: rate, window: window)
    return Trace(name: name, x: spectrum.frequencies, y: spectrum.amplitudes, color: color)
}
