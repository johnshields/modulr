import SwiftUI

/**
 * LevelMeterView
 * Vertical stereo dBFS meter with scale labels (0, -12, -24, -36, -48)
 */
struct LevelMeterView: View {
    @ObservedObject var monitor: PlaybackMonitor

    private let minDb: Float = -48
    private let maxDb: Float = 0
    private let ticks: [Float] = [0, -12, -24, -36, -48]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(ticks, id: \.self) { db in
                    Text("\(Int(db))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: tickAlignment(db))
                }
            }
            .frame(width: 22)

            HStack(spacing: 2) {
                bar(level: monitor.levelL)
                bar(level: monitor.levelR)
            }
            .frame(width: 16)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
    }

    private func tickAlignment(_ db: Float) -> Alignment {
        if db == ticks.first { return .top }
        if db == ticks.last { return .bottom }
        return .center
    }

    @ViewBuilder
    private func bar(level: Float) -> some View {
        GeometryReader { geo in
            let clamped = max(minDb, min(maxDb, level))
            let frac = CGFloat((clamped - minDb) / (maxDb - minDb))
            let h = geo.size.height * frac

            ZStack(alignment: .bottom) {
                Color.white.opacity(0.08)
                LinearGradient(
                    colors: [
                        Color(red: 0x4f/255, green: 0x9e/255, blue: 0xff/255),
                        Color(red: 0xa8/255, green: 0x55/255, blue: 0xf7/255),
                        Color(red: 1, green: 0.4, blue: 0.4)
                    ],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: h)
                .animation(.linear(duration: 0.05), value: h)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(width: 7)
    }
}
