import Foundation

/**
 * PythonRunner
 * Single bridge for all Python script invocations
 * Owns interpreter path, script discovery, subprocess lifecycle
 */
final class PythonRunner {
    static let shared = PythonRunner()

    private let defaults = UserDefaults.standard
    private let kPython = "modulr.pythonPath"

    var pythonPath: String {
        get { defaults.string(forKey: kPython) ?? "/opt/homebrew/bin/python3" }
        set { defaults.set(newValue, forKey: kPython) }
    }

    /**
     * Locate analyze.py inside the bundled Resources/scripts.
     * Bundle path keeps the modulr/ package sibling so relative imports resolve.
     */
    func scriptURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let path = resources.appendingPathComponent("scripts/analyze.py")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /**
     * Fire-and-wait subprocess. Optional stdin payload. Discards stdout/stderr.
     */
    func runSync(_ args: [String], stdin: Data? = nil) {
        guard let script = scriptURL() else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [script.path] + args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        if let stdin {
            let inPipe = Pipe()
            task.standardInput = inPipe
            do {
                try task.run()
                inPipe.fileHandleForWriting.write(stdin)
                try? inPipe.fileHandleForWriting.close()
                task.waitUntilExit()
            } catch {
                print("PythonRunner runSync stdin failed: \(error)")
            }
        } else {
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                print("PythonRunner runSync failed: \(error)")
            }
        }
    }

    /**
     * Streaming subprocess. Caller receives each stdout line on main queue.
     * Returns the Process for cancellation.
     */
    @discardableResult
    func runStreaming(_ args: [String], onLine: @escaping (String) -> Void, onExit: @escaping () -> Void) -> Process? {
        guard let script = scriptURL() else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [script.path] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                buffer += chunk
                while let nl = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[..<nl])
                    buffer.removeSubrange(...nl)
                    if !line.isEmpty { onLine(line) }
                }
            }
        }

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                onExit()
            }
        }

        do {
            try task.run()
            return task
        } catch {
            DispatchQueue.main.async { onExit() }
            return nil
        }
    }
}
