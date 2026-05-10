import Foundation
import Combine

/**
 * Analyzer
 * Owns analyze.py session state. Delegates subprocess plumbing to PythonRunner.
 */
final class Analyzer: ObservableObject {
    enum Mode: String {
        case analyse, reset, normalize, syncFilename, idle

        var title: String {
            switch self {
            case .analyse: return "Analysing"
            case .reset: return "Resetting Names"
            case .normalize: return "Matching Loudness"
            case .syncFilename: return "Syncing Filenames"
            case .idle: return "Working"
            }
        }

        var subtitle: String {
            switch self {
            case .analyse: return "Detecting BPM and key per track"
            case .reset: return "Stripping suffixes from filenames"
            case .normalize: return "Measuring volume and applying gain"
            case .syncFilename: return "Adding _KEY_BPM suffix from tags"
            case .idle: return ""
            }
        }
    }

    @Published var running = false
    @Published var current: String = ""
    @Published var progress: Double = 0
    @Published var log: [String] = []
    @Published var mode: Mode = .idle
    @Published var renameAfter: Bool {
        didSet { defaults.set(renameAfter, forKey: kRename) }
    }
    @Published var keepOrder: Bool {
        didSet { defaults.set(keepOrder, forKey: kKeepOrder) }
    }

    private var task: Process?
    private let defaults = UserDefaults.standard
    private let kRename = "kurley.renameAfter"
    private let kKeepOrder = "kurley.keepOrder"
    private var totalCount: Double = 0

    init() {
        self.renameAfter = UserDefaults.standard.bool(forKey: "kurley.renameAfter")
        self.keepOrder = UserDefaults.standard.bool(forKey: "kurley.keepOrder")
    }

    /**
     * Public entry points. `rename` only applies to analyse-mode invocations.
     */
    func analyzeFile(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        mode = .analyse
        var args = ["--file", url.path]
        if rename { args.append("--rename") }
        if rename && keepOrder { args.append("--keep-numbers") }
        run(args: args, completion: completion)
    }

    func analyzeFolder(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        mode = .analyse
        var args = ["--folder", url.path]
        if rename { args.append("--rename") }
        if rename && keepOrder { args.append("--keep-numbers") }
        run(args: args, completion: completion)
    }

    func resetFolder(_ url: URL, keepNumbers: Bool = false, completion: @escaping () -> Void) {
        mode = .reset
        var args = ["--folder", url.path, "--reset"]
        if keepNumbers { args.append("--keep-numbers") }
        run(args: args, completion: completion)
    }

    func resetFile(_ url: URL, keepNumbers: Bool = false, completion: @escaping () -> Void) {
        mode = .reset
        var args = ["--file", url.path, "--reset"]
        if keepNumbers { args.append("--keep-numbers") }
        run(args: args, completion: completion)
    }

    func stripNumbersFolder(_ url: URL, completion: @escaping () -> Void) {
        mode = .reset
        run(args: ["--folder", url.path, "--strip-numbers"], completion: completion)
    }

    func stripNumbersFile(_ url: URL, completion: @escaping () -> Void) {
        mode = .reset
        run(args: ["--file", url.path, "--strip-numbers"], completion: completion)
    }

    func normalizePreview(_ url: URL, completion: @escaping () -> Void) {
        mode = .normalize
        run(args: ["--normalize", url.path], completion: completion)
    }

    func normalizeApply(_ url: URL, completion: @escaping () -> Void) {
        mode = .normalize
        run(args: ["--normalize", url.path, "--apply"], completion: completion)
    }

    func normalizeFilePreview(_ url: URL, completion: @escaping () -> Void) {
        mode = .normalize
        run(args: ["--normalize-file", url.path], completion: completion)
    }

    func normalizeFileApply(_ url: URL, completion: @escaping () -> Void) {
        mode = .normalize
        run(args: ["--normalize-file", url.path, "--apply"], completion: completion)
    }

    func syncFilenameToTags(_ url: URL, completion: @escaping () -> Void) {
        mode = .syncFilename
        run(args: ["--sync-filename", url.path], completion: completion)
    }

    func bakeTweak(_ url: URL, rate: Float, cents: Float, bpm: Int?, key: String?, completion: @escaping () -> Void) {
        mode = .normalize  // reuse loudness mode UI for now
        let args = [
            "--bake-tweak", url.path,
            String(format: "%.4f", rate),
            String(format: "%.1f", cents),
            bpm.map(String.init) ?? "-",
            key ?? "-"
        ]
        run(args: args, completion: completion)
    }

    func cancel() {
        task?.terminate()
        task = nil
        running = false
    }

    private func run(args: [String], completion: @escaping () -> Void) {
        running = true
        log = []
        progress = 0
        totalCount = 0

        task = PythonRunner.shared.runStreaming(
            args,
            onLine: { [weak self] line in self?.handle(line: line) },
            onExit: { [weak self] in
                self?.running = false
                self?.task = nil
                self?.progress = 1
                completion()
            }
        )

        if task == nil {
            running = false
            log.append("ERROR: analyze.py not found or failed to launch")
        }
    }

    private func handle(line: String) {
        log.append(line)
        if line.hasPrefix("TOTAL:") {
            totalCount = Double(line.replacingOccurrences(of: "TOTAL:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
        } else if line.hasPrefix("PROGRESS:") {
            let body = line.replacingOccurrences(of: "PROGRESS:", with: "").trimmingCharacters(in: .whitespaces)
            let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
            if let frac = parts.first,
               let done = Double(frac.split(separator: "/").first.map(String.init) ?? "0"),
               totalCount > 0 {
                progress = done / totalCount
            }
            current = parts.count > 1 ? parts[1] : ""
        }
    }
}
