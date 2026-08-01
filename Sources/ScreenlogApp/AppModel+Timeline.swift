import AppKit
import Foundation
import ScreenlogCore

/// Timeline navigation, replay, selected-frame extraction, and search handoff.
///
/// Image work is detached from the main actor; only immutable frame descriptors
/// cross the boundary and presentation state is committed back on MainActor.
@MainActor
extension AppModel {
    // MARK: - Timeline and replay

    /// Load recent Timeline content without coupling navigation errors to the
    /// capture engine's global diagnostics.
    func refreshTimeline(
        announceResult: Bool = false,
        selectRecentActivity: Bool = false
    ) async {
        let issue =
            selectRecentActivity
            ? TimelineIssue.showRecentActivity
            : TimelineIssue.refreshTimeline
        if timelineIssue == issue { timelineIssue = nil }
        dismissTimelineNotice()
        timelineLoadState = .loading
        guard let store else {
            timelineLoadState = .failed
            if libraryStartupIssue == nil { timelineIssue = issue }
            return
        }

        do {
            let libraryResultFrameID =
                !selectRecentActivity && timelineNavigationOrigin == .libraryResult
                ? selectedTimelineID
                : nil
            let loadedSession =
                !selectRecentActivity && libraryResultFrameID == nil
                ? selectedSession
                : nil
            let frames = try await store.readAsync { store in
                if let libraryResultFrameID {
                    return try store.timelineAround(
                        frameID: libraryResultFrameID,
                        before: 40,
                        after: 40
                    )
                    .sorted { $0.id < $1.id }
                }
                if let loadedSession {
                    return try store.timeline(session: loadedSession, limit: 500)
                        .sorted { $0.id < $1.id }
                }
                return try store.recentTimeline(limit: 100).sorted { $0.id < $1.id }
            }
            let previousSelection = selectedTimelineID
            if selectRecentActivity {
                let clearsSearchSessionScope = searchSessionScoped
                selectedSessionIndex = nil
                timelineNavigationOrigin = .direct
                searchSessionScoped = false
                if clearsSearchSessionScope {
                    startLibrarySearch()
                }
            }
            timeline = frames
            if let previousSelection,
                frames.contains(where: { $0.id == previousSelection })
            {
                selectedTimelineID = previousSelection
            } else {
                selectedTimelineID = frames.last?.id
            }
            timelineLoadState = .ready
            if loadedSession != nil {
                publishTimelineNotice(
                    .timelineLoaded(scope: .session, momentCount: frames.count),
                    announce: announceResult
                )
            } else {
                publishTimelineNotice(
                    .timelineLoaded(scope: .recent, momentCount: frames.count),
                    announce: announceResult
                )
            }
        } catch {
            timelineLoadState = .failed
            timelineIssue = issue
        }
    }

    /// Leave a selected recording session and return to the ordinary recent
    /// Timeline. This is a first-class user action, not an error-state escape.
    func showRecentTimeline() async {
        stopReplay()
        await refreshTimeline(
            announceResult: true,
            selectRecentActivity: true
        )
    }

    func dismissTimelineIssue() {
        if timelineLoadState == .failed {
            timelineLoadState = .ready
        }
        timelineIssue = nil
    }

    /// Retry the primary Timeline query even when the failure was restored from
    /// load state rather than an operation banner.
    func retryTimelineLoad() async {
        if timelineIssue != nil {
            await retryTimelineIssue()
        } else {
            await refreshTimeline(announceResult: true)
        }
    }

    /// Retry only the failed Timeline operation. Session and moment identities
    /// are resolved again so stale array indices or view closures are never used.
    func retryTimelineIssue() async {
        guard let issue = timelineIssue else { return }
        timelineIssue = nil

        switch issue {
        case .refreshSessions:
            await loadSessions()
        case .refreshTimeline:
            await refreshTimeline(announceResult: true)
        case .showRecentActivity:
            await refreshTimeline(
                announceResult: true,
                selectRecentActivity: true
            )
        case .reloadSession(let startMs):
            if let session = sessions.first(where: { $0.startMs == startMs }) {
                await loadSession(session)
                return
            }

            await loadSessions()
            guard timelineIssue == nil else { return }
            if let session = sessions.first(where: { $0.startMs == startMs }) {
                await loadSession(session)
            } else {
                // Retention may have removed this session while the banner was
                // visible. That is an expected state, not another error.
                await refreshTimeline(announceResult: false)
                if timelineIssue == nil {
                    publishTimelineNotice(.sessionUnavailable)
                }
            }
        case .reopenMoment(let frameID, let timestampMs):
            await jumpToFrame(id: frameID, timestampMs: timestampMs)
        }
    }

