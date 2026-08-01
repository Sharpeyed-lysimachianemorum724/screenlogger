import Foundation
import OSLog

private let log = Logger(subsystem: "dev.screenlog", category: "xpc-host")

private final class XPCConnectionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false

    func finishOnce(_ body: () -> Void) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        body()
    }
}

/// App-side XPC server. Owns Store + RecordingEngine; CLI is a thin client.
public final class ScreenlogXPCHost: NSObject, ScreenlogDaemonProtocol, NSXPCListenerDelegate {
    public static let shared = ScreenlogXPCHost()

    private var listener: NSXPCListener?
    private let queue = DispatchQueue(label: "dev.screenlog.xpc-host", qos: .userInitiated)
    private var store: Store?
    private var root: URL?
    private var engineBox: RecordingEngineBox?
    private let preferences: UserDefaults
    private let connectionLock = NSLock()
    private let requestLock = NSLock()
    private let requestGroup = DispatchGroup()
    private var acceptingRequests = false
    private var storedConnectionCount = 0
    public var teamID: String?

    public private(set) var isRunning = false
    public var connectionCount: Int {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return storedConnectionCount
    }

    private override init() {
        self.preferences = ScreenlogProcessPreferences.current
        super.init()
    }

    init(preferences: UserDefaults) {
        self.preferences = preferences
        super.init()
    }

    public func start(store: Store, root: URL, engine: RecordingEngineBox) throws {
        self.store = store
        self.root = root
        self.engineBox = engine
        requestLock.withLock { acceptingRequests = true }

        // Anonymous listener + endpoint file (works unsigned for OSS).
        // Set SCREENLOG_XPC_MACH=1 for machServiceName when LaunchAgent is installed.
        let listener: NSXPCListener
        if ProcessInfo.processInfo.environment["SCREENLOG_XPC_MACH"] == "1" {
            listener = NSXPCListener(machServiceName: ScreenlogXPCServiceName)
        } else {
            listener = NSXPCListener.anonymous()
        }
        listener.delegate = self
        listener.resume()
        self.listener = listener
        isRunning = true

        try publish(endpoint: listener.endpoint, root: root)
        log.info("XPC host listening (anonymous endpoint published)")
    }

    public func stop() {
        requestLock.withLock { acceptingRequests = false }
        listener?.invalidate()
        listener = nil
        isRunning = false
        if let root {
            try? FileManager.default.removeItem(at: Self.endpointURL(root: root))
        }
        store = nil
        root = nil
        engineBox = nil
    }

    /// Refuse new work, drain accepted requests, then release Store. Unlike the
    /// immediate `stop()`, this is the replacement boundary used before SQLite
    /// is closed and the managed Library is renamed.
    public func stopAndDrain() async {
        requestLock.withLock { acceptingRequests = false }
        listener?.invalidate()
        listener = nil
        isRunning = false
        if let root { try? FileManager.default.removeItem(at: Self.endpointURL(root: root)) }
        await withCheckedContinuation { continuation in
            requestGroup.notify(queue: queue) {
                self.store = nil
                self.root = nil
                self.engineBox = nil
                continuation.resume()
            }
        }
    }

    public static func endpointURL(root: URL) -> URL {
        root.appendingPathComponent("xpc.endpoint", isDirectory: false)
    }

    private func publish(endpoint: NSXPCListenerEndpoint, root: URL) throws {
        try ScreenlogPaths.ensureDirectories(root: root)
        let url = Self.endpointURL(root: root)
        // Prefer secure coding; fall back if the system rejects endpoint secure archive.
        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(withRootObject: endpoint, requiringSecureCoding: true)
        } catch {
            log.error("secure archive of XPC endpoint failed: \(error.localizedDescription); retrying insecure")
            data = try NSKeyedArchiver.archivedData(withRootObject: endpoint, requiringSecureCoding: false)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        log.info("published XPC endpoint at \(url.path, privacy: .private(mask: .hash)) (\(data.count) bytes)")
    }

