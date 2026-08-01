import AppKit
import ApplicationServices
import Foundation
import OSLog

private let log = Logger(subsystem: "dev.screenlog", category: "ax")

public struct AXTreeSnapshot: Sendable {
    public var xml: String
    public var nodeCount: Int
    public var bundleID: String?
    public var applicationName: String?
    public var pid: pid_t
    public var isPartial: Bool
    /// Snapshot extraction mode (for example `xml_full` or `unknown`).
    public var extractionMode: String

    public init(
        xml: String,
        nodeCount: Int,
        bundleID: String? = nil,
        applicationName: String? = nil,
        pid: pid_t,
        isPartial: Bool,
        extractionMode: String = "xml_full"
    ) {
        self.xml = xml
        self.nodeCount = nodeCount
        self.bundleID = bundleID
        self.applicationName = applicationName
        self.pid = pid
        self.isPartial = isPartial
        self.extractionMode = extractionMode
    }
}

/// Walks the focused app accessibility tree into compact, assistant-friendly XML.
public final class AXTreeExtractor: @unchecked Sendable {
    public var maxDepth: Int = 12
    public var maxNodes: Int = 2_500

    public init() {}

    public func captureFocusedTree(expectedPID: pid_t? = nil) -> AXTreeSnapshot? {
        guard AccessibilityPermission.isTrusted(prompt: false) else {
            log.debug("AX not trusted")
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appStatus == .success,
            let focusedApp,
            let appEl = Self.accessibilityElement(from: focusedApp)
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(appEl, &pid) == .success, pid > 0 else { return nil }
        guard
            Self.shouldInspect(
                focusedPID: pid,
                expectedPID: expectedPID,
                currentProcessID: getpid()
            )
        else {
            log.debug("skip AX tree because the focused process is self or changed after capture")
            return nil
        }

        let nsApp = NSRunningApplication(processIdentifier: pid)
        let bundleID = nsApp?.bundleIdentifier
        let appName = nsApp?.localizedName ?? stringAttr(appEl, kAXTitleAttribute as String)

        var nodeCount = 0
        var isPartial = false
        let body = serialize(element: appEl, depth: 0, nodeCount: &nodeCount, isPartial: &isPartial)
        let xml = """
            <AccessibilityTree bundle="\(escape(bundleID ?? ""))" app="\(escape(appName ?? ""))" pid="\(pid)" nodes="\(nodeCount)" partial="\(isPartial)">
            \(body)
            </AccessibilityTree>
            """
        return AXTreeSnapshot(
            xml: xml,
            nodeCount: nodeCount,
            bundleID: bundleID,
            applicationName: appName,
            pid: pid,
            isPartial: isPartial,
            extractionMode: "xml_full"
        )
    }

    private func serialize(element: AXUIElement, depth: Int, nodeCount: inout Int, isPartial: inout Bool) -> String {
        if depth > maxDepth || nodeCount >= maxNodes {
            isPartial = true
            return ""
        }
        nodeCount += 1
        let role = stringAttr(element, kAXRoleAttribute as String) ?? "Unknown"
        let title = stringAttr(element, kAXTitleAttribute as String)
        let value = stringAttr(element, kAXValueAttribute as String)
        let desc = stringAttr(element, kAXDescriptionAttribute as String)
        let ident = stringAttr(element, kAXIdentifierAttribute as String)

        var attrs = "role=\"\(escape(role))\""
        if let title, !title.isEmpty { attrs += " title=\"\(escape(title))\"" }
        if let value, !value.isEmpty { attrs += " value=\"\(escape(String(value.prefix(200))))\"" }
        if let desc, !desc.isEmpty { attrs += " description=\"\(escape(String(desc.prefix(120))))\"" }
        if let ident, !ident.isEmpty { attrs += " id=\"\(escape(ident))\"" }
        if let frame = frameAttr(element) {
            attrs +=
                " x=\"\(Int(frame.origin.x))\" y=\"\(Int(frame.origin.y))\" w=\"\(Int(frame.size.width))\" h=\"\(Int(frame.size.height))\""
        }

        var childrenXML = ""
        if let children = copyChildren(element) {
            for child in children {
                if nodeCount >= maxNodes {
                    isPartial = true
                    break
                }
                childrenXML += serialize(element: child, depth: depth + 1, nodeCount: &nodeCount, isPartial: &isPartial)
            }
        }
        if childrenXML.isEmpty {
            return String(repeating: "  ", count: depth) + "<Node \(attrs) />\n"
        }
        return String(repeating: "  ", count: depth) + "<Node \(attrs)>\n" + childrenXML + String(repeating: "  ", count: depth)
            + "</Node>\n"
    }

    private func copyChildren(_ el: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        let st = AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref)
        guard st == .success, let arr = ref as? [AXUIElement] else { return nil }
        return arr
    }

    private func stringAttr(_ el: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        let st = AXUIElementCopyAttributeValue(el, name as CFString, &ref)
        guard st == .success, let ref else { return nil }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }

    private func frameAttr(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let posRef, let sizeRef
        else { return nil }
        guard let point = Self.point(from: posRef),
            let size = Self.size(from: sizeRef),
            Self.isSafeCoordinate(point.x),
            Self.isSafeCoordinate(point.y),
            Self.isSafeDimension(size.width),
            Self.isSafeDimension(size.height)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// Accessibility APIs return untyped Core Foundation values. Check the
    /// runtime type before bridging so a malformed AX response cannot crash
    /// the capture loop.
    static func accessibilityElement(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func point(from value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(from value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Never walk Screenlogger's own AppKit accessibility tree from the
    /// background capture actor. In-process AX queries can execute AppKit view
    /// accessors on the calling worker and trigger framework assertions.
    /// Matching the captured PID also prevents a focus change from attaching a
    /// different application's tree to the stored screenshot.
    static func shouldInspect(
        focusedPID: pid_t,
        expectedPID: pid_t?,
        currentProcessID: pid_t
    ) -> Bool {
        guard focusedPID > 0, focusedPID != currentProcessID else { return false }
        return expectedPID.map { $0 == focusedPID } ?? true
    }

    private static func isSafeCoordinate(_ value: CGFloat) -> Bool {
        value.isFinite && abs(value) <= CGFloat(Int.max)
    }

    private static func isSafeDimension(_ value: CGFloat) -> Bool {
        value.isFinite && value >= 0 && value <= CGFloat(Int.max)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