    /// Calendar days which contain at least part of a recorded session.
    ///
    /// Sessions normally begin and end on the same day, but expanding an
    /// overnight session here keeps day navigation honest around midnight.
    var timelineAvailableDays: [Date] {
        let calendar = Calendar.current
        var days = Set<Date>()
        for session in sessions {
            var day = calendar.startOfDay(
                for: Date(
                    timeIntervalSince1970: TimeInterval(session.startMs) / 1000
                ))
            let lastDay = calendar.startOfDay(
                for: Date(
                    timeIntervalSince1970: TimeInterval(session.endMs) / 1000
                ))
            while day <= lastDay {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days.sorted()
    }

    var selectedTimelineDay: Date? {
        guard let frame = selectedTimelineFrame else { return nil }
        return Calendar.current.startOfDay(
            for: Date(
                timeIntervalSince1970: TimeInterval(frame.timestampMs) / 1000
            ))
    }

    /// Sessions that overlap a calendar day, ordered from morning to evening.
    func timelineSessions(on day: Date) -> [SessionRow] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(end.timeIntervalSince1970 * 1000)
        return
            sessions
            .filter { $0.endMs >= startMs && $0.startMs < endMs }
            .sorted { $0.startMs < $1.startMs }
    }

    func canNavigateTimelineDay(by delta: Int) -> Bool {
        guard delta != 0, let current = selectedTimelineDay else { return false }
        if delta < 0 { return timelineAvailableDays.contains(where: { $0 < current }) }
        return timelineAvailableDays.contains(where: { $0 > current })
    }

    /// Move to the next recorded day, skipping calendar days with no captures.
    /// The previous-day action lands on that day's latest session; next-day lands
    /// on its first session, matching the direction in which the user is moving.
    func navigateTimelineDay(by delta: Int) async {
        guard delta != 0, let current = selectedTimelineDay else { return }
        let target: Date?
        if delta < 0 {
            target = timelineAvailableDays.last(where: { $0 < current })
        } else {
            target = timelineAvailableDays.first(where: { $0 > current })
        }
        guard let target else { return }
        await selectTimelineDay(target, preferLatestSession: delta < 0)
    }

    /// Open a recorded day at either its first or latest session.
    func selectTimelineDay(_ day: Date, preferLatestSession: Bool = true) async {
        let daySessions = timelineSessions(on: day)
        guard let session = preferLatestSession ? daySessions.last : daySessions.first else {
            publishTimelineNotice(.dayHasNoCaptures)
            return
        }
        await loadSession(session)
    }

    var selectedTimelineFrame: TimelineFrame? {
        guard let selectedTimelineID else { return timeline.first }
        guard let position = timelineNavigationIndex.position(of: selectedTimelineID),
            timeline.indices.contains(position)
        else {
            return timeline.first
        }
        return timeline[position]
    }

    /// Index of selection within current `timeline` (chronological after we normalize).
    var selectedTimelineIndex: Int? {
        guard let id = selectedTimelineID else { return nil }
        return timelineNavigationIndex.position(of: id)
    }

    var canStepBack: Bool {
        guard let i = selectedTimelineIndex else { return false }
        return i > 0
    }

    var canStepForward: Bool {
        guard let i = selectedTimelineIndex else { return false }
        return i + 1 < timeline.count
    }

    /// Select a timeline frame (loads still or video frame for replay stage).
    func selectTimelineFrame(id: Int64?) {
        selectedTimelineID = id
    }

    /// Decode nearby stills at a small bounded size without blocking timeline interaction.
    private func scheduleNeighborPrefetch(around id: Int64) {
        prefetchTask?.cancel()
        guard let idx = timelineNavigationIndex.position(of: id) else { return }
        let radius = TimelinePreviewPolicy.neighborRadius
        let neighbors = [idx - radius, idx + radius]
            .filter { $0 >= 0 && $0 < timeline.count }
            .map { timeline[$0] }
            .compactMap { frame -> (id: Int64, path: String)? in
                let key = previewCacheKey(
                    frameID: frame.id,
                    maxPixelSize: TimelinePreviewPolicy.selectedMaxPixelSize
                )
                guard previewCache.object(forKey: key as NSString) == nil,
                    let path = frame.imagePath,
                    !path.isEmpty
                else { return nil }
                return (frame.id, path)
            }
        guard !neighbors.isEmpty else { return }

        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await Task.sleep(
                    for: .milliseconds(TimelinePreviewPolicy.neighborPrefetchDelayMilliseconds)
                )
            } catch {
                return
            }
            // Promote the weak capture once. Capturing this immutable actor reference
            // in MainActor.run avoids sharing the mutable weak-capture storage.
            guard let model = self else { return }
            for neighbor in neighbors {
                guard !Task.isCancelled else { return }
                guard
                    let cgImage = FrameExtractor.previewCGImage(
                        atPath: neighbor.path,
                        maxPixelSize: TimelinePreviewPolicy.selectedMaxPixelSize
                    )
                else { continue }
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard model.selectedTimelineID == id else { return }
                    let key = model.previewCacheKey(
                        frameID: neighbor.id,
                        maxPixelSize: TimelinePreviewPolicy.selectedMaxPixelSize
                    )
                    guard model.previewCache.object(forKey: key as NSString) == nil else { return }
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    let image = NSImage(cgImage: cgImage, size: size)
                    model.previewCache.setObject(
                        image,
                        forKey: key as NSString,
                        cost: cgImage.bytesPerRow * cgImage.height
                    )
                }
            }
        }
    }

    func stepTimeline(by delta: Int) {
        guard !timeline.isEmpty else { return }
        normalizeTimelineChronologyIfNeeded()
        guard let current = selectedTimelineID,
            let idx = timelineNavigationIndex.position(of: current)
        else {
            selectedTimelineID = timeline.first?.id
            return
        }
        let next = idx + delta
        guard timeline.indices.contains(next) else {
            stopReplay()
            return
        }
        selectedTimelineID = timeline[next].id
    }

    func startReplay(intervalMs: UInt64 = 650) {
        stopReplay()
        isReplaying = true
        normalizeTimelineChronologyIfNeeded()
        if selectedTimelineID == nil {
            selectedTimelineID = timeline.first?.id
        }
        replayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
                guard let self, self.isReplaying else { break }
                await MainActor.run {
                    if self.canStepForward {
                        self.stepTimeline(by: 1)
                    } else {
                        self.stopReplay()
                    }
                }
            }
        }
    }

    func stopReplay() {
        isReplaying = false
        replayTask?.cancel()
        replayTask = nil
    }

    func toggleReplay() {
        if isReplaying { stopReplay() } else { startReplay() }
    }

    /// Timeline loads are normalized by their query paths. This guarded fallback
    /// preserves programmatic/test callers that provide an unordered window while
    /// avoiding a full sort on every steady-state navigation command.
    func normalizeTimelineChronologyIfNeeded() {
        guard !timelineNavigationIndex.isChronological else { return }
        timeline = timeline.sorted { $0.id < $1.id }
    }

    /// Open a search hit in the timeline viewer.
    func openSearchResult(_ result: FTSResult) {
        stopReplay()
        SearchWindowController.shared.hide()
        shellSearchMode = false
        // Highlight matching OCR on stage (Live Text style).
        stageHighlightTokens = lastParsedSearch.highlightTokens
        if stageHighlightTokens.isEmpty {
            // Fall back to raw query alnum tokens if operators stripped everything meaningful.
            stageHighlightTokens = SearchOperatorParser.parse(searchQuery).highlightTokens
        }
        showLiveText = true
        // Explicitly record the handoff and bring Timeline forward, including
        // when its retained native window is closed or minimized.
        timelineLoadState = .loading
        openMainShell(origin: .libraryResult)
        Task {
            await jumpToFrame(id: result.frameID, timestampMs: result.timestampMs)
        }
    }

    /// Return to the preserved Library query after inspecting a result.
    func returnToLibrary() {
        guard timelineNavigationOrigin == .libraryResult else { return }
        stopReplay()
        timelineNavigationOrigin = .direct
        shellSearchMode = true
        SearchWindowController.shared.show(model: self)
    }

    /// Small floating permissions helper (movable, closable - not always-on).
    func showPermissions(
        origin: CaptureSetupOrigin,
        preferredPermission: ScreenlogPermission? = nil
    ) {
        PermissionsHelperController.shared.show(
            model: self,
            origin: origin,
            preferredPermission: preferredPermission
        )
    }

    func hidePermissions() {
        PermissionsHelperController.shared.hide()
    }

    /// Load a window of frames around an id and select it for replay.
    func jumpToFrame(id: Int64, timestampMs: Int64? = nil) async {
        let issue = TimelineIssue.reopenMoment(frameID: id, timestampMs: timestampMs)
        if timelineIssue == issue { timelineIssue = nil }
        dismissTimelineNotice()
        timelineLoadState = .loading
        guard let store else {
            timelineLoadState = .failed
            if libraryStartupIssue == nil { timelineIssue = issue }
            return
        }
        do {
            let built = try await store.readAsync { s -> [TimelineFrame] in
                var window = try s.timelineAround(frameID: id, before: 40, after: 40)
                if let ts = timestampMs ?? window.first(where: { $0.id == id })?.timestampMs {
                    let expanded = try s.timelineExpand(
                        aroundTimestampMs: ts,
                        radiusMs: 60_000,
                        limit: 120
                    )
                    if expanded.count > window.count { window = expanded } else if window.isEmpty { window = expanded }
                }
                if window.isEmpty, let ts = timestampMs {
                    window = try s.timelineNear(timestampMs: ts, limit: 80)
                }
                if window.isEmpty {
                    return try s.recentTimeline(limit: 100).sorted { $0.id < $1.id }
                }
                return window.sorted { $0.id < $1.id }
            }
            timeline = built
            timelineLoadState = .ready
            let openedRequestedMoment = timeline.contains(where: { $0.id == id })
            let resolution: TimelineMomentNavigationResolution
            if openedRequestedMoment {
                selectedTimelineID = id
                resolution = .requestedMoment
            } else if let ts = timestampMs,
                let nearest = timeline.min(by: {
                    abs($0.timestampMs - ts) < abs($1.timestampMs - ts)
                })
            {
                selectedTimelineID = nearest.id
                resolution = .nearestAvailableMoment
            } else if let first = timeline.first {
                selectedTimelineID = first.id
                resolution = .recentActivity
            } else {
                selectedTimelineID = nil
                resolution = .unavailable
            }
            publishTimelineNotice(resolution.noticeEvent)
        } catch {
            timelineLoadState = .failed
            timelineIssue = issue
        }
    }

    /// Load still or decode compacted video for the selected frame (replay stage).
    func scheduleSelectedFrameExtract() {
        extractTask?.cancel()
        selectedFrameImage = nil
        selectedFrameExtracting = false
        selectedFramePreviewIssue = nil

        guard let id = selectedTimelineID,
            let store
        else { return }

        // Retention intentionally keeps text and provenance after removing
        // media. That is an unavailable preview, not a load failure to retry.
        if let position = timelineNavigationIndex.position(of: id),
            timeline.indices.contains(position),
            timeline[position].imagePath == nil,
            timeline[position].videoID == nil
        {
            return
        }

        scheduleNeighborPrefetch(around: id)

        // Memory cache hit - instant stage paint.
        let cacheKey = previewCacheKey(
            frameID: id,
            maxPixelSize: TimelinePreviewPolicy.selectedMaxPixelSize
        )
        if let cached = previewCache.object(forKey: cacheKey as NSString) {
            selectedFrameImage = cached
            return
        }

        selectedFrameExtracting = true
        extractTask = Task.detached(priority: .userInitiated) { [weak self] in
            // See neighbor prefetch above: nested sending closures capture an immutable
            // actor reference, never the mutable weak-capture slot itself.
            guard let model = self else { return }
            do {
                try await Task.sleep(
                    for: .milliseconds(TimelinePreviewPolicy.selectionDebounceMilliseconds)
                )
                let row = try await store.readAsync { try $0.frame(id: id) }
                guard let row else {
                    await MainActor.run {
                        guard model.selectedTimelineID == id else { return }
                        model.selectedFrameExtracting = false
                        model.selectedFramePreviewIssue = .momentMissing
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                let cgImage = try await FrameExtractor.previewCGImage(
                    forFrame: row,
                    store: store,
                    maxPixelSize: TimelinePreviewPolicy.selectedMaxPixelSize
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard model.selectedTimelineID == id else { return }
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    let image = NSImage(cgImage: cgImage, size: size)
                    model.previewCache.setObject(
                        image,
                        forKey: cacheKey as NSString,
                        cost: cgImage.bytesPerRow * cgImage.height
                    )
                    model.selectedFrameImage = image
                    model.selectedFrameExtracting = false
                    model.selectedFramePreviewIssue = nil
                }
            } catch is CancellationError {
                // A newer selection owns the presentation state.
            } catch {
                await MainActor.run {
                    guard model.selectedTimelineID == id else { return }
                    model.selectedFrameExtracting = false
                    model.selectedFramePreviewIssue = .mediaUnreadable
                }
            }
        }
    }

    /// Retry only the current moment's preview without refreshing sessions,
    /// capture state, or the rest of the Timeline.
    func retrySelectedFramePreview() {
        guard selectedTimelineID != nil else { return }
        scheduleSelectedFrameExtract()
    }

    private func previewCacheKey(frameID: Int64, maxPixelSize: Int) -> String {
        "\(frameID)|\(maxPixelSize)"
    }

}
