import AppKit
import ScreenlogCore
import SwiftUI

/// A stable visual identity for every assistant connection. Installed macOS
/// apps keep their native icon; CLI-only products use their recognizable mark
/// in the same compact macOS-style tile.
struct AssistantIntegrationIcon: View {
    let target: AssistantIntegrationTarget
    let applicationURL: URL?

    var body: some View {
        Group {
            if let applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(target.integrationIconBackground)

                    Image(target.integrationIconAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(target == .openclaw ? 3.5 : 5.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 0.75, y: 0.5)
        .accessibilityHidden(true)
    }
}

extension AssistantIntegrationTarget {
    fileprivate var integrationIconAssetName: String {
        switch self {
        case .claude: return "AssistantClaude"
        case .cursor: return "AssistantCursor"
        case .codex: return "AssistantCodex"
        case .grok: return "AssistantGrok"
        case .openclaw: return "AssistantOpenClaw"
        }
    }

    fileprivate var integrationIconBackground: Color {
        switch self {
        case .claude:
            return Color(red: 0.85, green: 0.42, blue: 0.29)
        case .cursor:
            return Color(red: 0.08, green: 0.08, blue: 0.08)
        case .codex:
            return Color(red: 0.10, green: 0.11, blue: 0.12)
        case .grok:
            return Color(red: 0.04, green: 0.05, blue: 0.06)
        case .openclaw:
            return Color(red: 0.03, green: 0.05, blue: 0.09)
        }
    }
}
