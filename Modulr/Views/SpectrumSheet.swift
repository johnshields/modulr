import SwiftUI
import AppKit
import AVFoundation

/**
 * SpectrumSheet
 * Spek-style spectrum view for a single track. Top header carries codec /
 * bitrate / sample-rate; the heatmap fills the middle with a left frequency
 * axis, bottom time axis, and a right dB legend; a footer surfaces the
 * lossy-source heuristic.
 */
struct SpectrumSheet: View {
    let trackURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var spectrum: SpectrumGenerator.Spectrum?
    @State private var image: NSImage?
    @State private var error: String?
    @State private var streamInfo: String = ""
    @State private var renderSize: CGSize = .zero

    private static let axisLeft: CGFloat = 60
    private static let axisBottom: CGFloat = 32
    private static let legendRight: CGFloat = 78
    private static let textColor = Color.white.opacity(0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            GeometryReader { geo in
                let heatmapSize = CGSize(
                    width: max(1, geo.size.width - Self.axisLeft - Self.legendRight),
                    height: max(1, geo.size.height - Self.axisBottom)
                )

                HStack(spacing: 0) {
                    freqAxis(height: heatmapSize.height)
                        .frame(width: Self.axisLeft)

                    VStack(spacing: 0) {
                        heatmap(size: heatmapSize)
                        timeAxis(width: heatmapSize.width)
                            .frame(height: Self.axisBottom)
                    }

                    dBLegend(height: heatmapSize.height)
                        .frame(width: Self.legendRight)
                }
                .onAppear { renderSize = heatmapSize }
                .onChange(of: geo.size) { _, _ in
                    renderSize = heatmapSize
                    rerender()
                }
            }
            .frame(minHeight: 360)

            footer
        }
        .padding(16)
        .frame(minWidth: 880, minHeight: 540)
        .background(Color.black)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
        .task { await analyse() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trackURL.lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(Self.textColor)
                    .lineLimit(1)
                if !streamInfo.isEmpty || spectrum != nil {
                    Text(headerDetailLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var headerDetailLine: String {
        var parts: [String] = []
        if !streamInfo.isEmpty { parts.append(streamInfo) }
        if let s = spectrum {
            parts.append("\(s.timeColumns) cols · \(s.freqBins) bins · \(SpectrumGenerator.fftSize)-pt FFT")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func heatmap(size: CGSize) -> some View {
        ZStack {
            Color.black
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size.width, height: size.height)
            } else if error == nil {
                ProgressView("Analysing…")
                    .controlSize(.small)
                    .foregroundStyle(Self.textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func freqAxis(height: CGFloat) -> some View {
        if let s = spectrum {
            let nyquist = s.sampleRate / 2
            let ticks = freqTicks(nyquist: nyquist)
            ZStack(alignment: .topTrailing) {
                ForEach(ticks, id: \.self) { hz in
                    let y = height * CGFloat(1 - hz / nyquist)
                    Text(formatHz(hz))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Self.textColor)
                        .padding(.trailing, 6)
                        .offset(y: y - 7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func timeAxis(width: CGFloat) -> some View {
        if let s = spectrum {
            let ticks = timeTicks(duration: s.duration)
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { t in
                    let x = width * CGFloat(t / s.duration)
                    Text(formatTime(t))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Self.textColor)
                        .offset(x: x - 14, y: 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    private func dBLegend(height: CGFloat) -> some View {
        let labels: [Float] = [0, -20, -40, -60, -80, -100, -120]
        return HStack(spacing: 6) {
            Canvas { ctx, size in
                let steps = Int(size.height)
                for i in 0..<steps {
                    let v = 1 - Float(i) / Float(max(1, steps - 1))
                    let (r, g, b) = SpectrumImageRenderer.palette(v)
                    let color = Color(
                        red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255
                    )
                    let rect = CGRect(x: 0, y: CGFloat(i), width: size.width, height: 1)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
            .frame(width: 14, height: height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(labels, id: \.self) { db in
                    let yNorm = (SpectrumGenerator.maxDB - db) /
                        (SpectrumGenerator.maxDB - SpectrumGenerator.minDB)
                    Text("\(Int(db)) dB")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Self.textColor)
                        .offset(y: height * CGFloat(yNorm) - 7)
                        .frame(height: 0, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.leading, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            if let v = verdict {
                Text(v.label.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(v.color)
                    .help(v.detail)
                Text(v.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var verdict: QualityVerdict? {
        spectrum.map(SpectrumAnalysis.verdict(spectrum:))
    }

    private func analyse() async {
        do {
            let result = try await SpectrumGenerator.generate(url: trackURL)
            let info = buildStreamInfo(url: trackURL, sampleRate: result.sampleRate)
            await MainActor.run {
                self.spectrum = result
                self.streamInfo = info
                self.rerender()
            }
        } catch {
            await MainActor.run { self.error = "Analyse failed: \(error)" }
        }
    }

    private func rerender() {
        guard let s = spectrum else { return }
        let w = max(1, Int(renderSize.width))
        let h = max(1, Int(renderSize.height))
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cg = SpectrumImageRenderer.render(s, width: w, height: h) else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            DispatchQueue.main.async { self.image = img }
        }
    }

    // Axis helpers

    private func freqTicks(nyquist: Double) -> [Double] {
        let candidates: [Double] = [0, 1_000, 5_000, 10_000, 15_000, 20_000, 22_050, 24_000]
        return candidates.filter { $0 <= nyquist + 1 }
    }

    private func timeTicks(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        let step: Double
        switch duration {
        case ..<60:    step = 5
        case ..<180:   step = 30
        case ..<600:   step = 60
        case ..<1800:  step = 300
        default:       step = 600
        }
        return stride(from: 0, through: duration, by: step).map { $0 }
    }

    private func formatHz(_ hz: Double) -> String { Formatters.hertz(hz) }
    private func formatTime(_ s: Double) -> String { Formatters.mss(s) }

    private func buildStreamInfo(url: URL, sampleRate: Double) -> String {
        let codec = url.pathExtension.uppercased()
        let asset = AVURLAsset(url: url)
        var bitrate: Int?
        if let track = asset.tracks(withMediaType: .audio).first {
            let bps = track.estimatedDataRate
            if bps > 0 { bitrate = Int((bps / 1000).rounded()) }
        }
        let parts: [String?] = [
            codec,
            bitrate.map { "\($0) kbps" },
            "\(Int(sampleRate)) Hz",
            "\(SpectrumGenerator.fftSize)-pt FFT",
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

}
