import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "dev.screenlog", category: "recording")

/// Retry policy for unexpected capture failures. Keeping this separate from the
/// loop makes the behavior deterministic and prevents a broken capture source
/// from being hammered at the user's normal capture interval.
struct RecordingCaptureBackoff: Equatable {
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval

    init(baseDelay: TimeInterval = 2, maximumDelay: TimeInterval = 60) {
        self.baseDelay = max(0.5, baseDelay)
        self.maximumDelay = max(self.baseDelay, maximumDelay)
    }

    func delay(afterConsecutiveFailures failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let exponent = min(failureCount - 1, 20)
        return min(maximumDelay, baseDelay * pow(2, Double(exponent)))
    }
}

// MARK: - Off-MainActor capture pipeline

/// Heavy capture work: ScreenCaptureKit stills, HEIC encode, Vision OCR, AX, SQLite writes.
/// Isolated from the UI so RecordingEngine's MainActor loop only hops back for published state.
private actor CapturePipeline {
    private let capture = ScreenCaptureService()
    private let differentialOCR = DifferentialOCRService()
    private let fullOCR = OCRService()
    private let browserURL = BrowserURLService()
    private let axExtractor = AXTreeExtractor()

    private var exclusions: ExclusionStore = .shared
    private var dataRoot: URL?

    var maxDimension: Int = 2_880
    var stillQuality: Double = 0.94
    var captureAXTree = true
    var captureBrowserURL = true
    var useDifferentialOCR = true
    /// Skip store when browser title/URL looks like private / incognito.
    var excludePrivateTabs = true
    /// Fail closed for supported browsers when their active domain is unknown.
    var pauseWhenBrowserAddressUnavailable = false

    struct CycleOutcome: Sendable {
        /// Frame id when stored; nil when skipped (exclusion).
        var frameID: Int64?
        var ocrReused: Bool
        var axNodes: Int
        var pauseReason: CapturePauseReason?
    }

    func configure(
        exclusions: ExclusionStore,
        dataRoot: URL?,
        maxDimension: Int,
        stillQuality: Double,
        captureAXTree: Bool? = nil,
        captureBrowserURL: Bool? = nil,
        useDifferentialOCR: Bool? = nil,
        excludePrivateTabs: Bool? = nil,
        pauseWhenBrowserAddressUnavailable: Bool? = nil
    ) {
        self.exclusions = exclusions
        self.dataRoot = dataRoot
        self.maxDimension = maxDimension
        capture.maxDimension = maxDimension
        self.stillQuality = min(1, max(0, stillQuality))
        capture.stillQuality = self.stillQuality
        if let captureAXTree { self.captureAXTree = captureAXTree }
        if let captureBrowserURL { self.captureBrowserURL = captureBrowserURL }
        if let useDifferentialOCR { self.useDifferentialOCR = useDifferentialOCR }
        if let excludePrivateTabs { self.excludePrivateTabs = excludePrivateTabs }
        if let pauseWhenBrowserAddressUnavailable {
            self.pauseWhenBrowserAddressUnavailable = pauseWhenBrowserAddressUnavailable
        }
    }

    func setExcludePrivateTabs(_ value: Bool) { excludePrivateTabs = value }
    func setPauseWhenBrowserAddressUnavailable(_ value: Bool) {
        pauseWhenBrowserAddressUnavailable = value
    }

    func applyCaptureQuality(maxDimension: Int, stillQuality: Double) {
        self.maxDimension = maxDimension
        capture.maxDimension = maxDimension
        self.stillQuality = min(1, max(0, stillQuality))
        capture.stillQuality = self.stillQuality
    }

    func setCaptureAXTree(_ value: Bool) { captureAXTree = value }
    func setCaptureBrowserURL(_ value: Bool) { captureBrowserURL = value }
    func setUseDifferentialOCR(_ value: Bool) { useDifferentialOCR = value }

    func applyCaptureFlags(ax: Bool, browserURL: Bool, differentialOCR: Bool) {
        captureAXTree = ax
        captureBrowserURL = browserURL
        useDifferentialOCR = differentialOCR
    }

    func applySnapshotPrefs(preferJPEG: Bool, ocrLanguages: [String], differentialOCR: Bool) {
        capture.preferJPEG = preferJPEG
        // Both OCR services must get languages: default capture uses DifferentialOCRService.
        // Parameter `differentialOCR` is a Bool flag - do not shadow the service property.
        fullOCR.recognitionLanguages = ocrLanguages
        self.differentialOCR.recognitionLanguages = ocrLanguages
        useDifferentialOCR = differentialOCR
    }

    func captureAndStore(store: Store) async throws -> CycleOutcome {
        // Cheap early exclusion by frontmost bundle (before ScreenCaptureKit work).
        let earlyBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if exclusions.isExcluded(bundleID: earlyBundle, domain: nil) {
            log.info("skip capture: excluded frontmost bundle \(earlyBundle ?? "?", privacy: .private(mask: .hash))")
            return CycleOutcome(
                frameID: nil,
                ocrReused: false,
                axNodes: 0,
                pauseReason: .excludedContent
            )
        }

        let bitmap = try await capture.captureOnce()

        var url: String?
        var domain: String?
        var title = bitmap.focusedTitle ?? ""
        let bundleID = bitmap.focusedBundleID ?? earlyBundle
        let displayName = bitmap.displayName
        let bundleVersion = bitmap.focusedBundleVersion ?? ""

        var browserAttribution: BrowserURLAttribution?
        if captureBrowserURL || pauseWhenBrowserAddressUnavailable {
            browserAttribution = browserURL.frontmostBrowserAttribution()
            // The foreground app can change while ScreenCaptureKit is working.
            // Never attach Browser B's address or title to Browser A's pixels.
            if let b = browserAttribution,
                b.observedBundleID == bundleID
            {
                if let u = b.url { url = u }
                if let d = b.domain { domain = d }
                if let t = b.title, !t.isEmpty { title = t }
            }
        }

        if exclusions.isExcluded(bundleID: bundleID, domain: domain) {
            log.info(
                "skip frame storage: excluded bundle=\(bundleID ?? "-", privacy: .private(mask: .hash)) domain=\(domain ?? "-", privacy: .private(mask: .hash))"
            )
            return CycleOutcome(
                frameID: nil,
                ocrReused: false,
                axNodes: 0,
                pauseReason: .excludedContent
            )
        }

        if excludePrivateTabs,
            PrivateBrowsingDetector.looksPrivate(title: title, url: url, bundleID: bundleID)
        {
            log.info(
                "skip private browsing tab bundle=\(bundleID ?? "-", privacy: .private(mask: .hash)) title=\(title, privacy: .private(mask: .hash))"
            )
            return CycleOutcome(
                frameID: nil,
                ocrReused: false,
                axNodes: 0,
                pauseReason: .privateBrowsing
            )
        }

        if BrowserCapturePrivacyPolicy.shouldPause(
            capturedBundleID: bundleID,
            attribution: browserAttribution,
            pauseWhenAddressUnavailable: pauseWhenBrowserAddressUnavailable
        ) {
            log.info(
                "skip browser frame: address unavailable or changed bundle=\(bundleID ?? "-", privacy: .private(mask: .hash))"
            )
            return CycleOutcome(
                frameID: nil,
                ocrReused: false,
                axNodes: 0,
                pauseReason: .browserAddressUnavailable
            )
        }

        // Full-screen OCR (differential or full), then attribute to FG app vs background windows.
        let rawOCR: OCRResult
        let reused: Bool
        if useDifferentialOCR {
            let diff = try await differentialOCR.recognize(pngData: bitmap.imageData)
            rawOCR = diff.result
            reused = diff.reused
        } else {
            rawOCR = try await fullOCR.recognize(pngData: bitmap.imageData)
            reused = false
        }

        let attributed = OCRService.attributeToForegroundBackground(
            result: rawOCR,
            imageWidth: bitmap.width,
            imageHeight: bitmap.height,
            captureDisplay: bitmap.captureDisplay,
            windowBounds: bitmap.windowBounds,
            foregroundBundleID: bundleID
        )

        // Attach browser URL to the frontmost window of the focused app for window_bound.url.
        var windowBounds = bitmap.windowBounds
        if let url, let bundleID {
            if let idx = windowBounds.indices
                .sorted(by: { windowBounds[$0].zOrder < windowBounds[$1].zOrder })
                .first(where: { windowBounds[$0].bundleID == bundleID })
            {
                windowBounds[idx].url = url
            }
        }

        let payload = CapturePayload(
            imageData: bitmap.imageData,
            timestampMs: bitmap.timestampMs,
            width: bitmap.width,
            height: bitmap.height,
            foreground: attributed.foreground,
            background: attributed.background,
            title: title,
            bundleID: bundleID,
            bundleVersion: bundleVersion,
            displayName: displayName,
            url: url,
            domain: domain,
            ocrBoxes: attributed.boxes,
            windowBounds: windowBounds,
            isInactive: false,
            imageFileExtension: bitmap.imageExtension,
            captureDisplay: bitmap.captureDisplay
        )

        // SQLite + filesystem write off MainActor.
        let frameID = try store.store(payload: payload)

        var axNodes = 0
        if captureAXTree, AccessibilityPermission.isTrusted(prompt: false) {
            if let snap = axExtractor.captureFocusedTree(
                expectedPID: bitmap.focusedProcessID
            ) {
                try store.storeAXSnapshot(frameID: frameID, snapshot: snap)
                axNodes = snap.nodeCount
            }
        }

        return CycleOutcome(frameID: frameID, ocrReused: reused, axNodes: axNodes, pauseReason: nil)
    }

    func runMaintenance(
        store: Store,
        retentionDays: Int,
        storageCapMB: Int64,
        runCompact: Bool = true,
        runRetention: Bool = true
    ) async {
        do {
            if runCompact {
                let compactor = VideoCompactionService()
                compactor.minBatchSize = 20
                let n = try compactor.compactIfNeeded(store: store)
                if n > 0 { log.info("auto-compacted \(n) frames") }
            }
            if runRetention {
                let policy = RetentionPolicy(
                    retentionDays: retentionDays,
                    storageCapMB: storageCapMB
                )
                _ = try RetentionService(policy: policy).run(store: store)
            }
        } catch {
            log.error("maintenance failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - UI-facing engine

/// Capture loop coordinator. **@MainActor only for published UI state**; heavy work runs in `CapturePipeline`.
@MainActor
public final class RecordingEngine: ObservableObject {
    public static let shared = RecordingEngine()

    @Published public private(set) var isRecording = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastFrameID: Int64?
    @Published public private(set) var framesCapturedSession: Int = 0
    @Published public private(set) var lastOCRReused = false
    @Published public private(set) var lastAXNodes: Int = 0
    @Published public private(set) var pausedForDisk = false
    /// Why a running capture loop is intentionally not saving frames.
    @Published public private(set) var pauseReason: CapturePauseReason?

    public var intervalSeconds: TimeInterval = 2.0
    public private(set) var maxDimension: Int = 2_880
    public private(set) var stillQuality: Double = 0.94
    public var retentionDays: Int = 30
    /// Soft cap on compacted video size (MB). 0 = disabled. Default 50 GB.
    public var storageCapMB: Int64 = 50_000
    /// Auto maintenance: run HEVC compaction in the background loop.
    public var autoCompactEnabled = true
    /// Auto maintenance: run age/size retention in the background loop.
    public var autoRetentionEnabled = true
    /// When true, skip capture cycles while the user is system-idle.
    public var pauseOnInactivity = true
    /// Idle seconds before Pause on Inactivity skips a cycle (default 5 minutes).
    public var inactivityThresholdSeconds: TimeInterval = 300
    /// When true, skip storing browser private / incognito tabs.
    public var excludePrivateTabs = true {
        didSet {
            let v = excludePrivateTabs
            Task { await pipeline.setExcludePrivateTabs(v) }
        }
    }
    /// Privacy-first optional behavior for website exclusions. When enabled,
    /// known browsers are not stored unless their active domain is available.
    public var pauseWhenBrowserAddressUnavailable = false {
        didSet {
            let value = pauseWhenBrowserAddressUnavailable
            Task { await pipeline.setPauseWhenBrowserAddressUnavailable(value) }
        }
    }
    public var captureAXTree = true {
        didSet {
            let v = captureAXTree
            Task { await pipeline.setCaptureAXTree(v) }
        }
    }
    public var captureBrowserURL = true {
        didSet {
            let v = captureBrowserURL
            Task { await pipeline.setCaptureBrowserURL(v) }
        }
    }
    public var useDifferentialOCR = true {
        didSet {
            let v = useDifferentialOCR
            Task { await pipeline.setUseDifferentialOCR(v) }
        }
    }
    /// Prefer JPEG stills over HEIC.
    public var preferJPEGStill = false
    /// Vision OCR language codes (empty = system).
    public var ocrLanguages: [String] = []
    /// Published when the capture loop is skipping due to idle (not disk).
    @Published public private(set) var pausedForInactivity = false

    private var task: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private let pipeline = CapturePipeline()
    private var store: Store?
    private var dataRoot: URL?
    private var exclusions: ExclusionStore = .shared

    public init() {}

    public func configure(
        store: Store,
        dataRoot: URL? = nil,
        exclusions: ExclusionStore? = nil
    ) {
        self.store = store
        self.dataRoot = dataRoot ?? store.root
        if let exclusions {
            self.exclusions = exclusions
        }
        let root = self.dataRoot
        let excl = self.exclusions
        let dim = maxDimension
        let quality = stillQuality
        let ax = captureAXTree
        let browser = captureBrowserURL
        let diff = useDifferentialOCR
        let jpeg = preferJPEGStill
        let langs = ocrLanguages
        Task {
            await pipeline.configure(
                exclusions: excl,
                dataRoot: root,
                maxDimension: dim,
                stillQuality: quality
            )
            await pipeline.applyCaptureFlags(ax: ax, browserURL: browser, differentialOCR: diff)
            await pipeline.applySnapshotPrefs(
                preferJPEG: jpeg,
                ocrLanguages: langs,
                differentialOCR: diff
            )
        }
    }

    /// Snapshot-class prefs (encoding, OCR languages, differential OCR).
    public func applySnapshotSettings(
        preferJPEG: Bool,
        ocrLanguages: [String],
        differentialOCR: Bool
    ) {
        preferJPEGStill = preferJPEG
        self.ocrLanguages = ocrLanguages
        useDifferentialOCR = differentialOCR
        let jpeg = preferJPEG
        let langs = ocrLanguages
        let diff = differentialOCR
        Task {
            await pipeline.applySnapshotPrefs(
                preferJPEG: jpeg,
                ocrLanguages: langs,
                differentialOCR: diff
            )
        }
    }

    /// Apply live settings from the app (interval, quality, retention, storage mode flags).
    public func applySettings(
        intervalSeconds: TimeInterval,
        maxDimension: Int,
        stillQuality: Double = 0.94,
        retentionDays: Int,
        storageCapMB: Int64 = 50_000,
        autoCompactEnabled: Bool = true,
        autoRetentionEnabled: Bool = true,
        pauseOnInactivity: Bool? = nil,
        inactivityThresholdSeconds: TimeInterval? = nil,
        excludePrivateTabs: Bool? = nil,
        pauseWhenBrowserAddressUnavailable: Bool? = nil
    ) {
        self.intervalSeconds = max(0.5, intervalSeconds)
        self.maxDimension = maxDimension == 0 ? 0 : max(480, maxDimension)
        self.stillQuality = min(1, max(0, stillQuality))
        self.retentionDays = max(1, retentionDays)
        self.storageCapMB = max(0, storageCapMB)
        self.autoCompactEnabled = autoCompactEnabled
        self.autoRetentionEnabled = autoRetentionEnabled
        if let pauseOnInactivity { self.pauseOnInactivity = pauseOnInactivity }
        if let inactivityThresholdSeconds {
            self.inactivityThresholdSeconds = max(30, inactivityThresholdSeconds)
        }
        if let excludePrivateTabs { self.excludePrivateTabs = excludePrivateTabs }
        if let pauseWhenBrowserAddressUnavailable {
            self.pauseWhenBrowserAddressUnavailable = pauseWhenBrowserAddressUnavailable
        }
        applyCaptureQualityToPipeline()
    }

    private func applyCaptureQualityToPipeline() {
        let dimension = maxDimension
        let quality = min(1, max(0, stillQuality))
        Task {
            await pipeline.applyCaptureQuality(
                maxDimension: dimension,
                stillQuality: quality
            )
        }
    }

    /// Apply a pure `StorageMaintenancePlan` (from `StorageManagementMode.maintenancePlan`).
    public func applyStoragePlan(_ plan: StorageMaintenancePlan) {
        retentionDays = plan.retentionDays
        storageCapMB = plan.storageCapMB
        autoCompactEnabled = plan.runCompact
        autoRetentionEnabled = plan.runRetention
    }

    /// Starts the capture loops and returns the authoritative resulting state.
    @discardableResult
    public func start() -> Bool {
        guard !isRecording else { return true }
        guard store != nil else {
            lastError = "Store not configured"
            isRecording = false
            return false
        }
        guard PermissionsSnapshot.currentFast().isCaptureReady else {
            lastError = "Screen Recording and Accessibility permissions are required"
            pauseReason = .permissionRequired
            isRecording = false
            return false
        }
        isRecording = true
        lastError = nil
        framesCapturedSession = 0
        pausedForDisk = false
        pausedForInactivity = false
        pauseReason = nil
        // Unstructured task: awaits on pipeline release MainActor during OCR/encode/DB.
        task = Task { [weak self] in await self?.runLoop() }
        maintenanceTask = Task { [weak self] in await self?.maintenanceLoop() }
        log.info("recording started interval=\(self.intervalSeconds)s")
        return isRecording
    }

    /// Stops capture and returns whether the engine reached the stopped state.
    @discardableResult
    public func stop() -> Bool {
        isRecording = false
        task?.cancel()
        task = nil
        maintenanceTask?.cancel()
        maintenanceTask = nil
        pausedForDisk = false
        pausedForInactivity = false
        pauseReason = nil
        log.info("recording stopped")
        return !isRecording
    }

    /// Stop and await both loops before a Library replacement closes SQLite.
    /// `stop()` is intentionally immediate for ordinary UI use; restore needs
    /// the stronger guarantee that no pipeline operation still holds `Store`.
    public func quiesceForLibraryReplacement() async {
        isRecording = false
        let captureTask = task
        let backgroundMaintenanceTask = maintenanceTask
        captureTask?.cancel()
        backgroundMaintenanceTask?.cancel()
        task = nil
        maintenanceTask = nil
        _ = await captureTask?.result
        _ = await backgroundMaintenanceTask?.result
        store = nil
        dataRoot = nil
        pausedForDisk = false
        pausedForInactivity = false
        pauseReason = nil
        log.info("recording quiesced for Library replacement")
    }

    public func captureOneNow() async throws -> Int64 {
        guard let store else { throw CaptureError.notAuthorized }
        guard PermissionsSnapshot.currentFast().isCaptureReady else {
            pauseReason = .permissionRequired
            throw CaptureError.notAuthorized
        }
        if let root = dataRoot ?? Optional(store.root),
            DiskSpaceMonitor.shared.shouldPauseRecording(dataRoot: root)
        {
            pausedForDisk = true
            pauseReason = .lowDiskSpace
            throw CaptureError.diskFull
        }
        // await pipeline to MainActor free during capture/OCR/store
        let outcome = try await pipeline.captureAndStore(store: store)
        if let reason = outcome.pauseReason {
            pauseReason = reason
            throw CaptureError.excluded
        }
        guard let id = outcome.frameID else {
            throw CaptureError.excluded
        }
        pausedForDisk = false
        pausedForInactivity = false
        pauseReason = nil
        lastFrameID = id
        framesCapturedSession += 1
        lastOCRReused = outcome.ocrReused
        lastAXNodes = outcome.axNodes
        lastError = nil
        return id
    }

    private func runLoop() async {
        let failureBackoff = RecordingCaptureBackoff()
        var consecutiveFailures = 0
        while !Task.isCancelled && isRecording {
            if !PermissionsSnapshot.currentFast().isCaptureReady {
                pausedForDisk = false
                pausedForInactivity = false
                pauseReason = .permissionRequired
                lastError = nil
                log.warning("capture paused: required macOS permissions are unavailable")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }

            // Disk check is cheap; keep on MainActor for published `pausedForDisk`.
            if let root = dataRoot ?? store?.root,
                DiskSpaceMonitor.shared.shouldPauseRecording(dataRoot: root)
            {
                pausedForDisk = true
                pausedForInactivity = false
                pauseReason = .lowDiskSpace
                lastError = nil
                log.warning("capture paused: free disk space below 1GB threshold")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                continue
            }
            if pausedForDisk {
                log.info("disk space OK; resuming capture loop")
            }
            pausedForDisk = false

            // Pause on Inactivity - skip store while user is idle (no keyboard/mouse).
            if pauseOnInactivity,
                SystemIdleMonitor.isIdle(thresholdSeconds: inactivityThresholdSeconds)
            {
                if !pausedForInactivity {
                    log.info(
                        "capture paused for inactivity (idle >= \(Int(self.inactivityThresholdSeconds))s)"
                    )
                }
                pausedForInactivity = true
                pauseReason = .inactivity
                lastError = nil
                let ns = UInt64(intervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                continue
            }
            if pausedForInactivity {
                log.info("user active again; resuming capture")
            }
            pausedForInactivity = false

            do {
                if let store {
                    // Suspension point: CapturePipeline runs OCR / HEIC / DB off MainActor.
                    let outcome = try await pipeline.captureAndStore(store: store)
                    if let id = outcome.frameID {
                        lastFrameID = id
                        framesCapturedSession += 1
                        lastOCRReused = outcome.ocrReused
                        lastAXNodes = outcome.axNodes
                    }
                    pauseReason = outcome.pauseReason
                    // A completed cycle (including an intentional exclusion) proves
                    // the capture pipeline is healthy and resets retry throttling.
                    consecutiveFailures = 0
                    lastError = nil
                    // A privacy pause is intentional and remains visible until
                    // the next cycle can save a frame.
                }
            } catch CaptureError.excluded {
                consecutiveFailures = 0
                lastError = nil
            } catch CaptureError.notAuthorized {
                consecutiveFailures = 0
                pauseReason = .permissionRequired
                lastError = nil
            } catch {
                consecutiveFailures += 1
                pauseReason = nil
                lastError = error.localizedDescription
                log.error("capture cycle failed: \(error.localizedDescription)")
            }
            let retryDelay = failureBackoff.delay(
                afterConsecutiveFailures: consecutiveFailures
            )
            let sleepSeconds = max(intervalSeconds, retryDelay)
            let ns = UInt64(sleepSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func maintenanceLoop() async {
        while !Task.isCancelled && isRecording {
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard let store, !Task.isCancelled else { continue }
            let days = retentionDays
            let cap = storageCapMB
            let compact = autoCompactEnabled
            let retain = autoRetentionEnabled
            // Off mode: skip both. Compress: compact only. Limit: both.
            if !compact && !retain { continue }
            await pipeline.runMaintenance(
                store: store,
                retentionDays: days,
                storageCapMB: cap,
                runCompact: compact,
                runRetention: retain
            )
        }
    }
}
