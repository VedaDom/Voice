import Foundation

/// Spawns engine/worker.py and speaks the JSON-lines protocol with it.
final class WorkerBridge {
    private var process: Process?
    private var stdinPipe = Pipe()
    private let onEvent: ([String: Any]) -> Void

    init(onEvent: @escaping ([String: Any]) -> Void) {
        self.onEvent = onEvent
    }

    static var engineRoot: URL {
        if let env = ProcessInfo.processInfo.environment["VOICE_ENGINE_DIR"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Projects/voice")
    }

    /// (python, worker.py) — the runtime shipped inside the app bundle when
    /// present (release builds), otherwise the dev checkout.
    static func resolveEngine() -> (python: URL, script: URL) {
        if let res = Bundle.main.resourceURL {
            let python = res.appendingPathComponent("runtime/python/bin/python3")
            let script = res.appendingPathComponent("engine/worker.py")
            if FileManager.default.fileExists(atPath: python.path),
               FileManager.default.fileExists(atPath: script.path) {
                return (python, script)
            }
        }
        let root = engineRoot
        return (root.appendingPathComponent(".venv/bin/python"),
                root.appendingPathComponent("engine/worker.py"))
    }

    func launch() {
        let (python, script) = Self.resolveEngine()

        NSLog("Voice: launching worker python=%@ script=%@", python.path, script.path)
        guard FileManager.default.fileExists(atPath: python.path),
              FileManager.default.fileExists(atPath: script.path) else {
            NSLog("Voice: engine not found at %@", python.path)
            onEvent(["event": "state", "state": "error",
                     "message": "Engine not found"])
            return
        }

        let p = Process()
        p.executableURL = python
        p.arguments = [script.path]
        p.currentDirectoryURL = script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"   // bundle may be mounted read-only
        env["PYTHONNOUSERSITE"] = "1"
        p.environment = env

        stdinPipe = Pipe()
        let out = Pipe()
        p.standardInput = stdinPipe
        p.standardOutput = out
        let logURL = HistoryStore.dataDir.appendingPathComponent("worker.err.log")
        try? FileManager.default.createDirectory(at: HistoryStore.dataDir,
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: logURL)) ?? FileHandle.nullDevice

        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    DispatchQueue.main.async { self?.onEvent(obj) }
                }
            }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.onEvent(["event": "state", "state": "error",
                               "message": "Engine exited (code \(proc.terminationStatus))"])
            }
        }

        do {
            try p.run()
            process = p
            NSLog("Voice: worker started pid %d", p.processIdentifier)
        } catch {
            NSLog("Voice: worker spawn failed: %@", error.localizedDescription)
            onEvent(["event": "state", "state": "error",
                     "message": "Could not start engine: \(error.localizedDescription)"])
        }
    }

    func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    func setup() { send(["cmd": "setup"]) }
    func start(language: String) { send(["cmd": "start", "language": language]) }
    func stop() { send(["cmd": "stop"]) }
    func cancel() { send(["cmd": "cancel"]) }

    func shutdown() {
        send(["cmd": "shutdown"])
        process?.terminate()
    }
}
