import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayer
    @StateObject private var library = Library()

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(library)
        } detail: {
            VStack(spacing: 0) {
                WaveformView()
                TransportView()
                Divider()
                TrackListView()
                    .environmentObject(library)
            }
        }
    }
}
