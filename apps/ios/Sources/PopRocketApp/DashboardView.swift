import PopRocketKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var showingPairing = false
    @State private var showingBridgeSettings = false
    @State private var monitorEditor: HealthMonitorEditorState?
    @State private var targetEditor: TargetEditorState?
    @State private var commandEditor: CommandEditorState?
    @State private var pendingMonitorDeletion: HealthMonitor?
    @State private var pendingTargetDeletion: WOLTarget?
    @State private var pendingCommandDeletion: CommandShortcut?
    @State private var deletingMonitorID: String?
    @State private var deletingTargetID: String?
    @State private var healthOperationMessage: String?
    @State private var healthOperationError: String?
    @State private var wakeOperationMessage: String?
    @State private var wakeOperationError: String?
    @State private var commandText = ""
    @FocusState private var focusedField: DashboardFocusField?

    var body: some View {
        NavigationStack {
            List {
                bridgeSection
                healthSection
                commandSection
                wakeSection
                if model.credential != nil {
                    activitySection
                }
                if !model.cards.isEmpty || model.statusSnapshotsErrorMessage != nil {
                    cardsSection
                }
            }
            .navigationTitle("PopRocket")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: Self.toolbarPlacement) {
                    Button {
                        showingBridgeSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Bridge Settings")

                    Button {
                        Task { await model.refreshFromUser() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }

                #if canImport(UIKit)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingPairing) {
                PairingView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingBridgeSettings) {
                BridgeSettingsView()
                    .environmentObject(model)
            }
            .sheet(item: $monitorEditor) { state in
                HealthMonitorEditorView(monitor: state.monitor)
                    .environmentObject(model)
            }
            .sheet(item: $targetEditor) { state in
                WOLTargetEditorView(target: state.target)
                    .environmentObject(model)
            }
            .sheet(item: $commandEditor) { state in
                CommandShortcutEditorView(state: state) {
                    if state.clearComposerOnSave {
                        commandText = ""
                    }
                    model.clearCommandResult()
                }
                    .environmentObject(model)
            }
            .confirmationDialog(
                "Delete Tile?",
                isPresented: Binding(
                    get: { pendingCommandDeletion != nil },
                    set: { if !$0 { pendingCommandDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingCommandDeletion {
                    Button("Delete", role: .destructive) {
                        model.deleteCommandShortcut(pendingCommandDeletion)
                        model.clearCommandResult()
                        self.pendingCommandDeletion = nil
                    }
                }
            } message: {
                if let pendingCommandDeletion {
                    Text(pendingCommandDeletion.name)
                }
            }
            .confirmationDialog(
                "Delete Monitor?",
                isPresented: Binding(
                    get: { pendingMonitorDeletion != nil },
                    set: { if !$0 { pendingMonitorDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingMonitorDeletion {
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteMonitor(pendingMonitorDeletion)
                            self.pendingMonitorDeletion = nil
                        }
                    }
                }
            } message: {
                if let pendingMonitorDeletion {
                    Text(pendingMonitorDeletion.name)
                }
            }
            .confirmationDialog(
                "Delete Device?",
                isPresented: Binding(
                    get: { pendingTargetDeletion != nil },
                    set: { if !$0 { pendingTargetDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingTargetDeletion {
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteTarget(pendingTargetDeletion)
                            self.pendingTargetDeletion = nil
                        }
                    }
                }
            } message: {
                if let pendingTargetDeletion {
                    Text(pendingTargetDeletion.name)
                }
            }
            .alert("PopRocket", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section("Health") {
            if model.credential == nil {
                ContentUnavailableView("Pair Bridge", systemImage: "waveform.path.ecg")
            } else {
                if deletingMonitorID != nil {
                    SectionStatusRow(
                        title: "Deleting Monitor",
                        message: healthOperationMessage ?? "Deleting monitor",
                        systemImage: "trash",
                        tint: .orange,
                        progress: true
                    )
                } else if let healthOperationMessage {
                    SectionStatusRow(
                        title: "Monitor Updated",
                        message: healthOperationMessage,
                        systemImage: "checkmark.circle",
                        tint: .green
                    )
                }
                if let healthOperationError {
                    SectionNoticeRow(
                        title: "Monitor Action Failed",
                        message: healthOperationError,
                        systemImage: "exclamationmark.triangle",
                        tint: .orange
                    )
                }

                if model.healthMonitors.isEmpty {
                    if let reason = model.healthMonitorControlsUnavailableReason {
                        SectionNoticeRow(
                            title: "Monitors Unavailable",
                            message: reason,
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                    } else {
                        ContentUnavailableView("No Monitors", systemImage: "waveform.path.ecg")
                    }
                } else {
                    if let message = model.healthMonitorsErrorMessage {
                        SectionNoticeRow(
                            title: "Monitor Refresh Failed",
                            message: message,
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                    } else if let reason = model.healthMonitorControlsUnavailableReason {
                        SectionNoticeRow(
                            title: "Monitor Management Unavailable",
                            message: reason,
                            systemImage: "lock",
                            tint: .secondary
                        )
                    }
                    HealthSummaryRow(
                        monitors: model.healthMonitors,
                        isLive: model.bridgeReachable,
                        lastUpdatedAt: model.healthMonitorsUpdatedAt
                    )
                    ForEach(model.healthMonitors) { monitor in
                        HealthMonitorRow(monitor: monitor, isLive: model.bridgeReachable)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if monitor.source == "user", model.healthMonitorControlsUnavailableReason == nil, deletingMonitorID == nil {
                                    Button {
                                        healthOperationMessage = nil
                                        healthOperationError = nil
                                        monitorEditor = HealthMonitorEditorState(monitor: monitor)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        pendingMonitorDeletion = monitor
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }

                Button {
                    healthOperationMessage = nil
                    healthOperationError = nil
                    monitorEditor = HealthMonitorEditorState(monitor: nil)
                } label: {
                    Label("Add Monitor", systemImage: "plus")
                }
                .disabled(model.healthMonitorControlsUnavailableReason != nil || deletingMonitorID != nil)
            }
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        Section("Bridge") {
            if let credential = model.credential {
                Button {
                    showingBridgeSettings = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(credential.bridgeName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(credential.directURLs.first?.absoluteString ?? credential.bridgeID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.bridgeHealthy ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(model.bridgeStatusText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(model.bridgeHealthy ? .green : .orange)
                            }
                            if let bridgeHealth = model.bridgeHealth {
                                HStack(spacing: 8) {
                                    Text("Uptime \(Self.shortDuration(seconds: bridgeHealth.uptimeSeconds))")
                                    Text("Checked \(bridgeHealth.serverTime, style: .relative)")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingPairing = true
                } label: {
                    Label("Pair Bridge", systemImage: "qrcode.viewfinder")
                }
            }
        }
    }

    @ViewBuilder
    private var wakeSection: some View {
        Section("Wake-on-LAN") {
            if model.credential == nil {
                ContentUnavailableView("Pair Bridge", systemImage: "bolt.badge.clock")
            } else {
                if deletingTargetID != nil {
                    SectionStatusRow(
                        title: "Deleting Device",
                        message: wakeOperationMessage ?? "Deleting device",
                        systemImage: "trash",
                        tint: .orange,
                        progress: true
                    )
                } else if let wakeOperationMessage {
                    SectionStatusRow(
                        title: "Device Updated",
                        message: wakeOperationMessage,
                        systemImage: "checkmark.circle",
                        tint: .green
                    )
                }
                if let wakeOperationError {
                    SectionNoticeRow(
                        title: "Device Action Failed",
                        message: wakeOperationError,
                        systemImage: "exclamationmark.triangle",
                        tint: .orange
                    )
                }

                if model.wolTargets.isEmpty {
                    if let reason = model.wolTargetManagementUnavailableReason ?? model.wolControlsUnavailableReason {
                        SectionNoticeRow(
                            title: "Devices Unavailable",
                            message: reason,
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                    } else {
                        ContentUnavailableView("No Targets", systemImage: "desktopcomputer")
                    }
                } else {
                    if let message = model.wolTargetsErrorMessage {
                        SectionNoticeRow(
                            title: "Device Refresh Failed",
                            message: message,
                            systemImage: "exclamationmark.triangle",
                            tint: .orange
                        )
                    } else if let reason = model.wolControlsUnavailableReason {
                        SectionNoticeRow(
                            title: model.bridgeReachable ? "Wake Unavailable" : "Last Known Devices",
                            message: staleAwareMessage(reason, lastUpdatedAt: model.wolTargetsUpdatedAt),
                            systemImage: model.bridgeReachable ? "bolt.slash" : "clock.badge.exclamationmark",
                            tint: .secondary
                        )
                    } else if let reason = model.wolTargetManagementUnavailableReason {
                        SectionNoticeRow(
                            title: "Device Management Unavailable",
                            message: reason,
                            systemImage: "lock",
                            tint: .secondary
                        )
                    }
                    ForEach(model.wolTargets) { target in
                        let wakeUnavailableReason = model.wolWakeUnavailableReason(for: target)
                        WOLTargetRow(
                            target: target,
                            state: model.wakeStates[target.id],
                            wakeEnabled: wakeUnavailableReason == nil && deletingTargetID != target.id,
                            disabledReason: deletingTargetID == target.id ? "Deleting device." : wakeUnavailableReason
                        ) {
                            Task { await model.wake(target) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if target.source != "config", model.wolTargetManagementUnavailableReason == nil, deletingTargetID == nil {
                                Button {
                                    wakeOperationMessage = nil
                                    wakeOperationError = nil
                                    targetEditor = TargetEditorState(target: target)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    pendingTargetDeletion = target
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Button {
                    wakeOperationMessage = nil
                    wakeOperationError = nil
                    targetEditor = TargetEditorState(target: nil)
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                .disabled(model.wolTargetManagementUnavailableReason != nil || deletingTargetID != nil)
            }
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        Section("Commands") {
            if model.credential == nil {
                ContentUnavailableView("Pair Bridge", systemImage: "terminal")
            } else {
                if !model.commandShortcuts.isEmpty {
                    CommandShortcutGrid(
                        shortcuts: model.commandShortcuts,
                        commandRunning: model.commandRunning,
                        runningShortcutID: model.runningCommandShortcutID,
                        commandEnabled: model.canRunCommands,
                        run: { shortcut in
                            focusedField = nil
                            Task { await model.runCommandShortcut(shortcut) }
                        },
                        edit: { shortcut in
                            focusedField = nil
                            commandEditor = CommandEditorState(
                                shortcut: shortcut,
                                initialCommand: shortcut.command,
                                clearComposerOnSave: false
                            )
                        },
                        delete: { shortcut in
                            focusedField = nil
                            pendingCommandDeletion = shortcut
                        }
                    )
                }

                if let reason = model.commandUnavailableReason {
                    CommandUnavailableRow(reason: reason)
                }

                CommandComposer(
                    commandText: Binding(
                        get: { commandText },
                        set: { newValue in
                            commandText = newValue
                            model.clearCommandResult()
                        }
                    ),
                    commandRunning: model.commandRunning,
                    commandEnabled: model.canRunCommands,
                    focusedField: $focusedField,
                    run: {
                        focusedField = nil
                        Task { await model.runCommand(commandText) }
                    },
                    save: {
                        focusedField = nil
                        commandEditor = CommandEditorState(
                            shortcut: nil,
                            initialCommand: commandText,
                            clearComposerOnSave: true
                        )
                    },
                    clear: {
                        focusedField = nil
                        commandText = ""
                        model.clearCommandResult()
                    }
                )

                if let status = model.commandStatusText {
                    CommandResultRow(
                        status: status,
                        output: model.commandOutputText,
                        succeeded: model.commandSucceeded
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var cardsSection: some View {
        Section("Status") {
            if let message = model.statusSnapshotsErrorMessage {
                SectionNoticeRow(
                    title: "Status Refresh Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            }
            ForEach(model.cards) { card in
                CardRow(card: card)
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section("Activity") {
            if let message = model.activityErrorMessage {
                SectionNoticeRow(
                    title: "Activity Refresh Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            } else if model.auditRecords.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "clock.arrow.circlepath")
            }
            if !model.auditRecords.isEmpty {
                ForEach(model.auditRecords) { record in
                    ActivityRow(record: record)
                }
            }
        }
    }

    private static var toolbarPlacement: ToolbarItemPlacement {
        #if canImport(UIKit)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    private func staleAwareMessage(_ message: String, lastUpdatedAt: Date?) -> String {
        guard !model.bridgeReachable, let lastUpdatedAt else {
            return message
        }
        let relative = Self.relativeFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date())
        return "\(message) Last updated \(relative)."
    }

    @MainActor
    private func deleteMonitor(_ monitor: HealthMonitor) async {
        deletingMonitorID = monitor.id
        healthOperationMessage = "Deleting \(monitor.name)"
        healthOperationError = nil
        let deleted = await model.deleteHealthMonitor(monitor)
        deletingMonitorID = nil
        if deleted {
            healthOperationMessage = "Deleted \(monitor.name)"
        } else {
            healthOperationMessage = nil
            healthOperationError = model.errorMessage ?? "Could not delete \(monitor.name)."
            model.errorMessage = nil
        }
    }

    @MainActor
    private func deleteTarget(_ target: WOLTarget) async {
        deletingTargetID = target.id
        wakeOperationMessage = "Deleting \(target.name)"
        wakeOperationError = nil
        let deleted = await model.deleteWOLTarget(target)
        deletingTargetID = nil
        if deleted {
            wakeOperationMessage = "Deleted \(target.name)"
        } else {
            wakeOperationMessage = nil
            wakeOperationError = model.errorMessage ?? "Could not delete \(target.name)."
            model.errorMessage = nil
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func shortDuration(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h \(minutes % 60)m"
        }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }
}

private enum DashboardFocusField: Hashable {
    case command
}

private enum CommandEditorFocusField: Hashable {
    case name
    case command
}

private enum HealthMonitorEditorFocusField: Hashable {
    case name
    case host
    case port
    case url
    case timeoutSeconds
}

private enum WOLTargetEditorFocusField: Hashable {
    case name
    case mac
    case ipAddress
    case broadcastIP
    case udpPort
}

private struct TargetEditorState: Identifiable {
    let id = UUID()
    let target: WOLTarget?
}

private struct HealthMonitorEditorState: Identifiable {
    let id = UUID()
    let monitor: HealthMonitor?
}

private struct CommandEditorState: Identifiable {
    let id = UUID()
    let shortcut: CommandShortcut?
    let initialCommand: String
    let clearComposerOnSave: Bool
}

private enum DashboardDesign {
    static let cornerRadius: CGFloat = 8
    static let fieldPadding: CGFloat = 12
    static let controlSpacing: CGFloat = 10
    static let tileMinimumHeight: CGFloat = 128
    static let panelFill = Color.secondary.opacity(0.08)
    static let panelStroke = Color.secondary.opacity(0.18)
    static let disabledOpacity = 0.55
}

private struct CardRow: View {
    let card: CardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.title)
                    .font(.headline)
                Spacer()
                StatusBadge(status: card.stale ? "stale" : card.status)
            }
            Text(card.value?.displayText ?? card.kind)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(card.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SectionNoticeRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SectionStatusRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var progress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if progress {
                ProgressView()
                    .frame(width: 24)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct FormValidationRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct FormErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct ActivityRow: View {
    let record: AuditRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                    .frame(width: 22)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: record.status)
            }
            HStack(spacing: 8) {
                Text(record.createdAt, style: .relative)
                Text(record.actorDeviceID)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let message = record.resultMessage, !message.isEmpty {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if let target = record.actionID.stripPrefix("wol:") {
            return "Wake \(target)"
        }
        if record.actionID == "command:run" {
            return "Command"
        }
        return record.actionID
    }

    private var iconName: String {
        switch record.status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed", "denied":
            return "exclamationmark.triangle.fill"
        default:
            return "clock"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case "completed":
            return .green
        case "failed", "denied":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct HealthSummaryRow: View {
    let monitors: [HealthMonitor]
    let isLive: Bool
    let lastUpdatedAt: Date?

    private var upCount: Int {
        monitors.filter { $0.status == "up" }.count
    }

    private var downCount: Int {
        monitors.filter { $0.status == "down" }.count
    }

    private var unknownCount: Int {
        max(0, monitors.count - upCount - downCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isLive, let lastUpdatedAt {
                    Text("Last updated \(lastUpdatedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        if !isLive {
            return "Last Known Health"
        }
        if downCount > 0 {
            return "\(downCount) Down"
        }
        if unknownCount > 0 {
            return "\(unknownCount) Unknown"
        }
        return "All Systems Up"
    }

    private var subtitle: String {
        let counts = "\(upCount) up / \(downCount) down / \(monitors.count) monitored"
        if !isLive {
            return "Bridge offline; showing \(counts.lowercased())"
        }
        if unknownCount > 0 {
            return "\(counts), \(unknownCount) unchecked"
        }
        return counts
    }

    private var iconName: String {
        if !isLive {
            return "clock.badge.exclamationmark"
        }
        if downCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if unknownCount > 0 {
            return "questionmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if !isLive || unknownCount > 0 {
            return .secondary
        }
        return downCount > 0 ? .orange : .green
    }
}

private struct HealthMonitorRow: View {
    let monitor: HealthMonitor
    let isLive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(monitor.name)
                        .font(.headline)
                    if let sourceLabel {
                        Text(sourceLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(endpointText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(stateDurationText)
                    if let responseTime = monitor.responseTimeMS, monitor.status == "up" {
                        Text("\(responseTime) ms")
                    }
                    if let checkedAt = monitor.checkedAt {
                        Text("Checked \(checkedAt, style: .relative)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if monitor.status == "down", let message = monitor.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            StatusBadge(status: isLive ? monitor.status : "stale")
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        guard isLive else {
            return .secondary
        }
        switch monitor.status {
        case "up":
            return .green
        case "down":
            return .orange
        default:
            return .secondary
        }
    }

    private var sourceLabel: String? {
        switch monitor.source {
        case "config":
            return "CONFIG"
        case "wol":
            return "DEVICE"
        default:
            return nil
        }
    }

    private var endpointText: String {
        if monitor.kind == "http", let url = monitor.url {
            return url
        }
        if let host = monitor.host {
            if let port = monitor.port {
                return "\(host):\(port)"
            }
            return host
        }
        return monitor.kind
    }

    private var stateDurationText: String {
        guard let changedAt = monitor.statusChangedAt else {
            return "Not checked"
        }
        let label = Self.statusLabel(monitor.status)
        let duration = Self.shortDuration(since: changedAt)
        if isLive {
            return "\(label) \(duration)"
        }
        return "Last \(label.lowercased()) \(duration)"
    }

    private static func statusLabel(_ status: String) -> String {
        switch status {
        case "up":
            return "Up"
        case "down":
            return "Down"
        default:
            return "Unknown"
        }
    }

    private static func shortDuration(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h \(minutes % 60)m"
        }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }
}

private struct WOLTargetRow: View {
    let target: WOLTarget
    let state: WOLActionState?
    let wakeEnabled: Bool
    let disabledReason: String?
    let wake: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(target.name)
                        .font(.headline)
                    if target.source == "config" {
                        Text("CONFIG")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(target.ipAddress ?? target.broadcastIP)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(target.mac)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let state {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.succeeded ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(state.status)
                        if let message = state.message, !message.isEmpty {
                            Text(message)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(state.succeeded ? .green : .orange)
                } else if let disabledReason, !wakeEnabled {
                    Label(disabledReason, systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(action: wake) {
                if state?.running == true {
                    ProgressView()
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "power")
                        .frame(width: 34, height: 34)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state?.running == true || !wakeEnabled)
            .accessibilityLabel("Wake \(target.name)")
        }
        .padding(.vertical, 4)
    }
}

private struct CommandComposer: View {
    @Binding var commandText: String
    let commandRunning: Bool
    let commandEnabled: Bool
    let focusedField: FocusState<DashboardFocusField?>.Binding
    let run: () -> Void
    let save: () -> Void
    let clear: () -> Void

    private var trimmedCommand: String {
        commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardDesign.controlSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !trimmedCommand.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear command")
                }
            }

            TextField("ssh lepton@pluto wake-neptune", text: $commandText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .commandInputTraits()
                .lineLimit(2...5)
                .focused(focusedField, equals: DashboardFocusField.command)
                .padding(DashboardDesign.fieldPadding)
                .dashboardPanel()

            HStack(spacing: DashboardDesign.controlSpacing) {
                Button(action: run) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                        Text(commandRunning ? "Running" : "Run")
                        if commandRunning {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(commandRunning || trimmedCommand.isEmpty || !commandEnabled)

                Button(action: save) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.square")
                        Text(trimmedCommand.isEmpty ? "New Tile" : "Save Tile")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CommandUnavailableRow: View {
    let reason: String

    var body: some View {
        Label(reason, systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

private struct CommandResultRow: View {
    let status: String
    let output: String?
    let succeeded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(succeeded ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(succeeded ? .green : .orange)
            }
            if let output, !output.isEmpty {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CommandShortcutGrid: View {
    let shortcuts: [CommandShortcut]
    let commandRunning: Bool
    let runningShortcutID: UUID?
    let commandEnabled: Bool
    let run: (CommandShortcut) -> Void
    let edit: (CommandShortcut) -> Void
    let delete: (CommandShortcut) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(shortcuts) { shortcut in
                CommandShortcutTile(
                    shortcut: shortcut,
                    commandRunning: commandRunning,
                    isRunning: runningShortcutID == shortcut.id,
                    commandEnabled: commandEnabled,
                    run: { run(shortcut) },
                    edit: { edit(shortcut) },
                    delete: { delete(shortcut) }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CommandShortcutTile: View {
    let shortcut: CommandShortcut
    let commandRunning: Bool
    let isRunning: Bool
    let commandEnabled: Bool
    let run: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: run) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: isRunning ? "hourglass" : "terminal")
                            .font(.headline)
                            .foregroundStyle(isRunning ? Color.orange : Color.blue)
                        Spacer(minLength: 32)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shortcut.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                        Text(shortcut.command)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let lastRunAt = shortcut.lastRunAt, let lastStatus = shortcut.lastStatus {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Self.statusColor(lastStatus))
                                    .frame(width: 6, height: 6)
                                Text("\(Self.displayStatus(lastStatus)) \(lastRunAt, style: .relative)")
                                    .lineLimit(1)
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Self.statusColor(lastStatus))
                            .accessibilityLabel("Last run \(Self.displayStatus(lastStatus))")
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: commandEnabled ? "play.fill" : "lock.fill")
                        }
                        Text(isRunning ? "Running" : (commandEnabled ? "Run" : "Unavailable"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRunning ? Color.orange : (commandRunning || !commandEnabled ? Color.secondary : Color.blue))
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: DashboardDesign.tileMinimumHeight, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .disabled(commandRunning || !commandEnabled)
            .accessibilityLabel("Run \(shortcut.name)")

            Menu {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .padding(6)
            .disabled(commandRunning)
            .accessibilityLabel("Command tile options")
        }
        .dashboardPanel()
        .opacity((commandRunning && !isRunning) || !commandEnabled ? DashboardDesign.disabledOpacity : 1)
    }

    private static func displayStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "completed":
            return "Ran"
        case "failed", "request failed":
            return "Failed"
        case "accepted":
            return "Accepted"
        default:
            return status
        }
    }

    private static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "accepted", "completed":
            return .green
        case "failed", "request failed", "denied":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct CommandShortcutEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let shortcut: CommandShortcut?
    let onSaved: () -> Void

    @State private var name: String
    @State private var command: String
    @State private var inlineError: String?
    @FocusState private var focusedField: CommandEditorFocusField?

    init(state: CommandEditorState, onSaved: @escaping () -> Void) {
        shortcut = state.shortcut
        self.onSaved = onSaved
        _name = State(initialValue: state.shortcut?.name ?? "")
        _command = State(initialValue: state.shortcut?.command ?? state.initialCommand)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tile") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .command
                        }
                    TextField("Command", text: $command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .commandInputTraits()
                        .lineLimit(1...5)
                        .focused($focusedField, equals: .command)
                }
                if let validationMessage {
                    FormValidationRow(message: validationMessage)
                }
                if let inlineError {
                    FormErrorRow(message: inlineError)
                }
            }
            .navigationTitle(shortcut == nil ? "Add Tile" : "Edit Tile")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
                inlineError = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        inlineError = nil
                        if model.saveCommandShortcut(
                            name: name,
                            command: command,
                            existingID: shortcut?.id
                        ) {
                            focusedField = nil
                            onSaved()
                            dismiss()
                        } else {
                            inlineError = model.errorMessage ?? "Could not save this command tile."
                            model.errorMessage = nil
                        }
                    }
                    .disabled(validationMessage != nil)
                }

                #if canImport(UIKit)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                #endif
            }
        }
    }

    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name this command tile."
        }
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the command this tile should run."
        }
        return nil
    }

    private var formFingerprint: String {
        "\(name)\n\(command)"
    }
}

private struct HealthMonitorEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let monitor: HealthMonitor?

    @State private var name: String
    @State private var kind: String
    @State private var host: String
    @State private var port: String
    @State private var url: String
    @State private var timeoutSeconds: String
    @State private var saving = false
    @State private var inlineError: String?
    @FocusState private var focusedField: HealthMonitorEditorFocusField?

    init(monitor: HealthMonitor?) {
        self.monitor = monitor
        _name = State(initialValue: monitor?.name ?? "")
        _kind = State(initialValue: monitor?.kind ?? "tcp")
        _host = State(initialValue: monitor?.host ?? "")
        _port = State(initialValue: monitor?.port.map(String.init) ?? "22")
        _url = State(initialValue: monitor?.url ?? "")
        _timeoutSeconds = State(initialValue: monitor.map { String($0.timeoutSeconds) } ?? "3")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Monitor") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = kind == "tcp" ? .host : .url
                        }
                    Picker("Type", selection: $kind) {
                        Text("TCP").tag("tcp")
                        Text("HTTP").tag("http")
                    }
                    .pickerStyle(.segmented)
                }

                if kind == "tcp" {
                    Section("TCP") {
                        TextField("Host", text: $host)
                            .commandInputTraits()
                            .focused($focusedField, equals: .host)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .port
                            }
                        TextField("Port", text: $port)
                            .numberInputTraits()
                            .focused($focusedField, equals: .port)
                    }
                } else {
                    Section("HTTP") {
                        TextField("URL", text: $url)
                            .commandInputTraits()
                            .focused($focusedField, equals: .url)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .timeoutSeconds
                            }
                    }
                }

                Section("Timing") {
                    TextField("Timeout Seconds", text: $timeoutSeconds)
                        .numberInputTraits()
                        .focused($focusedField, equals: .timeoutSeconds)
                }
                if let validationMessage {
                    FormValidationRow(message: validationMessage)
                }
                if let inlineError {
                    FormErrorRow(message: inlineError)
                }
            }
            .navigationTitle(monitor == nil ? "Add Monitor" : "Edit Monitor")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
                inlineError = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving" : "Save") {
                        Task {
                            inlineError = nil
                            saving = true
                            let saved = await model.saveHealthMonitor(
                                name: name,
                                kind: kind,
                                host: host,
                                port: port,
                                url: url,
                                timeoutSeconds: timeoutSeconds,
                                existingID: monitor?.id
                            )
                            saving = false
                            if saved {
                                focusedField = nil
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not save this monitor."
                                model.errorMessage = nil
                            }
                        }
                    }
                    .disabled(saving || validationMessage != nil)
                }

                #if canImport(UIKit)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                #endif
            }
        }
    }

    private var validationMessage: String? {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasName {
            return "Name this monitor."
        }
        let trimmedTimeout = timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timeout = Int(trimmedTimeout), (1...30).contains(timeout) else {
            return "Timeout must be between 1 and 30 seconds."
        }
        if kind == "tcp" {
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHost.isEmpty {
                return "Enter the host to check."
            }
            if !trimmedPort.isEmpty && !(Int(trimmedPort).map { (1...65535).contains($0) } ?? false) {
                return "Port must be between 1 and 65535."
            }
            return nil
        }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            return "Enter the HTTP URL to check."
        }
        if !Self.isValidHTTPURL(trimmedURL) {
            return "Enter a valid HTTP URL or hostname."
        }
        return nil
    }

    private var formFingerprint: String {
        "\(name)\n\(kind)\n\(host)\n\(port)\n\(url)\n\(timeoutSeconds)"
    }

    private static func isValidHTTPURL(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace) else {
            return false
        }
        let normalized = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: normalized) else {
            return false
        }
        return (components.scheme == "http" || components.scheme == "https") &&
            components.host?.isEmpty == false
    }
}

private struct WOLTargetEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let target: WOLTarget?

    @State private var name: String
    @State private var mac: String
    @State private var ipAddress: String
    @State private var broadcastIP: String
    @State private var udpPort: String
    @State private var saving = false
    @State private var inlineError: String?
    @FocusState private var focusedField: WOLTargetEditorFocusField?

    init(target: WOLTarget?) {
        self.target = target
        _name = State(initialValue: target?.name ?? "")
        _mac = State(initialValue: target?.mac ?? "")
        _ipAddress = State(initialValue: target?.ipAddress ?? "")
        _broadcastIP = State(initialValue: target?.broadcastIP ?? "")
        _udpPort = State(initialValue: target.map { String($0.udpPort) } ?? "9")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .mac
                        }
                    TextField("MAC Address", text: $mac)
                        .commandInputTraits()
                        .focused($focusedField, equals: .mac)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .ipAddress
                        }
                    TextField("IP Address", text: $ipAddress)
                        .commandInputTraits()
                        .focused($focusedField, equals: .ipAddress)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .broadcastIP
                        }
                }
                Section("Network") {
                    TextField("Broadcast IP", text: $broadcastIP)
                        .commandInputTraits()
                        .focused($focusedField, equals: .broadcastIP)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .udpPort
                        }
                    TextField("UDP Port", text: $udpPort)
                        .numberInputTraits()
                        .focused($focusedField, equals: .udpPort)
                }
                if let validationMessage {
                    FormValidationRow(message: validationMessage)
                }
                if let inlineError {
                    FormErrorRow(message: inlineError)
                }
            }
            .navigationTitle(target == nil ? "Add Device" : "Edit Device")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
                inlineError = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving" : "Save") {
                        Task {
                            inlineError = nil
                            saving = true
                            let saved = await model.saveWOLTarget(
                                name: name,
                                mac: mac,
                                ipAddress: ipAddress,
                                broadcastIP: broadcastIP,
                                udpPort: udpPort,
                                existingID: target?.id
                            )
                            saving = false
                            if saved {
                                focusedField = nil
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not save this device."
                                model.errorMessage = nil
                            }
                        }
                    }
                    .disabled(saving || validationMessage != nil)
                }

                #if canImport(UIKit)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                #endif
            }
        }
    }

    private var validationMessage: String? {
        let trimmedPort = udpPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMAC = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIPAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBroadcastIP = broadcastIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "Name this device."
        }
        if trimmedMAC.isEmpty {
            return "Enter the device MAC address."
        }
        if !Self.isValidMACAddress(trimmedMAC) {
            return "Enter a valid MAC address."
        }
        if trimmedIPAddress.isEmpty && trimmedBroadcastIP.isEmpty {
            return "Enter either an IP address or broadcast IP."
        }
        if !trimmedIPAddress.isEmpty && !Self.isValidIPv4Address(trimmedIPAddress) {
            return "IP address must be IPv4."
        }
        if !trimmedBroadcastIP.isEmpty && !Self.isValidIPv4Address(trimmedBroadcastIP) {
            return "Broadcast IP must be IPv4."
        }
        if !trimmedPort.isEmpty && !(Int(trimmedPort).map { (1...65535).contains($0) } ?? false) {
            return "UDP port must be between 1 and 65535."
        }
        return nil
    }

    private var formFingerprint: String {
        "\(name)\n\(mac)\n\(ipAddress)\n\(broadcastIP)\n\(udpPort)"
    }

    private static func isValidMACAddress(_ value: String) -> Bool {
        let separator: Character?
        if value.contains(":") {
            separator = ":"
        } else if value.contains("-") {
            separator = "-"
        } else {
            separator = nil
        }
        guard let separator else {
            return false
        }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let parts = value.split(separator: separator, omittingEmptySubsequences: false)
        return parts.count == 6 && parts.allSatisfy { part in
            part.count == 2 && part.unicodeScalars.allSatisfy { hex.contains($0) }
        }
    }

    private static func isValidIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(part) == String(number)
        }
    }
}

private extension View {
    func dashboardPanel() -> some View {
        background(DashboardDesign.panelFill)
            .overlay(
                RoundedRectangle(cornerRadius: DashboardDesign.cornerRadius, style: .continuous)
                    .stroke(DashboardDesign.panelStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DashboardDesign.cornerRadius, style: .continuous))
    }
}

#if canImport(UIKit)
private extension View {
    func commandInputTraits() -> some View {
        textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .autocorrectionDisabled()
    }

    func numberInputTraits() -> some View {
        textInputAutocapitalization(.never)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
    }
}
#else
private extension View {
    func commandInputTraits() -> some View {
        self
    }

    func numberInputTraits() -> some View {
        self
    }
}
#endif

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.16))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case "accepted", "fresh", "up", "completed":
            return .green
        case "down", "failed", "denied", "error":
            return .orange
        default:
            return .secondary
        }
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
