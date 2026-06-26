import SwiftUI
import AppKit

struct WaveformView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @ObservedObject var monitor: PlaybackMonitor
    @State private var slices: [WaveSlice] = []
    @State private var artwork: NSImage?
    @State private var hoverX: CGFloat?
    @State private var zoom: CGFloat = 1.0

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 32.0

    var body: some View {
        HStack(spacing: 0) {
            artworkAndWaveform
            LevelMeterView(monitor: monitor)
                .frame(width: 64)
                .padding(.vertical, 6)
                .padding(.trailing, 6)
                .background(Color.black.opacity(0.85))
        }
        .frame(height: 180)
        .overlay(alignment: .bottom) {
            HStack(spacing: 14) {
                Button { prevTrack() } label: { Image(systemName: "backward.end.fill") }
                    .help("Previous track")
                Button { skip(-10) } label: { Image(systemName: "backward.fill") }
                    .help("Back 10s")
                Button(action: player.stop) { Image(systemName: "stop.fill") }
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { skip(10) } label: { Image(systemName: "forward.fill") }
                    .help("Forward 10s")
                Button { nextTrack() } label: { Image(systemName: "forward.end.fill") }
                    .help("Next track")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.6))
            .cornerRadius(8)
            .padding(.bottom, 8)
        }
        .task(id: player.currentURL) {
            guard let url = player.currentURL else {
                slices = []
                artwork = nil
                return
            }
            zoom = 1
            async let p = WaveformLoader.slices(from: url)
            async let a = ArtworkLoader.load(url)
            slices = await p
            artwork = await a
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkChanged)) { note in
            guard let changed = note.object as? URL, changed == player.currentURL else { return }
            if let data = note.userInfo?["data"] as? Data, let img = NSImage(data: data) {
                artwork = img
            } else {
                artwork = nil
            }
        }
    }

    @ViewBuilder
    private var artworkAndWaveform: some View {
        Group {
            ZStack {
                Color.black.opacity(0.85)
                if let art = artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .clipped()

            GeometryReader { geo in
                let contentWidth = geo.size.width * zoom

                ZStack(alignment: .topLeading) {
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: zoom > 1) {
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<100, id: \.self) { i in
                                    Color.clear
                                        .frame(width: contentWidth / 100, height: 1)
                                        .id("mark-\(i)")
                                }
                            }
                            .frame(width: contentWidth, height: 1)

                            Canvas { ctx, size in
                                guard !slices.isEmpty else { return }
                                let mid = size.height / 2
                                let step = size.width / CGFloat(slices.count)
                                let progress = player.duration > 0 ? monitor.currentTime / player.duration : 0
                                let progressX = size.width * CGFloat(progress)

                                func bandColor(_ s: WaveSlice, played: Bool) -> Color {
                                    let gamma = 0.85
                                    var r = pow(Double(s.low), gamma) * 1.7
                                    var g = pow(Double(s.mid), gamma) * 0.8
                                    var b = pow(Double(s.high), gamma) * 1.2
                                    let floor = min(r, min(g, b)) * 0.6
                                    r -= floor; g -= floor; b -= floor
                                    let gain = played ? 1.3 : 0.5
                                    return Color(red: max(0, min(1, r * gain)),
                                                 green: max(0, min(1, g * gain)),
                                                 blue: max(0, min(1, b * gain)))
                                }

                                for (i, s) in slices.enumerated() {
                                    let x = CGFloat(i) * step
                                    let h = CGFloat(s.peak) * size.height
                                    let rect = CGRect(x: x, y: mid - h/2, width: max(1, step - 0.5), height: h)
                                    ctx.fill(Path(rect), with: .color(bandColor(s, played: x < progressX)))
                                }

                                let head = Color(red: 1.0, green: 0.25, blue: 0.32)
                                var glow = Path()
                                glow.move(to: CGPoint(x: progressX, y: 0))
                                glow.addLine(to: CGPoint(x: progressX, y: size.height))
                                ctx.stroke(glow, with: .color(head.opacity(0.25)), lineWidth: 6)
                                ctx.stroke(glow, with: .color(head.opacity(0.5)), lineWidth: 3)
                                ctx.stroke(glow, with: .color(head), lineWidth: 1.5)

                                if let hx = self.hoverX {
                                    var hover = Path()
                                    hover.move(to: CGPoint(x: hx, y: 0))
                                    hover.addLine(to: CGPoint(x: hx, y: size.height))
                                    ctx.stroke(hover, with: .color(head.opacity(0.15)), lineWidth: 6)
                                    ctx.stroke(hover, with: .color(head.opacity(0.35)), lineWidth: 3)
                                    ctx.stroke(hover, with: .color(head.opacity(0.7)), lineWidth: 1)
                                }
                            }
                            .frame(width: contentWidth, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let pt): hoverX = max(0, min(contentWidth, pt.x))
                                case .ended: hoverX = nil
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let ratio = max(0, min(1, value.location.x / contentWidth))
                                        player.seek(to: player.duration * Double(ratio))
                                    }
                            )

                            if let hx = hoverX {
                                let ratio = max(0, min(1, hx / contentWidth))
                                let t = player.duration * Double(ratio)
                                Text(Formatters.mmss(t))
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.black.opacity(0.7))
                                    .foregroundStyle(.white)
                                    .cornerRadius(4)
                                    .offset(x: min(max(hx - 30, 4), contentWidth - 64), y: 30)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: contentWidth, height: geo.size.height)
                    }
                    .onChange(of: zoom) { _, _ in
                        let ratio = player.duration > 0 ? monitor.currentTime / player.duration : 0
                        let idx = max(0, min(99, Int(ratio * 100)))
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("mark-\(idx)", anchor: .center)
                            }
                        }
                    }
                    }

                    HStack {
                        Text(Formatters.mmss(monitor.currentTime))
                        Spacer()
                        Text("-" + Formatters.mmss(max(0, player.duration - monitor.currentTime)))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .allowsHitTesting(false)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()

                            HStack(spacing: 4) {
                                Button { setZoom(zoom / 2) } label: {
                                    Image(systemName: "minus.magnifyingglass")
                                }
                                .disabled(zoom <= minZoom)

                                Button { setZoom(1) } label: {
                                    Text("\(Int(zoom))x")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(minWidth: 28)
                                        .foregroundStyle(.white)
                                }
                                .help("Reset zoom")
                                .disabled(zoom == 1)

                                Button { setZoom(zoom * 2) } label: {
                                    Image(systemName: "plus.magnifyingglass")
                                }
                                .disabled(zoom >= maxZoom)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.6))
                            .cornerRadius(6)
                        }
                        .padding(8)
                    }
                }
                .onHover { inside in
                    if inside { NSCursor.iBeam.push() } else { NSCursor.pop() }
                }
            }
            .background(Color.black.opacity(0.85))
        }
    }

    private func setZoom(_ z: CGFloat) {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoom = max(minZoom, min(maxZoom, z))
        }
    }

    private func skip(_ delta: TimeInterval) {
        player.seek(to: monitor.currentTime + delta)
    }

    private func currentIndex() -> Int? {
        guard let url = player.currentURL else { return nil }
        return library.tracks.firstIndex(where: { $0.url == url })
    }

    private func nextTrack() {
        let tracks = library.tracks
        guard !tracks.isEmpty else { return }
        let next: Track
        if player.isShuffled {
            next = tracks.randomElement()!
        } else if let i = currentIndex(), i + 1 < tracks.count {
            next = tracks[i + 1]
        } else {
            next = tracks[0]
        }
        player.load(next.url)
        player.play()
    }

    private func prevTrack() {
        let tracks = library.tracks
        guard !tracks.isEmpty else { return }
        if monitor.currentTime > 3 {
            player.seek(to: 0)
            return
        }
        let prev: Track
        if let i = currentIndex(), i > 0 {
            prev = tracks[i - 1]
        } else {
            prev = tracks.last!
        }
        player.load(prev.url)
        player.play()
    }

}
