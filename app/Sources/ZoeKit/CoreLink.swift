import Foundation

/// How to start the core. The app owns it as a child process, so only the app can reach its stdin/stdout
/// (PLAN.md §3: no network port, nothing else can fake an approval).
public struct CoreCommand: Sendable {
    public var executable: URL
    public var arguments: [String]
    public var directory: URL?
    public var environment: [String: String]?

    public init(executable: URL, arguments: [String], directory: URL? = nil, environment: [String: String]? = nil) {
        self.executable = executable; self.arguments = arguments
        self.directory = directory; self.environment = environment
    }

    /// Development default. If the core's venv exists (`uv sync` in `core/`), run its `zoe-core` script
    /// directly: the core is then the app's direct child (so a crash is seen at once) and spawning skips
    /// uv. Otherwise fall back to `uv run`, which creates the venv. The packaged app bundles its own
    /// runtime (#7). `ZOE_CORE_DIR` overrides where the core project lives.
    public static func development(coreDir: URL) -> CoreCommand {
        let script = coreDir.appendingPathComponent(".venv/bin/zoe-core")
        if FileManager.default.isExecutableFile(atPath: script.path) {
            return CoreCommand(executable: script, arguments: [], directory: coreDir)
        }
        return CoreCommand(executable: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["uv", "run", "--quiet", "--project", coreDir.path, "zoe-core"],
                    directory: coreDir, environment: Self.environmentWithUVOnPath())
    }

    /// The installed app: `Contents/Resources/core/launch.sh` syncs the core's environment with uv, then
    /// becomes the core (#7).
    public static func bundled(coreDir: URL) -> CoreCommand {
        CoreCommand(executable: coreDir.appendingPathComponent("launch.sh"), arguments: [], directory: coreDir)
    }

    /// The bundled core if this is the installed app, else the development checkout.
    public static func auto(developmentCoreDir: URL) -> CoreCommand {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("core"),
           FileManager.default.isExecutableFile(atPath: res.appendingPathComponent("launch.sh").path) {
            return .bundled(coreDir: res)
        }
        return .development(coreDir: developmentCoreDir)
    }

    /// GUI apps don't inherit the shell PATH, so add the usual uv locations.
    static func environmentWithUVOnPath() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "\(NSHomeDirectory())/.cargo/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return env
    }
}

public enum LinkState: Sendable, Equatable {
    case starting
    case ready(pid: Int32)
    case offline(String)
    case stopped
}

/// Approval requests waiting for me. If the core restarts, every one of them counts as **deny**
/// (PLAN.md §3), because the core that asked no longer exists.
public final class PendingInputs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    public init() {}
    public func add(_ id: String) { lock.withLock { ids.append(id) } }
    public func resolve(_ id: String) { lock.withLock { ids.removeAll { $0 == id } } }
    public var count: Int { lock.withLock { ids.count } }
    /// Removes and returns every pending id; the caller dismisses their cards as denied.
    public func denyAll() -> [String] { lock.withLock { defer { ids.removeAll() }; return ids } }
}

/// Spawns the core, frames its stdout into messages, writes messages to its stdin, and restarts it with
/// backoff when it dies. All callbacks arrive on `callbackQueue` (main by default).
public final class CoreLink: @unchecked Sendable {
    public var onMessage: (@Sendable (CoreMessage) -> Void)?
    public var onState: (@Sendable (LinkState) -> Void)?
    public var onLog: (@Sendable (String) -> Void)?
    /// Pending approvals denied because the core restarted.
    public var onPendingDenied: (@Sendable ([String]) -> Void)?

    public let pending = PendingInputs()
    public private(set) var restarts = 0

    private let command: CoreCommand
    private let queue = DispatchQueue(label: "zoe.corelink")
    private let callbackQueue: DispatchQueue
    private var process: Process?
    private var stdin: FileHandle?
    private var framer = JSONLineFramer()
    private var stopping = false
    private var backoff: TimeInterval = 0.25
    private var startedAt = Date()
    private var state: LinkState = .stopped

