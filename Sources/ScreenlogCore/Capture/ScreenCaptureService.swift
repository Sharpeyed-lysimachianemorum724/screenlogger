import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import OSLog
import ScreenCaptureKit
import UniformTypeIdentifiers

private let log = Logger(subsystem: "dev.screenlog", category: "capture")

public struct CapturedBitmap: Sendable {
    /// Encoded still (HEIC preferred, JPEG fallback).
    public var imageData: Data
    /// File extension matching `imageData` (`heic` / `jpg` / rare `png`).
    public var imageExtension: String
    public var width: Int
    public var height: Int
    public var timestampMs: Int64
    public var windowBounds: [WindowBound]
    /// Process that was frontmost when ScreenCaptureKit completed the still.
    public var focusedProcessID: pid_t?
    public var focusedBundleID: String?
    public var focusedTitle: String?
    public var displayName: String?
    /// Bundle short version of frontmost app (feeds `application.version`).
    public var focusedBundleVersion: String?
    /// Display geometry in global CG points (x/y/width/height consistent).
    public var captureDisplay: CaptureDisplayRect?
    /// CGDirectDisplayID of the captured display (multi-monitor).
    public var displayID: UInt32?
}

/// ScreenCaptureKit snapshot capture enriched with CGWindowList metadata.
/// Safe to call from a background actor / queue - HEIC encode never requires MainActor.
public final class ScreenCaptureService: NSObject, @unchecked Sendable {
    /// Longest output edge in pixels. Zero preserves native display resolution.
    public var maxDimension: Int = 2_880
    public var maxWindows: Int = 60
    /// Lossy quality for HEIC / JPEG (0...1).
    public var stillQuality: Double = 0.94
    /// Prefer JPEG stills instead of HEIC (Snapshots to Encoding).
    public var preferJPEG: Bool = false
    /// When true (default), capture the display under the frontmost window (multi-monitor).
    public var preferFrontmostDisplay: Bool = true

    public override init() {
        super.init()
    }

    public func captureOnce() async throws -> CapturedBitmap {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = Self.selectDisplay(from: content, preferFrontmost: preferFrontmostDisplay) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = Self.backingScale(for: display)
        let outputSize = Self.outputSize(
            nativeWidth: display.width * scale,
            nativeHeight: display.height * scale,
            maxDimension: maxDimension
        )
        config.width = outputSize.width
        config.height = outputSize.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // HEIC/JPEG encode is CPU-bound - keep it off MainActor (caller should already be off-main).
        let quality = stillQuality
        let preferJPEG = preferJPEG
        let encoded: (data: Data, ext: String) = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    cont.resume(returning: try Self.encodeStill(image, quality: quality, preferJPEG: preferJPEG))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        // Prefer CGWindowList for z-order + bounds accuracy; enrich titles from SC when useful.
        let windows = Self.windowBoundsPreferringCG(scContent: content, limit: maxWindows)
        let focused = Self.focusedApp()
        let ts = Int64(Date().timeIntervalSince1970 * 1000)

        // display.frame is global CG points (origin top-left in window-server space).
        let frame = display.frame
        let displayRect = CaptureDisplayRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
        let displayID = UInt32(display.displayID)

        log.debug(
            "capture \(image.width)x\(image.height) ext=\(encoded.ext) windows=\(windows.count) display=\(Int(displayRect.width))x\(Int(displayRect.height)) id=\(displayID) bundle=\(focused.bundleID ?? "-", privacy: .private(mask: .hash))"
        )
        return CapturedBitmap(
            imageData: encoded.data,
            imageExtension: encoded.ext,
            width: image.width,
            height: image.height,
            timestampMs: ts,
            windowBounds: windows,
            focusedProcessID: focused.processID,
            focusedBundleID: focused.bundleID,
            focusedTitle: focused.title,
            displayName: focused.displayName,
            focusedBundleVersion: focused.version,
            captureDisplay: displayRect,
            displayID: displayID
        )
    }

    /// Applies a bounded longest-edge policy without ever upscaling. A zero
    /// limit is intentionally native, which is how the Ultra preset is stored.
    static func outputSize(
        nativeWidth: Int,
        nativeHeight: Int,
        maxDimension: Int
    ) -> (width: Int, height: Int) {
        let width = max(1, nativeWidth)
        let height = max(1, nativeHeight)
        let longestEdge = max(width, height)
        guard maxDimension > 0, longestEdge > maxDimension else {
            return (width, height)
        }
        let factor = Double(maxDimension) / Double(longestEdge)
        return (
            max(1, Int((Double(width) * factor).rounded())),
            max(1, Int((Double(height) * factor).rounded()))
        )
    }