    // MARK: - Listener

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Prefer code-signing audit when team ID is known (signed builds).
        if let teamID,
            ProcessInfo.processInfo.environment["SCREENLOG_XPC_RELAXED"] != "1"
        {
            let req =
                "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
            newConnection.setCodeSigningRequirement(req)
        }

        newConnection.exportedInterface = NSXPCInterface(with: ScreenlogDaemonProtocol.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: ScreenlogClientProtocol.self)
        let lifetime = XPCConnectionLifetime()
        newConnection.invalidationHandler = { [weak self] in
            lifetime.finishOnce { self?.adjustConnectionCount(by: -1) }
        }
        newConnection.interruptionHandler = { [weak self] in
            log.error("XPC connection interrupted")
            lifetime.finishOnce { self?.adjustConnectionCount(by: -1) }
        }
        adjustConnectionCount(by: 1)
        newConnection.resume()
        return true
    }

    // MARK: - Protocol

    public func xpcPing(with reply: @escaping (String) -> Void) {
        reply("pong \(ScreenlogCore.version)")
    }

    public func xpcGetStatus(with reply: @escaping (Data?, String?) -> Void) {
        guard beginRequest() else {
            reply(nil, "store unavailable")
            return
        }
        Task {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else { throw StoreXPCError.unavailable }
                let perms = await PermissionsSnapshot.current()
                let engineState = await MainActor.run {
                    (
                        recording: RecordingEngine.shared.isRecording,
                        pauseReason: RecordingEngine.shared.pauseReason
                    )
                }
                let stats = try store.stats()
                let status = DaemonStatus(
                    version: ScreenlogCore.version,
                    recording: engineState.recording,
                    pauseReason: engineState.pauseReason,
                    connections: self.connectionCount,
                    totalFrames: stats.totalFrames,
                    unfinalizedFrames: stats.unfinalizedFrames,
                    minTimestampMs: stats.minTimestampMs,
                    maxTimestampMs: stats.maxTimestampMs,
                    screenRecording: perms.screenRecording,
                    accessibility: perms.accessibility,
                    dataRoot: self.root?.path ?? store.root.path
                )
                reply(try JSONEncoder().encode(status), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func xpcStartRecording(with reply: @escaping (Bool, String?) -> Void) {
        if let error = localToolAuthorizationError(for: .startRecording) {
            reply(false, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(false, "store unavailable")
            return
        }
        Task { @MainActor in
            defer { self.requestGroup.leave() }
            RecordingEngine.shared.start()
            let started = RecordingEngine.shared.isRecording
            reply(started, started ? nil : (RecordingEngine.shared.lastError ?? "recording did not start"))
        }
    }

    public func xpcStopRecording(with reply: @escaping (Bool, String?) -> Void) {
        if let error = localToolAuthorizationError(for: .stopRecording) {
            reply(false, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(false, "store unavailable")
            return
        }
        Task { @MainActor in
            defer { self.requestGroup.leave() }
            RecordingEngine.shared.stop()
            reply(true, nil)
        }
    }

    public func xpcCaptureOnce(with reply: @escaping (Int64, String?) -> Void) {
        if let error = localToolAuthorizationError(for: .captureOnce) {
            reply(-1, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(-1, "store unavailable")
            return
        }
        Task { @MainActor in
            defer { self.requestGroup.leave() }
            do {
                let id = try await RecordingEngine.shared.captureOneNow()
                reply(id, nil)
            } catch {
                reply(-1, error.localizedDescription)
            }
        }
    }

    public func xpcFTS(query: String, limit: Int, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .fts, query: query, limit: limit), reply: reply) else { return }
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.searchLibrary(query: query, limit: limit))
        }
    }

    public func xpcStats(with reply: @escaping (Data?, String?) -> Void) {
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.stats())
        }
    }

    public func xpcTopApplications(limit: Int, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .topApplications, limit: limit), reply: reply) else { return }
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.topApplications(limit: limit))
        }
    }

    public func xpcTopDomains(limit: Int, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .topDomains, limit: limit), reply: reply) else { return }
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.topDomains(limit: limit))
        }
    }

    public func xpcSessions(gapMinutes: Int, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .sessions, gapMinutes: gapMinutes), reply: reply) else { return }
        storeReply(reply) { store in
            let gap = Int64(max(1, gapMinutes)) * 60_000
            return try JSONEncoder().encode(try store.sessions(gapMs: gap))
        }
    }

    public func xpcSample(limit: Int, minSegLen: Int, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .sample, limit: limit, minSegLen: minSegLen), reply: reply) else { return }
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.sampleFrames(limit: limit, minSegLen: minSegLen))
        }
    }

    public func xpcFrame(id: Int64, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .frame, frameID: id), reply: reply) else { return }
        storeReply(reply) { store in
            guard let f = try store.frame(id: id) else { throw StoreXPCError.notFound }
            return try JSONEncoder().encode(f)
        }
    }

    public func xpcFrameAt(timestampMs: Int64, with reply: @escaping (Data?, String?) -> Void) {
        storeReply(reply) { store in
            guard let f = try store.frameNearest(timestampMs: timestampMs) else {
                throw StoreXPCError.notFound
            }
            return try JSONEncoder().encode(f)
        }
    }

    public func xpcOCRBoxes(frameID: Int64, with reply: @escaping (Data?, String?) -> Void) {
        guard validate(IPCRequest(cmd: .ocrBoxes, frameID: frameID), reply: reply) else { return }
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.ocrBoxes(frameID: frameID))
        }
    }

    public func xpcListApplications(with reply: @escaping (Data?, String?) -> Void) {
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.listApplications())
        }
    }

    public func xpcListDomains(with reply: @escaping (Data?, String?) -> Void) {
        storeReply(reply) { store in
            return try JSONEncoder().encode(try store.listDomains())
        }
    }

    public func xpcAXTree(frameID: Int64, with reply: @escaping (String?, String?) -> Void) {
        do {
            try IPCRequest(cmd: .axTree, frameID: frameID).validate()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(nil, "store unavailable")
            return
        }
        queue.async {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else {
                    reply(nil, "store unavailable")
                    return
                }
                let xml = try store.axTreeXML(frameID: frameID)
                reply(xml, xml == nil ? "no ax tree for frame" : nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func xpcExtractImage(
        frameID: Int64,
        timestampMs: Int64,
        outPath: String,
        preferBase64: Bool,
        with reply: @escaping (Data?, String?) -> Void
    ) {
        do {
            try IPCRequest(
                cmd: .extractImage,
                frameID: frameID > 0 ? frameID : nil,
                timestampMs: frameID > 0 ? nil : timestampMs,
                outPath: outPath,
                preferBase64: preferBase64
            ).validate()
        } catch {
            reply(nil, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(nil, "store unavailable")
            return
        }
        Task {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else {
                    reply(nil, StoreXPCError.unavailable.localizedDescription)
                    return
                }
                let frame: FrameRow
                if frameID > 0 {
                    guard let f = try store.frame(id: frameID) else {
                        throw StoreXPCError.notFound
                    }
                    frame = f
                } else {
                    guard let f = try store.frameNearest(timestampMs: timestampMs) else {
                        throw StoreXPCError.notFound
                    }
                    frame = f
                }

                let still = try await FrameExtractor.stillData(forFrame: frame, store: store)

                var writtenPath: String?
                if !outPath.isEmpty {
                    writtenPath = try Self.writeStillData(
                        still.data,
                        ext: still.fileExtension,
                        frame: frame,
                        outPath: outPath
                    )
                } else if !preferBase64 {
                    // Default: write under data root so CLI can open without base64 over XPC.
                    let root = self.root ?? store.root
                    let exportDir = root.appendingPathComponent("exports", isDirectory: true)
                    writtenPath = try Self.writeStillData(
                        still.data,
                        ext: still.fileExtension,
                        frame: frame,
                        outPath: exportDir.path
                    )
                }

                let result = ExtractImageResult(
                    frameID: frame.id,
                    timestampMs: frame.timestampMs,
                    path: writtenPath,
                    base64: preferBase64 ? still.data.base64EncodedString() : nil,
                    fileExtension: still.fileExtension,
                    byteCount: still.data.count,
                    source: still.source
                )
                reply(try JSONEncoder().encode(result), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func xpcCompact(with reply: @escaping (Int, String?) -> Void) {
        if let error = localToolAuthorizationError(for: .compact) {
            reply(0, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(0, "store unavailable")
            return
        }
        queue.async {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else {
                    reply(0, "store unavailable")
                    return
                }
                let n = try VideoCompactionService().compactIfNeeded(store: store)
                reply(n, nil)
            } catch {
                reply(0, error.localizedDescription)
            }
        }
    }

    public func xpcRunRetention(with reply: @escaping (String?, String?) -> Void) {
        if let error = localToolAuthorizationError(for: .retention) {
            reply(nil, error.localizedDescription)
            return
        }
        guard beginRequest() else {
            reply(nil, "store unavailable")
            return
        }
        queue.async {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else {
                    reply(nil, "store unavailable")
                    return
                }
                reply(try RetentionService().run(store: store), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    public func xpcPermissions(with reply: @escaping ([String: Bool]) -> Void) {
        Task {
            let p = await PermissionsSnapshot.current()
            reply([
                "screen_recording": p.screenRecording,
                "accessibility": p.accessibility,
            ])
        }
    }

    private func storeReply(_ reply: @escaping (Data?, String?) -> Void, _ body: @escaping (Store) throws -> Data) {
        guard beginRequest() else {
            reply(nil, "store unavailable")
            return
        }
        queue.async {
            defer { self.requestGroup.leave() }
            do {
                guard let store = self.store else {
                    reply(nil, "store unavailable")
                    return
                }
                reply(try body(store), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    private func validate(
        _ request: IPCRequest,
        reply: @escaping (Data?, String?) -> Void
    ) -> Bool {
        do {
            try request.validate()
            return true
        } catch {
            reply(nil, error.localizedDescription)
            return false
        }
    }

    private func localToolAuthorizationError(
        for command: IPCCommand
    ) -> LocalToolAccessError? {
        do {
            try LocalToolAccessPolicy(preferences: preferences).authorize(command)
            return nil
        } catch let error as LocalToolAccessError {
            return error
        } catch {
            assertionFailure("Unexpected local tool authorization error: \(error)")
            return .mutationAccessRequired
        }
    }

    private func adjustConnectionCount(by delta: Int) {
        connectionLock.lock()
        storedConnectionCount = max(0, storedConnectionCount + delta)
        connectionLock.unlock()
    }

    private func beginRequest() -> Bool {
        requestLock.withLock {
            guard acceptingRequests else { return false }
            requestGroup.enter()
            return true
        }
    }

    /// Write still bytes to a file path or into a directory; returns absolute path written.
    private static func writeStillData(
        _ data: Data,
        ext: String,
        frame: FrameRow,
        outPath: String
    ) throws -> String {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outPath, isDirectory: &isDir)
        let dest: URL
        if outPath.hasSuffix("/") || (exists && isDir.boolValue) {
            let name = String(format: "frame-%lld-%lld.%@", frame.id, frame.timestampMs, ext)
            dest = URL(fileURLWithPath: outPath, isDirectory: true).appendingPathComponent(name)
        } else {
            dest = URL(fileURLWithPath: outPath)
        }
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: dest, options: .atomic)
        return dest.path
    }
}

enum StoreXPCError: Error, LocalizedError {
    case notFound
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notFound: return "frame not found"
        case .unavailable: return "store unavailable"
        }
    }
}

/// Placeholder retained for API stability of `start(store:root:engine:)`.
public final class RecordingEngineBox: @unchecked Sendable {
    public init() {}
}