    public init(command: CoreCommand, callbackQueue: DispatchQueue = .main) {
        self.command = command
        self.callbackQueue = callbackQueue
    }

    public func start() { queue.async { self.stopping = false; self.launch() } }

    /// My answer to a pending input: sent to the core and no longer pending.
    public func answer(pendingID: String, value: String, via: String) {
        pending.resolve(pendingID)
        send(CoreMessage("answer", ["pending_id": pendingID, "value": value, "via": via,
                                    "at": Date().timeIntervalSince1970]))
    }

    /// Asks the core to exit, then terminates it if it hasn't within a second.
    public func stop() {
        queue.sync {
            stopping = true
            writeLocked(CoreMessage("shutdown"))
            let p = process
            queue.asyncAfter(deadline: .now() + 1) { if p?.isRunning == true { p?.terminate() } }
        }
    }

    public func send(_ message: CoreMessage) { queue.async { self.writeLocked(message) } }

    // MARK: - internals (on `queue`)

    private func setState(_ s: LinkState) {
        state = s
        let cb = onState
        callbackQueue.async { cb?(s) }
    }

    private func launch() {
        setState(.starting)
        framer = JSONLineFramer()
        let p = Process()
        p.executableURL = command.executable
        p.arguments = command.arguments
        p.currentDirectoryURL = command.directory
        if let env = command.environment { p.environment = env }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self, !data.isEmpty else { h.readabilityHandler = nil; return }
            self.queue.async { self.received(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self, !data.isEmpty else { h.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            let cb = self.onLog
            self.callbackQueue.async { cb?(text) }
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async { self.terminated(proc) }
        }
        do {
            try p.run()
        } catch {
            setState(.offline("could not start core: \(error.localizedDescription)"))
            scheduleRestart()
            return
        }
        process = p
        stdin = inPipe.fileHandleForWriting
        startedAt = Date()
        writeLocked(CoreMessage("hello", ["protocol": 1]))
    }

    private func received(_ data: Data) {
        for r in framer.feed(data) {
            switch r {
            case .success(let m):
                if m.type == "hello", case .starting = state {
                    setState(.ready(pid: process?.processIdentifier ?? 0))
                }
                // Track what's waiting for me, so a core restart can deny it all (PLAN.md §3).
                if m.type == "pending_input", let id = m.string("id") { pending.add(id) }
                if m.type == "dismiss_panel", let id = m.string("id") { pending.resolve(id) }
                let cb = onMessage
                callbackQueue.async { cb?(m) }
            case .failure(let e):
                let cb = onLog
                callbackQueue.async { cb?("bad line from core: \(e)\n") }
            }
        }
    }

    private func terminated(_ p: Process) {
        guard p === process else { return }
        process = nil
        try? stdin?.close(); stdin = nil
        let denied = pending.denyAll()
        if !denied.isEmpty { let cb = onPendingDenied; callbackQueue.async { cb?(denied) } }
        if stopping { setState(.stopped); return }
        setState(.offline("core exited (status \(p.terminationStatus))"))
        restarts += 1
        scheduleRestart()
    }

    private func scheduleRestart() {
        // Stable for 30 s → start again quickly; otherwise back off up to 5 s so a crash loop can't spin.
        if Date().timeIntervalSince(startedAt) > 30 { backoff = 0.25 }
        let delay = backoff
        backoff = min(backoff * 2, 5)
        queue.asyncAfter(deadline: .now() + delay) { if !self.stopping { self.launch() } }
    }

    private func writeLocked(_ m: CoreMessage) {
        guard let h = stdin, let data = try? m.encoded() else { return }
        do { try h.write(contentsOf: data) } catch {
            let cb = onLog
            callbackQueue.async { cb?("write to core failed: \(error)\n") }
        }
    }
}
