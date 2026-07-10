import Foundation
import SwiftUI
import WatchConnectivity

@main
struct PopRocketWatchApp: App {
    @StateObject private var model = WatchDashboardModel()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(model)
                .task {
                    model.activate()
                }
        }
    }
}

struct WatchDashboardView: View {
    @EnvironmentObject private var model: WatchDashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = model.snapshot {
                    header(snapshot)
                    stats(snapshot)
                    monitors(snapshot.healthMonitors)
                    devices(snapshot.wolTargets)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "bolt.circle")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                        Text("No bridge")
                            .font(.headline)
                        Text("Open PopRocket on iPhone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func header(_ snapshot: WatchDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(snapshot.bridgeReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(snapshot.bridgeName ?? "PopRocket")
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(snapshot.bridgeStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.updatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func stats(_ snapshot: WatchDashboardSnapshot) -> some View {
        let downCount = snapshot.healthMonitors.filter { $0.status.lowercased() != "up" }.count
        return HStack(spacing: 8) {
            WatchMetricView(title: "Down", value: "\(downCount)", systemImage: "exclamationmark.triangle.fill")
            WatchMetricView(title: "Devices", value: "\(snapshot.wolTargets.count)", systemImage: "desktopcomputer")
        }
    }

    private func monitors(_ monitors: [WatchHealthMonitor]) -> some View {
        let priority = monitors
            .sorted { lhs, rhs in
                let lhsUp = lhs.status.lowercased() == "up"
                let rhsUp = rhs.status.lowercased() == "up"
                if lhsUp != rhsUp {
                    return !lhsUp
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(4)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Health")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(priority)) { monitor in
                HStack(spacing: 6) {
                    Image(systemName: monitor.status.lowercased() == "up" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(monitor.status.lowercased() == "up" ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(monitor.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(monitor.status.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func devices(_ targets: [WatchWOLTarget]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Devices")
                .font(.caption)
                .foregroundStyle(.secondary)
            if targets.isEmpty {
                Text("Pin wake targets on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(targets.prefix(4))) { target in
                    let state = model.wakeStates[target.id]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "power.circle.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(target.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                if let ipAddress = target.ipAddress, !ipAddress.isEmpty {
                                    Text(ipAddress)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            Button {
                                model.wake(target, bridgeID: model.snapshot?.bridgeID)
                            } label: {
                                if state?.running == true {
                                    ProgressView()
                                } else {
                                    Image(systemName: "power")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(state?.running == true)
                        }
                        if let state {
                            Text(state.message?.isEmpty == false ? state.message ?? state.status : state.status)
                                .font(.caption2)
                                .foregroundStyle(state.succeeded ? .green : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct WatchMetricView: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

final class WatchDashboardModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchDashboardSnapshot?
    @Published private(set) var wakeStates: [String: WatchWakeState] = [:]

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        if self.session !== session {
            self.session = session
            session.delegate = self
        }
        if session.activationState == .notActivated {
            session.activate()
        }
        apply(session.receivedApplicationContext)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func wake(_ target: WatchWOLTarget, bridgeID: String?) {
        guard let bridgeID, !bridgeID.isEmpty else {
            wakeStates[target.id] = WatchWakeState(status: "Unavailable", message: "Open PopRocket on iPhone", running: false, succeeded: false)
            return
        }
        activate()
        guard let session, session.activationState == .activated else {
            wakeStates[target.id] = WatchWakeState(status: "Unavailable", message: "iPhone unavailable", running: false, succeeded: false)
            return
        }
        wakeStates[target.id] = WatchWakeState(status: "Sending", message: nil, running: true, succeeded: false)
        session.sendMessage(
            [
                "type": "wake_wol",
                "bridge_id": bridgeID,
                "target_id": target.id
            ],
            replyHandler: { [weak self] response in
                DispatchQueue.main.async {
                    self?.wakeStates[target.id] = WatchWakeState(response: response)
                }
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.wakeStates[target.id] = WatchWakeState(
                        status: "Failed",
                        message: error.localizedDescription,
                        running: false,
                        succeeded: false
                    )
                }
            }
        )
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["dashboard_snapshot"] as? Data else {
            return
        }
        do {
            let decoded = try WatchDashboardSnapshot.decoder.decode(WatchDashboardSnapshot.self, from: data)
            DispatchQueue.main.async {
                self.snapshot = decoded
            }
        } catch {
            print("PopRocket watch decode failed: \(error)")
        }
    }
}

struct WatchWakeState: Equatable {
    let status: String
    let message: String?
    let running: Bool
    let succeeded: Bool

    init(status: String, message: String?, running: Bool, succeeded: Bool) {
        self.status = status
        self.message = message
        self.running = running
        self.succeeded = succeeded
    }

    init(response: [String: Any]) {
        let ok = response["ok"] as? Bool ?? false
        self.status = response["status"] as? String ?? (ok ? "Sent" : "Failed")
        self.message = response["message"] as? String
        self.running = false
        self.succeeded = ok
    }
}

struct WatchDashboardSnapshot: Codable, Equatable {
    let bridgeID: String?
    let bridgeName: String?
    let bridgeReachable: Bool
    let bridgeStatus: String
    let healthMonitors: [WatchHealthMonitor]
    let wolTargets: [WatchWOLTarget]
    let updatedAt: Date

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct WatchHealthMonitor: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let message: String?
    let responseTimeMS: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case message
        case responseTimeMS = "response_time_ms"
    }
}

struct WatchWOLTarget: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let ipAddress: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ipAddress = "ip_address"
    }
}