    // MARK: - Display selection (multi-monitor)

    /// Prefer the display containing the frontmost app's key window; fall back to main / first.
    private static func selectDisplay(from content: SCShareableContent, preferFrontmost: Bool) -> SCDisplay? {
        let displays = content.displays
        guard !displays.isEmpty else { return nil }
        if !preferFrontmost {
            return primaryDisplay(in: displays) ?? displays.first
        }

        if let point = frontmostWindowCenter() {
            if let hit = displays.first(where: { $0.frame.contains(point) }) {
                return hit
            }
        }
        // Mouse location as secondary hint
        let mouse = NSEvent.mouseLocation
        // NSEvent.mouseLocation is bottom-left origin; convert to top-left global like SCDisplay.frame
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let topLeftY = Self.globalTopLeftY(for: screen)
            let cgPoint = CGPoint(x: mouse.x, y: topLeftY)
            if let hit = displays.first(where: { $0.frame.contains(cgPoint) }) {
                return hit
            }
            // Also try raw mouse if frames already match Cocoa coords on this OS
            if let hit = displays.first(where: { $0.frame.contains(mouse) }) {
                return hit
            }
        }
        return primaryDisplay(in: displays) ?? displays.first
    }

    private static func primaryDisplay(in displays: [SCDisplay]) -> SCDisplay? {
        let mainID = CGMainDisplayID()
        return displays.first(where: { $0.displayID == mainID }) ?? displays.first
    }

    private static func frontmostWindowCenter() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        for win in info {
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            guard let ownerPID = win[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard
                let boundsDict = win[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            if rect.width < 8 || rect.height < 8 { continue }
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return nil
    }

    /// Convert Cocoa bottom-left `screen.frame` maxY space to approximate top-left Y for a mouse point.
    private static func globalTopLeftY(for screen: NSScreen) -> CGFloat {
        // Cocoa: origin bottom-left of primary. CG window bounds: origin top-left of primary.
        // mouse.y is Cocoa; CG y ~ (primary height) - mouse.y ... but multi-monitor is messy.
        // Prefer matching SCDisplay.frame which uses CG coords - callers try both.
        let primaryH =
            NSScreen.screens.first(where: { $0 == NSScreen.main })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        let mouse = NSEvent.mouseLocation
        return primaryH - mouse.y
    }

    private static func backingScale(for display: SCDisplay) -> Int {
        // Match SCDisplay to NSScreen when possible.
        let id = CGDirectDisplayID(display.displayID)
        if let screen = NSScreen.screens.first(where: {
            guard let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(num.uint32Value) == id
        }) {
            return max(1, Int(screen.backingScaleFactor.rounded()))
        }
        return max(1, Int(NSScreen.main?.backingScaleFactor ?? 2))
    }

    // MARK: - Still encode (HEIC to JPEG fallback)

    private static func encodeStill(
        _ image: CGImage,
        quality: Double,
        preferJPEG: Bool = false
    ) throws -> (data: Data, ext: String) {
        if preferJPEG {
            if let jpeg = imageData(image, type: .jpeg, quality: quality) {
                return (jpeg, "jpg")
            }
        }
        if let heic = imageData(image, type: .heic, quality: quality) {
            return (heic, "heic")
        }
        log.info("HEIC encode failed; falling back to JPEG")
        if let jpeg = imageData(image, type: .jpeg, quality: quality) {
            return (jpeg, "jpg")
        }
        if let png = imageData(image, type: .png) {
            return (png, "png")
        }
        throw CaptureError.encodeFailed
    }

    private static func imageData(_ image: CGImage, type: UTType, quality: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData,
                type.identifier as CFString,
                1,
                nil
            )
        else { return nil }
        var props: [CFString: Any] = [:]
        if let quality {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Window bounds (CGWindowList primary)

    /// Z-ordered on-screen windows via `CGWindowListCopyWindowInfo` (front to back).
    /// Bounds come from CG (window-server accuracy). SCShareableContent fills missing titles / bundle IDs.
    private static func windowBoundsPreferringCG(scContent: SCShareableContent, limit: Int) -> [WindowBound] {
        let cg = cgWindowBounds(limit: limit)
        if !cg.isEmpty {
            return enrich(cgWindows: cg, with: scContent)
        }
        return scWindowBounds(scContent, limit: limit)
    }

    private static func cgWindowBounds(limit: Int) -> [WindowBound] {
        guard
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        var out: [WindowBound] = []
        out.reserveCapacity(min(limit, info.count))
        var z = 0
        for win in info {
            if out.count >= limit { break }

            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            // Keep normal windows (layer 0); skip menubar / dock chrome.
            if layer != 0 { continue }

            let alpha = win[kCGWindowAlpha as String] as? Double ?? 1
            if alpha <= 0.01 { continue }

            guard
                let boundsDict = win[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            let w = Int(rect.size.width.rounded())
            let h = Int(rect.size.height.rounded())
            if w < 8 || h < 8 { continue }

            let owner = win[kCGWindowOwnerName as String] as? String
            let title = win[kCGWindowName as String] as? String
            let pid = win[kCGWindowOwnerPID as String] as? pid_t
            var bundle: String?
            if let pid {
                bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }

            out.append(
                WindowBound(
                    bundleID: bundle,
                    windowTitle: (title?.isEmpty == false) ? title : owner,
                    x: Int(rect.origin.x.rounded()),
                    y: Int(rect.origin.y.rounded()),
                    width: w,
                    height: h,
                    windowLayer: layer,
                    zOrder: z
                )
            )
            z += 1
        }
        return out
    }

    private static func scWindowBounds(_ content: SCShareableContent, limit: Int) -> [WindowBound] {
        content.windows.prefix(limit).enumerated().map { idx, win in
            let frame = win.frame
            return WindowBound(
                bundleID: win.owningApplication?.bundleIdentifier,
                windowTitle: win.title,
                x: Int(frame.origin.x.rounded()),
                y: Int(frame.origin.y.rounded()),
                width: Int(frame.size.width.rounded()),
                height: Int(frame.size.height.rounded()),
                windowLayer: win.windowLayer,
                zOrder: idx
            )
        }
    }

    private static func enrich(cgWindows: [WindowBound], with content: SCShareableContent) -> [WindowBound] {
        let sc = content.windows
        guard !sc.isEmpty else { return cgWindows }
        return cgWindows.map { wb in
            var copy = wb
            if copy.bundleID != nil, let t = copy.windowTitle, !t.isEmpty { return copy }
            let match = sc.first { win in
                let f = win.frame
                let dx = abs(Int(f.origin.x.rounded()) - wb.x)
                let dy = abs(Int(f.origin.y.rounded()) - wb.y)
                let dw = abs(Int(f.size.width.rounded()) - wb.width)
                let dh = abs(Int(f.size.height.rounded()) - wb.height)
                return dx <= 4 && dy <= 4 && dw <= 8 && dh <= 8
            }
            if copy.bundleID == nil {
                copy.bundleID = match?.owningApplication?.bundleIdentifier
            }
            if copy.windowTitle == nil || copy.windowTitle?.isEmpty == true {
                copy.windowTitle = match?.title
            }
            return copy
        }
    }

    private static func focusedApp() -> (
        processID: pid_t?,
        bundleID: String?,
        title: String?,
        displayName: String?,
        version: String?
    ) {
        let app = NSWorkspace.shared.frontmostApplication
        var version: String?
        if let url = app?.bundleURL,
            let info = Bundle(url: url)?.infoDictionary
        {
            version =
                (info["CFBundleShortVersionString"] as? String)
                ?? (info["CFBundleVersion"] as? String)
        }
        return (
            app?.processIdentifier,
            app?.bundleIdentifier,
            app?.localizedName,
            app?.localizedName,
            version
        )
    }
}

public enum CaptureError: Error, CustomStringConvertible, LocalizedError {
    case noDisplay
    case encodeFailed
    case notAuthorized
    case diskFull
    case excluded

    public var description: String {
        switch self {
        case .noDisplay: return "No display available for capture"
        case .encodeFailed: return "Failed to encode still image (HEIC/JPEG)"
        case .notAuthorized: return "Screen Recording permission not granted"
        case .diskFull: return "Disk space critically low - capture paused"
        case .excluded: return "Current app or website is excluded from capture"
        }
    }

    public var errorDescription: String? { description }
}
