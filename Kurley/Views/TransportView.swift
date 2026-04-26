import SwiftUI

struct TransportView: View {
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        HStack(spacing: 16) {
            Toggle("AutoPlay", isOn: .constant(true)).toggleStyle(.switch)
            Toggle("Mute", isOn: $player.isMuted).toggleStyle(.switch)
            Toggle("Shuffle", isOn: $player.isShuffled).toggleStyle(.switch)

            Spacer()

            Button(action: {}) { Image(systemName: "backward.end.fill") }
            Button(action: {}) { Image(systemName: "backward.fill") }
            Button(action: player.stop) { Image(systemName: "stop.fill") }
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            Button(action: {}) { Image(systemName: "forward.fill") }
            Button(action: {}) { Image(systemName: "forward.end.fill") }

            Spacer()

            VStack {
                Text("Volume").font(.caption2)
                Slider(value: $player.volume, in: 0...1).frame(width: 100)
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}
