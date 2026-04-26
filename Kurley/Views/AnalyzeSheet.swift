import SwiftUI

struct AnalyzeSheet: View {
    @ObservedObject var analyzer: Analyzer
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analyzing").font(.headline)
            ProgressView(value: analyzer.progress)
            Text(analyzer.current).font(.caption).foregroundStyle(.secondary).lineLimit(1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(analyzer.log.enumerated()), id: \.offset) { idx, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .id(idx)
                        }
                    }.padding(8)
                }
                .frame(minHeight: 320, maxHeight: 480)
                .background(Color.black.opacity(0.4))
                .onChange(of: analyzer.log.count) { _, n in
                    proxy.scrollTo(n - 1, anchor: .bottom)
                }
            }

            HStack {
                Spacer()
                if analyzer.running {
                    Button("Cancel") { analyzer.cancel() }
                } else {
                    Button("Close") { onDone(); dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
