import Foundation
import Combine

/**
 * Analyzer
 * Runs Python BPM/key detection script as subprocess.
 * Streams progress lines to delegate.
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
    private let kPython = "kurley.pythonPath"
    private let kRename = "kurley.renameAfter"
    private var stdoutBuffer = ""

    init() {
        self.renameAfter = UserDefaults.standard.bool(forKey: "kurley.renameAfter")
    }

    var pythonPath: String {
        get { defaults.string(forKey: kPython) ?? "/opt/homebrew/bin/python3" }
        set { defaults.set(newValue, forKey: kPython) }
    }

    func scriptURL() -> URL? {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: "/Users/johnshields/Projects/kurley/scripts/analyze.py"),
            Bundle.main.url(forResource: "analyze", withExtension: "py")
        ].compactMap { $0 }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    func analyzeFile(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        run(args: ["--file", url.path] + (rename ? ["--rename"] : []), completion: completion)
    }

    func analyzeFolder(_ url: URL, rename: Bool = false, completion: @escaping () -> Void) {
        run(args: ["--folder", url.path] + (rename ? ["--rename"] : []), completion: completion)
    }

    func resetFolder(_ url: URL, completion: @escaping () -> Void) {
        run(args: ["--folder", url.path, "--reset"], completion: completion)
    }

    func resetFile(_ url: URL, completion: @escaping () -> Void) {
        run(args: ["--file", url.path, "--reset"], completion: completion)
    }

    func cancel() {
        task?.terminate()
        task = nil
        running = false
    }

    private func run(args: [String], completion: @escaping () -> Void) {
        guard let script = scriptURL() else {
            log.append("ERROR: analyze.py not found")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = [script.path] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        running = true
        log = []
        progress = 0
        stdoutBuffer = ""
        var total: Double = 0
        var done: Double = 0

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.stdoutBuffer += chunk
                while let nl = self.stdoutBuffer.firstIndex(of: "\n") {
                    let line = String(self.stdoutBuffer[..<nl])
                    self.stdoutBuffer.removeSubrange(...nl)
                    if line.isEmpty { continue }
                    self.log.append(line)
                    if line.hasPrefix("TOTAL:") {
                        total = Double(line.replacingOccurrences(of: "TOTAL:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                    } else if line.hasPrefix("PROGRESS:") {
                        let body = line.replacingOccurrences(of: "PROGRESS:", with: "").trimmingCharacters(in: .whitespaces)
                        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
                        if let idxFrac = parts.first, let idx = Double(idxFrac.split(separator: "/").first.map(String.init) ?? "0") {
                            done = idx
                            if total > 0 { self.progress = done / total }
                        }
                        self.current = parts.count > 1 ? parts[1] : ""
                    }
                }
            }
        }

        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.running = false
                self.task = nil
                self.progress = 1
                pipe.fileHandleForReading.readabilityHandler = nil
                completion()
            }
        }

        do {
            try p.run()
            task = p
        } catch {
            running = false
            log.append("ERROR launching: \(error)")
        }
    }
}
