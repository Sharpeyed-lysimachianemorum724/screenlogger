import Foundation
import ScreenlogCore

/// App-facing adapter for the shared assistant-host discovery policy.
enum AgentPresence {
    typealias Result = AssistantHostDiscovery.Result

    static func detect(_ target: AssistantIntegrationTarget) -> Result {
        AssistantHostDiscovery().detect(target)
    }
}
