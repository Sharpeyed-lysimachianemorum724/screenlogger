import Foundation

/// ScreenlogCore - local screen memory: capture, OCR, SQLite FTS, CLI bridge.
///
/// Links the Apple system frameworks used by Screenlogger (ScreenCaptureKit,
/// Vision/VisionKit, AVFoundation, VideoToolbox, Accessibility, SwiftUI stack, etc.).
/// Persistence uses system SQLite3 + FTS5 (not SQLCipher) per OSS design.
public enum ScreenlogCore {
    /// User-facing version shared by the app, framework, and both CLI builds.
    public static let version = ProductVersion.current.marketing
    public static let buildVersion = ProductVersion.current.build
    public static let productName = "Screenlogger"
}

private final class ScreenlogCoreBundleToken {}

private struct ProductVersion {
    let marketing: String
    let build: String

    static let current: ProductVersion = {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: ScreenlogCoreBundleToken.self)
        #endif

        if let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            isValid(marketing: marketing, build: build)
        {
            return ProductVersion(marketing: marketing, build: build)
        }

        let resourceURL =
            bundle.url(forResource: "ProductVersion", withExtension: "xcconfig")
            ?? bundle.resourceURL?.appendingPathComponent(
                "Resources/ProductVersion.xcconfig"
            )
        if let resourceURL,
            let contents = try? String(contentsOf: resourceURL, encoding: .utf8),
            let marketing = setting("MARKETING_VERSION", in: contents),
            let build = setting("CURRENT_PROJECT_VERSION", in: contents),
            isValid(marketing: marketing, build: build)
        {
            return ProductVersion(marketing: marketing, build: build)
        }

        return ProductVersion(marketing: "unknown", build: "unknown")
    }()

    private static func setting(_ name: String, in contents: String) -> String? {
        contents.split(whereSeparator: \Character.isNewline).lazy.compactMap { rawLine in
            let line =
                rawLine.split(separator: "//", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { return nil }
            let fields = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count == 2, fields[0] == name, !fields[1].isEmpty else { return nil }
            return fields[1]
        }.first
    }

    private static func isValid(marketing: String, build: String) -> Bool {
        marketing.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
            && build.range(of: #"^[1-9][0-9]*$"#, options: .regularExpression) != nil
    }
}
