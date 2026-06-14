import SwiftUI

struct AnalyzeSheet: View {
    @ObservedObject var analyzer: Analyzer
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void

    @State private var lastRefreshLogCount = 0

    private struct Counts {
        var analysed = 0, skipped = 0, errors = 0, renamed = 0
        var measured = 0, applied = 0, planned = 0
    }

    private var counts: Counts {
        var c = Counts()
        for line in analyzer.log {
            if line.hasPrefix("RESULT:") { c.analysed += 1 }
            else if line.hasPrefix("SKIP:") { c.skipped += 1 }
            else if line.hasPrefix("ERROR:") { c.errors += 1 }
            else if line.hasPrefix("RENAMED:") { c.renamed += 1 }
            else if line.hasPrefix("MEASURE:") { c.measured += 1 }
            else if line.hasPrefix("PLAN:") { c.planned += 1 }
            else if line.hasPrefix("APPLIED:") { c.applied += 1 }
        }
        return c
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
        .overlay(alignment: .topTrailing) {
            MacCloseButton {
                if analyzer.running { analyzer.cancel() }
                onDone(); dismiss()
            }
        }
    }

    private var headerIcon: String {
        switch analyzer.mode {
        case .normalize: return "speaker.wave.2.fill"
        case .reset: return "arrow.counterclockwise"
        case .syncFilename: return "doc.text"
        default: return "waveform.badge.magnifyingglass"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: analyzer.running ? headerIcon : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(analyzer.running ? Theme.accent : .green)
                .symbolEffect(.pulse, isActive: analyzer.running)

            VStack(alignment: .leading, spacing: 2) {
                Text(analyzer.running ? analyzer.mode.title : "Done")
                    .font(.headline)
                Text(analyzer.running ? analyzer.mode.subtitle : "Operation complete")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(analyzer.current.isEmpty ? "" : analyzer.current)
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
                .animation(.easeOut(duration: 0.25), value: analyzer.progress)
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let c = counts
        HStack(spacing: 8) {
            switch analyzer.mode {
            case .normalize:
                chip("Measured", count: c.measured, color: .gray)
                chip("Planned", count: c.planned, color: Theme.accent)
                chip("Applied", count: c.applied, color: .green)
                chip("Errors", count: c.errors, color: .red)
            case .reset, .syncFilename:
                chip("Renamed", count: c.renamed, color: Theme.accent)
                chip("Skipped", count: c.skipped, color: .gray)
                chip("Errors", count: c.errors, color: .red)
            default:
                chip("Analysed", count: c.analysed, color: Theme.accent)
                chip("Skipped", count: c.skipped, color: .gray)
                chip("Renamed", count: c.renamed, color: .blue)
                chip("Errors", count: c.errors, color: .red)
            }
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
        if line.hasPrefix("RESULT:") { return Theme.accent }
        if line.hasPrefix("RENAMED:") { return .blue }
        if line.hasPrefix("SKIP:") { return .gray }
        if line.hasPrefix("ERROR:") { return .red }
        if line.hasPrefix("PROGRESS:") { return .yellow }
        if line.hasPrefix("TOTAL:") || line.hasPrefix("DONE") { return .green }
        if line.hasPrefix("ARTWORK_SET:") || line.hasPrefix("TITLE_SET:") || line.hasPrefix("TAG_SET:") { return .cyan }
        if line.hasPrefix("MEASURE:") { return .gray }
        if line.hasPrefix("PLAN:") { return Theme.accent }
        if line.hasPrefix("APPLIED:") { return .green }
        if line.hasPrefix("TARGET:") { return .orange }
        return .secondary
    }

    private var footer: some View {
        HStack {
            if analyzer.running {
                ProgressView().controlSize(.small)
                Text("Running…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
