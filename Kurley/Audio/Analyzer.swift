import Foundation
import Combine

/**
 * Analyzer
 * Owns analyze.py session state. Delegates subprocess plumbing to PythonRunner.
 */
final class Analyzer: ObservableObject {
    @Published var running = false
    @Published var current: String = ""
    @Published var progress: Double = 0
    @Published var log: [String] = []
    @Published var renameAfter: Bool {
        didSet { defaults.set(renameAfter, forKey: kRename) }
    }

    private var task: Process?
    private let defaults = UserDefaults.standard
    private let kRename = "kurley.renameAfter"
    private var totalCount: Double = 0

    init() {
        self.renameAfter = UserDefaults.standard.bool(forKey: "kurley.renameAfter")
    }

    /**
     * Public entry points. `rename` only applies to analyse-mode invocations.
     */
    func analyzeFile(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        run(args: ["--file", url.path] + (rename ? ["--rename"] : []), completion: completion)
    }

    func analyzeFolder(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        run(args: ["--folder", url.path] + (rename ? ["--rename"] : []), completion: completion)
    }

    func resetFolder(_ url: URL, keepNumbers: Bool = false, completion: @escaping () -> Void) {
        var args = ["--folder", url.path, "--reset"]
        if keepNumbers { args.append("--keep-numbers") }
        run(args: args, completion: completion)
    }

    func resetFile(_ url: URL, keepNumbers: Bool = false, completion: @escaping () -> Void) {
        var args = ["--file", url.path, "--reset"]
        if keepNumbers { args.append("--keep-numbers") }
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
