import ScreenlogCore
import SwiftUI

struct AssistantIntegrationActionNoticeView: View {
    let notice: AssistantIntegrationActionNotice

    var body: some View {
        Label(notice.message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(foregroundColor)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notice.severity.accessibilityLabel)
            .accessibilityValue(notice.message)
    }

    private var systemImage: String {
        switch notice.severity {
        case .success:
            return "checkmark.circle.fill"
        case .information:
            return "info.circle"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var foregroundColor: Color {
        switch notice.severity {
        case .success:
            return SLDesign.success
        case .information:
            return .secondary
        case .failure:
            return .red
        }
    }
}
