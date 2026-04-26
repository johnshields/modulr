import SwiftUI

struct AnalyzeSheet: View {
    @ObservedObject var analyzer: Analyzer
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var stats: (analyzed: Int, skipped: Int, errors: Int, renamed: Int) {
        var a = 0, s = 0, e = 0, r = 0
        for line in analyzer.log {
            if line.hasPrefix("RESULT:") { a += 1 }
            else if line.hasPrefix("SKIP:") { s += 1 }
            else if line.hasPrefix("ERROR:") { e += 1 }
            else if line.hasPrefix("RENAMED:") { r += 1 }
        }
        return (a, s, e, r)
    }

    private var lastResult: String? {
        analyzer.log.reversed().first { $0.hasPrefix("RESULT:") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            progressSection
            statsRow
            consoleView
            footer
        }
        .padding(20)
        .frame(width: 600, height: 540)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: analyzer.running ? "waveform.badge.magnifyingglass" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(analyzer.running ? Self.accent : .green)
                .symbolEffect(.pulse, isActive: analyzer.running)

            VStack(alignment: .leading, spacing: 2) {
                Text(analyzer.running ? "Analysing" : "Done")
                    .font(.headline)
                Text(analyzer.running ? "Detecting BPM and key per track" : "All tracks processed")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(analyzer.current.isEmpty ? "—" : analyzer.current)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int(analyzer.progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: analyzer.progress)
                .progressViewStyle(.linear)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            chip("Analysed", count: stats.analyzed, color: Self.accent)
            chip("Skipped", count: stats.skipped, color: .gray)
            chip("Renamed", count: stats.renamed, color: .blue)
            chip("Errors", count: stats.errors, color: .red)
            Spacer()
        }
    }

    private func chip(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption)
            Text("\(count)").font(.caption.bold()).foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .cornerRadius(4)
    }

    private var consoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(analyzer.log.enumerated()), id: \.offset) { idx, line in
                        logLine(line).id(idx)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxHeight: .infinity)
            .onChange(of: analyzer.log.count) { _, n in
                guard n > 0 else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(n - 1, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func logLine(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix(of: line))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color(of: line))
                .frame(width: 64, alignment: .leading)
            Text(body(of: line))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    private func prefix(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[..<colon])
    }

    private func body(of line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    private func color(of line: String) -> Color {
        if line.hasPrefix("RESULT:") { return Self.accent }
        if line.hasPrefix("RENAMED:") { return .blue }
        if line.hasPrefix("SKIP:") { return .gray }
        if line.hasPrefix("ERROR:") { return .red }
        if line.hasPrefix("PROGRESS:") { return .yellow }
        if line.hasPrefix("TOTAL:") || line.hasPrefix("DONE") { return .green }
        if line.hasPrefix("ARTWORK_SET:") || line.hasPrefix("TITLE_SET:") { return .cyan }
        return .secondary
    }

    private var footer: some View {
        HStack {
            if analyzer.running {
                ProgressView().controlSize(.small)
                Text("Running…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if analyzer.running {
                Button("Cancel", role: .destructive) { analyzer.cancel() }
            } else {
                Button("Close") { onDone(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
