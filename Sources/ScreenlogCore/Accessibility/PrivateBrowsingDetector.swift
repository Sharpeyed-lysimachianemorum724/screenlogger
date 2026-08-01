import Foundation

/// Heuristics for browser private / incognito windows (AX title + URL cues).
/// Used when 'Exclude Private Tabs' is on - skip storing those captures.
public enum PrivateBrowsingDetector {
    /// Returns true when window/title/URL signals a private browsing session.
    public static func looksPrivate(
        title: String?,
        url: String?,
        bundleID: String?
    ) -> Bool {
        let t = (title ?? "").lowercased()
        // Safari, Firefox, Chrome, Edge, Brave common chrome titles.
        if t.contains("private browsing")
            || t.contains("private window")
            || t.contains("incognito")
            || t.contains("inprivate")
        {
            return true
        }

        if let url, let lower = Optional(url.lowercased()) {
            if lower.hasPrefix("safari-private:")
                || lower.contains("://private/")
                || lower.hasPrefix("chrome://private")
                || lower.hasPrefix("edge://private")
            {
                return true
            }
        }

        // Bundle-specific title patterns that are not covered above.
        if let bid = bundleID?.lowercased() {
            if bid.contains("safari"), t.contains("private") { return true }
            if bid.contains("chrome") || bid.contains("brave") || bid.contains("edge"),
                t.contains("incognito") || t.contains("inprivate")
            {
                return true
            }
        }

        return false
    }
}
