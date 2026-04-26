import SwiftUI

struct WaveformView: View {
    @EnvironmentObject var player: AudioPlayer
    @State private var peaks: [Float] = []

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let mid = size.height / 2
            let step = size.width / CGFloat(peaks.count)
            let progress = player.duration > 0 ? player.currentTime / player.duration : 0
            let progressX = size.width * CGFloat(progress)

            for (i, p) in peaks.enumerated() {
                let x = CGFloat(i) * step
                let h = CGFloat(p) * size.height
                let rect = CGRect(x: x, y: mid - h/2, width: max(1, step - 0.5), height: h)
                let color: Color = x < progressX ? .accentColor : .gray
                ctx.fill(Path(rect), with: .color(color))
            }

            var line = Path()
            line.move(to: CGPoint(x: progressX, y: 0))
            line.addLine(to: CGPoint(x: progressX, y: size.height))
            ctx.stroke(line, with: .color(.white), lineWidth: 1)
        }
        .frame(height: 180)
        .background(Color.black.opacity(0.85))
        .task(id: player.currentURL) {
            guard let url = player.currentURL else { peaks = []; return }
            peaks = await WaveformLoader.peaks(from: url)
        }
    }
}
