import AppKit
import ScreenlogCore
import SwiftUI

// MARK: - Shared identity / time helpers

enum SLAppIdentity {
    private static let nameCache = NSCache<NSString, NSString>()
    private static let iconCache = NSCache<NSString, NSImage>()

    static func displayName(bundleID: String?) -> String {
        guard let bundleID, !bundleID.isEmpty else { return "Moment" }
        if let cached = nameCache.object(forKey: bundleID as NSString) {
            return cached as String
        }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
        } else {
            name = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        nameCache.setObject(name as NSString, forKey: bundleID as NSString)
        return name
    }

    static func icon(bundleID: String?, size: CGFloat = 28) -> NSImage {
        let key = "\(bundleID ?? "")-\(Int(size))" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image: NSImage
        if let bundleID, !bundleID.isEmpty,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            image = icon
        } else {
            let fallback =
                NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: size, height: size))
            fallback.size = NSSize(width: size, height: size)
            image = fallback
        }
        iconCache.setObject(image, forKey: key)
        return image
    }

    static func applicationURL(bundleID: String?) -> URL? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

// MARK: - App icon view

struct SLAppIconView: View {
    let bundleID: String?
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: SLAppIdentity.icon(bundleID: bundleID, size: size * 2))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Search

/// Dismissible structured-search chips (app: / site: / date: ...).
/// `compact` fits chips inside the single top search field.

struct SLFaviconView: View {
    let domain: String
    var size: CGFloat = 14
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                Image(nsImage: FaviconCache.shared.placeholder(for: domain, size: size))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .task(id: domain) {
            let resolved = await FaviconCache.shared.image(for: domain)
            image = resolved
        }
    }
}

// MARK: - Replay / History

struct FrameThumbnail: View {
    let path: String?
    var isCompacted: Bool = false
    var extractedImage: NSImage? = nil
    var extracting: Bool = false
    /// Fixed size when set; pass `nil` + outer frame for flexible grid cells.
    var width: CGFloat? = 64
    var height: CGFloat? = 40

    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let extractedImage {
                Image(nsImage: extractedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isCompacted {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                    if extracting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "film.stack")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if loadFailed || path == nil || path?.isEmpty == true {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: path == nil ? "film" : "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(6)
        .accessibilityHidden(true)
        .task(id: path) {
            loadedImage = nil
            loadFailed = false
            guard let path, !path.isEmpty, extractedImage == nil else { return }
            let img = await Task.detached(priority: .utility) {
                NSImage(contentsOfFile: path)
            }.value
            if let img {
                loadedImage = img
            } else {
                loadFailed = true
            }
        }
    }
}
