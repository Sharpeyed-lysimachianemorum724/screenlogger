import Foundation
import ScreenlogCore

extension ScreenlogCLIMain {
    static func usage(_ args: [String], client: ScreenlogXPCClient) throws {
        guard let sub = args.first else {
            throw CLIError.usage("usage time|top-applications|top-domains|sessions")
        }
        let rest = Array(args.dropFirst())
        switch sub {
        case "time":
            let s = try client.stats()
            print("frames: \(s.totalFrames)")
            print("approx_recorded_seconds: \(s.totalFrames * 2)")
            print("unfinalized: \(s.unfinalizedFrames)")
        case "top-applications", "top-apps":
            let limit = try intFlag(rest, name: "--limit", allowed: 1...500) ?? 20
            for item in try client.topApplications(limit: limit) {
                print("\(item.frameCount)\t\(item.identifier)\t\(item.displayName ?? "")")
            }
        case "top-domains":
            let limit = try intFlag(rest, name: "--limit", allowed: 1...500) ?? 20
            for item in try client.topDomains(limit: limit) {
                print("\(item.frameCount)\t\(item.identifier)")
            }
        case "sessions":
            let gap = try intFlag(rest, name: "--gap", allowed: 1...10_080) ?? 5
            for s in try client.sessions(gapMinutes: gap) {
                print("\(s.startMs)\t\(s.endMs)\tframes=\(s.frameCount)")
            }
        default:
            throw CLIError.unknown("usage \(sub)")
        }
    }

    static func list(_ args: [String], client: ScreenlogXPCClient) throws {
        switch args.first {
        case "applications", "apps":
            for a in try client.listApplications() {
                print("\(a.bundleID)\t\(a.displayName ?? "")")
            }
        case "domains":
            for d in try client.listDomains() {
                print(d.normalizedDomain)
            }
        default:
            throw CLIError.usage("list applications|domains")
        }
    }

    static func record(_ args: [String], client: ScreenlogXPCClient) throws {
        switch args.first {
        case "start":
            try client.startRecording()
            print("recording started")
        case "stop":
            try client.stopRecording()
            print("recording stopped")
        case "once":
            let id = try client.captureOnce()
            print("frame_id=\(id)")
        default:
            throw CLIError.usage("record start|stop|once")
        }
    }
}
