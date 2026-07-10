import PopRocketKit
import SwiftUI
#if os(iOS)
import UIKit
import UserNotifications
#endif

enum BridgeSettingsContentMode: Equatable {
    case all
    case bridges
    case settings
}

private enum BridgeSettingsPane: String, CaseIterable, Identifiable {
    case bridges
    case widgets
    case notifications
    case feedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bridges:
            return "Bridges"
        case .widgets:
            return "Widgets"
        case .notifications:
            return "Alerts"
        case .feedback:
            return "Feedback"
        }
    }

    var systemImage: String {
        switch self {
        case .bridges:
            return "antenna.radiowaves.left.and.right"
        case .widgets:
            return "square.grid.2x2"
        case .notifications:
            return "bell.badge"
        case .feedback:
            return "waveform.path"
        }
    }
}

struct BridgeSettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let showsDoneButton: Bool
    let mode: BridgeSettingsContentMode
    @State private var showingPairing = false
    @State private var pendingRemoval: BridgeRemoval?
    @State private var renameTarget: BridgeRename?
    @State private var selectingBridgeID: String?
    @State private var reconnectingBridgeID: String?
    @State private var removingBridgeID: String?
    @State private var statusMessage: String?
    @State private var inlineError: String?
    @State private var selectedPane: BridgeSettingsPane = .bridges
    @State private var notificationPermissionState: NotificationPermissionState = .unavailable
    @AppStorage(AppFeedback.PreferenceKey.hapticsEnabled) private var hapticsEnabled = AppFeedback.defaultHapticsEnabled
    @AppStorage(AppFeedback.PreferenceKey.tonesEnabled) private var tonesEnabled = AppFeedback.defaultTonesEnabled

    init(showsDoneButton: Bool = true, mode: BridgeSettingsContentMode = .all) {
        self.showsDoneButton = showsDoneButton
        self.mode = mode
    }

    var body: some View {
        Group {
            if showsDoneButton {
                NavigationStack {
                    bridgeSettingsContent
                        .navigationTitle(navigationTitle)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    dismiss()
                                }
                            }
                        }
                }
            } else {
                bridgeSettingsContent
            }
        }
        .sheet(isPresented: $showingPairing) {
            PairingView()
                .environmentObject(model)
        }
        .sheet(item: $renameTarget) { rename in
            BridgeNameEditorView(bridge: rename.bridge)
                .environmentObject(model)
        }
        .alert(item: $pendingRemoval) { removal in
            Alert(
                title: Text("Remove Bridge?"),
                message: Text(removal.bridge.bridgeName),
                primaryButton: .destructive(Text("Remove")) {
                    remove(removal.bridge)
                },
                secondaryButton: .cancel()
            )
        }
        .task {
            await refreshNotificationPermissionState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshNotificationPermissionState()
            }
        }
    }

    private var bridgeSettingsContent: some View {
        ScrollView {
            VStack(spacing: AppDesign.Spacing.section) {
                switch mode {
                case .all:
                    paneSwitch
                    if statusMessage != nil || inlineError != nil {
                        operationStatusSection
                    }
                    switch selectedPane {
                    case .bridges:
                        bridgePaneContent
                    case .widgets:
                        widgetsSection
                    case .notifications:
                        notificationsSection
                    case .feedback:
                        feedbackSection
                    }
                case .bridges:
                    if statusMessage != nil || inlineError != nil {
                        operationStatusSection
                    }
                    bridgePaneContent
                case .settings:
                    if statusMessage != nil || inlineError != nil {
                        operationStatusSection
                    }
                    widgetsSection
                    notificationsSection
                    feedbackSection
                }
                if showsAddBridgeSection {
                    addBridgeSection
                }
            }
            .padding(.horizontal, AppDesign.Spacing.page)
            .padding(.vertical, AppDesign.Spacing.page)
            .padding(.bottom, showsDoneButton ? 0 : 88)
        }
        .appPage()
    }

    private var showsAddBridgeSection: Bool {
        switch mode {
        case .all:
            return selectedPane == .bridges && !showsBridgeSetupOnly
        case .bridges:
            return !showsBridgeSetupOnly
        case .settings:
            return false
        }
    }

    private var showsBridgeSetupOnly: Bool {
        model.credential == nil && model.bridges.isEmpty
    }

    private var navigationTitle: String {
        switch mode {
        case .all:
            return "Settings"
        case .bridges:
            return "Bridges"
        case .settings:
            return "Settings"
        }
    }

    @ViewBuilder
    private var paneSwitch: some View {
        SettingsPaneSelector(
            panes: BridgeSettingsPane.allCases,
            selectedPane: selectedPane,
            operationInProgress: operationInProgress,
            item: settingsPaneItem(for:),
            select: { pane in
                guard !operationInProgress else {
                    return
                }
                AppFeedback.selection()
                selectedPane = pane
            }
        )
        if operationInProgress {
            AppDisabledReasonRow(reason: "Finish the current bridge operation before switching settings areas.")
        }
    }

    @ViewBuilder
    private var addBridgeSection: some View {
        AppSection(
            title: "New Bridge",
            subtitle: "",
            systemImage: "plus.circle",
            tint: operationInProgress ? AppDesign.Palette.stale : AppDesign.Palette.bridge
        ) {
            AppActionButton(
                title: "Add Bridge",
                systemImage: "plus",
                kind: operationInProgress ? .stale : .action,
                isEnabled: !operationInProgress,
                disabledReason: "Finish the current bridge operation before adding another bridge."
            ) {
                AppFeedback.selection()
                showingPairing = true
            }
            if operationInProgress {
                AppDisabledReasonRow(reason: "Finish the current bridge operation before adding another bridge.")
            }
        }
    }

    @ViewBuilder
    private var bridgePaneContent: some View {
        if showsBridgeSetupOnly {
            bridgeSetupSection
        } else {
            activeBridgeSection
            bridgesSection
        }
    }

    @ViewBuilder
    private var bridgeSetupSection: some View {
        AppSection(
            title: "Bridge",
            subtitle: "",
            systemImage: "link.badge.plus",
            tint: operationInProgress ? AppDesign.Palette.stale : AppDesign.Palette.bridge
        ) {
            AppEmptyState(
                title: "No Bridge Added",
                message: "Add one trusted local bridge to monitor, wake, and run actions.",
                systemImage: "antenna.radiowaves.left.and.right",
                tint: AppDesign.Palette.bridge
            )
            AppActionButton(
                title: "Add Bridge",
                systemImage: "plus",
                kind: operationInProgress ? .stale : .action,
                isEnabled: !operationInProgress,
                disabledReason: "Finish the current bridge operation before adding another bridge."
            ) {
                AppFeedback.selection()
                showingPairing = true
            }
        }
    }

    @ViewBuilder
    private var widgetsSection: some View {
        AppSection(
            title: "Widgets",
            subtitle: "",
            systemImage: "square.grid.2x2",
            tint: widgetsSectionTint
        ) {
            if model.credential == nil {
                AppEmptyState(
                    title: "Add Bridge",
                    message: "Widgets use the active bridge cache.",
                    systemImage: "square.grid.2x2"
                )
            } else {
                WidgetSurfaceSummary(
                    trustedCount: model.widgetActionSelections.count,
                    bridgeName: model.credential?.bridgeName ?? "Active bridge",
                    bridgeReachable: model.bridgeReachable,
                    lastConfirmedText: bridgeLastConfirmedText,
                    tint: widgetsSectionTint
                )

                if model.widgetActionSelections.isEmpty {
                    AppNoticeRow(
                        title: "No Trusted Actions",
                        message: "Trust wake or command tiles for widgets.",
                        systemImage: "checkmark.seal",
                        tint: AppDesign.Palette.stale
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.widgetActionSelections) { selection in
                            WidgetActionSelectionRow(
                                selection: selection,
                                addedText: AppFormat.relativeShort(selection.addedAt),
                                remove: {
                                    removeWidgetSelection(selection)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        AppSection(
            title: "Feedback",
            subtitle: "",
            systemImage: "waveform.path",
            tint: feedbackSectionTint
        ) {
            VStack(spacing: 10) {
                Toggle(isOn: $hapticsEnabled) {
                    FeedbackPreferenceLabel(
                        title: "Haptics",
                        detail: "Taps, progress, results",
                        systemImage: "hand.tap"
                    )
                }
                .onChange(of: hapticsEnabled) { _, enabled in
                    AppFeedback.hapticsEnabled = enabled
                    if enabled {
                        AppFeedback.selection()
                    }
                }

                Divider()

                Toggle(isOn: $tonesEnabled) {
                    FeedbackPreferenceLabel(
                        title: "Audio Cues",
                        detail: "Off by default, silent-aware",
                        systemImage: "speaker.wave.2"
                    )
                }
                .onChange(of: tonesEnabled) { _, enabled in
                    AppFeedback.tonesEnabled = enabled
                    if enabled {
                        AppFeedback.success()
                    }
                }
            }
            .padding(12)
            .appSemanticPanel(
                tint: feedbackSectionTint,
                isActive: hapticsEnabled || tonesEnabled,
                prominence: .quiet
            )

            FeedbackModeSummary(
                title: feedbackModeTitle,
                detail: feedbackModeDetail,
                systemImage: feedbackModeIcon,
                tint: feedbackSectionTint
            )

            AppActionButton(
                title: "Preview Feedback",
                systemImage: "waveform.path",
                kind: .action
            ) {
                previewFeedback()
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        AppSection(
            title: "Notifications",
            subtitle: "",
            systemImage: notificationPermissionState.systemImage,
            tint: notificationSectionTint
        ) {
            AppNoticeRow(
                title: notificationPermissionState.title,
                message: notificationStatusDetail,
                systemImage: notificationPermissionState.systemImage,
                tint: notificationSectionTint
            )

            AppActionButton(
                title: notificationActionTitle,
                systemImage: notificationActionIcon,
                kind: notificationPermissionState == .denied ? .warning : .action,
                isEnabled: notificationPermissionState != .unavailable,
                disabledReason: "Notification settings are available on iPhone."
            ) {
                Task {
                    await manageNotifications()
                }
            }
        }
    }

    @ViewBuilder
    private var activeBridgeSection: some View {
        AppSection(
            title: "Active Bridge",
            subtitle: "",
            systemImage: activeBridgeIconName,
            tint: activeBridgeTint
        ) {
            if let credential = model.credential {
                ActiveBridgeAuthorityPanel(
                    bridgeName: credential.bridgeName,
                    address: bridgeAddressText(for: credential),
                    pairedText: AppFormat.relativeShort(credential.pairedAt),
                    statusTitle: activeBridgeStatusTitle,
                    statusDetail: activeBridgeStatusDetail,
                    statusKind: activeBridgeStatusKind,
                    statusIconName: activeBridgeIconName,
                    cacheTitle: activeBridgeCacheTitle,
                    cacheDetail: activeBridgeCacheDetail,
                    capabilities: activeBridgeCapabilityItems,
                    tint: activeBridgeTint,
                    reconnecting: reconnectingBridgeID == credential.bridgeID,
                    operationInProgress: operationInProgress,
                    reconnect: {
                        reconnect(credential)
                    },
                    rename: {
                        AppFeedback.selection()
                        renameTarget = BridgeRename(bridge: credential)
                    }
                )
            } else {
                AppEmptyState(
                    title: "No Active Bridge",
                    message: "Add a trusted local bridge.",
                    systemImage: "link.badge.plus"
                )
            }
        }
    }

    @ViewBuilder
    private var bridgesSection: some View {
        AppSection(
            title: "Saved Bridges",
            subtitle: "",
            systemImage: "antenna.radiowaves.left.and.right",
            tint: bridgesSectionTint
        ) {
            if model.bridges.isEmpty {
                AppNoticeRow(
                    title: "No Bridges",
                    message: "Add one bridge to start.",
                    systemImage: "link",
                    tint: AppDesign.Palette.stale
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(model.bridges, id: \.bridgeID) { bridge in
                        bridgeManagementRow(bridge)
                    }
                }
                if operationInProgress {
                    AppDisabledReasonRow(reason: "Bridge controls are locked while the current operation finishes.")
                }
            }
        }
    }

    @ViewBuilder
    private var operationStatusSection: some View {
        AppSection(
            title: "Latest Result",
            subtitle: "",
            systemImage: "waveform",
            tint: operationStatusTint
        ) {
            if selectingBridgeID != nil {
                AppNoticeRow(
                    title: "Selecting Bridge",
                    message: statusMessage ?? "Selecting bridge",
                    systemImage: "checkmark.circle",
                    tint: AppDesign.Palette.warning,
                    progress: true
                )
            } else if reconnectingBridgeID != nil {
                AppNoticeRow(
                    title: "Reconnecting",
                    message: statusMessage ?? "Reconnecting",
                    systemImage: "arrow.clockwise",
                    tint: AppDesign.Palette.warning,
                    progress: true
                )
            } else if removingBridgeID != nil {
                AppNoticeRow(
                    title: "Removing Bridge",
                    message: statusMessage ?? "Removing bridge",
                    systemImage: "trash",
                    tint: AppDesign.Palette.destructive,
                    progress: true
                )
            } else if let statusMessage {
                AppNoticeRow(
                    title: "Bridge Updated",
                    message: statusMessage,
                    systemImage: "checkmark.circle",
                    tint: AppDesign.Palette.success
                )
            }

            if let inlineError {
                AppNoticeRow(
                    title: "Bridge Action Failed",
                    message: inlineError,
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
            }
        }
    }

    private func bridgeManagementRow(_ bridge: PairingCredential) -> some View {
        BridgeManagementCard(
            bridge: bridge,
            active: model.credential?.bridgeID == bridge.bridgeID,
            statusText: bridgeListStatusText(for: bridge),
            statusDetail: bridgeListStatusDetail(for: bridge),
            statusKind: bridgeListStatusKind(for: bridge),
            selecting: selectingBridgeID == bridge.bridgeID,
            reconnecting: reconnectingBridgeID == bridge.bridgeID,
            removing: removingBridgeID == bridge.bridgeID,
            operationInProgress: operationInProgress,
            use: {
                select(bridge)
            },
            reconnect: {
                reconnect(bridge)
            },
            rename: {
                AppFeedback.selection()
                renameTarget = BridgeRename(bridge: bridge)
            },
            remove: {
                AppFeedback.selection()
                pendingRemoval = BridgeRemoval(bridge: bridge)
            }
        )
    }

    private var operationInProgress: Bool {
        selectingBridgeID != nil || reconnectingBridgeID != nil || removingBridgeID != nil
    }

    private var activeBridgeTint: Color {
        guard model.credential != nil else {
            return AppDesign.Palette.stale
        }
        if model.bridgeHealthy {
            return AppDesign.Palette.success
        }
        return model.bridgeReachable ? AppDesign.Palette.warning : AppDesign.Palette.stale
    }

    private var activeBridgeIconName: String {
        guard model.credential != nil else {
            return "link.badge.plus"
        }
        if model.bridgeHealthy {
            return "checkmark.circle.fill"
        }
        return model.bridgeReachable ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark"
    }

    private var activeBridgeStatusTitle: String {
        guard model.credential != nil else {
            return "Not Added"
        }
        if model.bridgeHealthy {
            return "Live"
        }
        return model.bridgeReachable ? "Responding" : "Cached"
    }

    private var activeBridgeStatusDetail: String? {
        guard model.credential != nil else {
            return nil
        }
        if model.bridgeReachable {
            if let uptime = model.bridgeHealth.map({ AppFormat.shortDuration(seconds: $0.uptimeSeconds, precision: .largestUnit) }) {
                return "\(model.bridgeStatusText), uptime \(uptime)"
            }
            return model.bridgeStatusText
        }
        return bridgeLastConfirmedText.map { "last confirmed \($0)" } ?? "no confirmed cache yet"
    }

    private var activeBridgeStatusKind: AppStatusKind {
        guard model.credential != nil else {
            return .stale
        }
        if model.bridgeHealthy {
            return .success
        }
        return model.bridgeReachable ? .warning : .stale
    }

    private var activeBridgeCacheTitle: String {
        model.bridgeReachable ? "Widget Cache" : "Cached Data"
    }

    private var activeBridgeCacheDetail: String {
        if model.bridgeReachable {
            return "Health, wake, actions, and widgets refresh from this bridge."
        }
        return bridgeLastConfirmedText.map { "Last confirmed \($0). Live actions are paused." } ?? "No confirmed cache yet. Live actions are paused."
    }

    private var activeBridgeCapabilityItems: [BridgeCapabilityItem] {
        guard let capabilities = model.bridgeHealth?.capabilities else {
            return []
        }
        return [
            BridgeCapabilityItem(
                title: "Commands",
                systemImage: "terminal",
                kind: capabilities.commandRunnerEnabled ? .success : .stale
            ),
            BridgeCapabilityItem(
                title: "Ad Hoc",
                systemImage: "text.badge.plus",
                kind: capabilities.commandRunnerAdHoc ? .success : .stale
            ),
            BridgeCapabilityItem(
                title: "Health",
                systemImage: "waveform.path.ecg",
                kind: capabilities.healthMonitors ? .success : .stale
            ),
            BridgeCapabilityItem(
                title: "Wake",
                systemImage: "power",
                kind: capabilities.wol ? .success : .stale
            )
        ]
    }

    private func bridgeAddressText(for bridge: PairingCredential) -> String {
        bridge.directURLs.first?.absoluteString ?? "No bridge URL saved"
    }

    private func bridgeListStatusText(for bridge: PairingCredential) -> String {
        guard model.credential?.bridgeID == bridge.bridgeID else {
            return "Saved"
        }
        return activeBridgeStatusTitle
    }

    private func bridgeListStatusDetail(for bridge: PairingCredential) -> String {
        guard model.credential?.bridgeID == bridge.bridgeID else {
            return "Paired \(AppFormat.relativeShort(bridge.pairedAt))"
        }
        return activeBridgeStatusDetail ?? model.bridgeStatusText
    }

    private func bridgeListStatusKind(for bridge: PairingCredential) -> AppStatusKind {
        guard model.credential?.bridgeID == bridge.bridgeID else {
            return .stale
        }
        return activeBridgeStatusKind
    }

    private var bridgeLastConfirmedAt: Date? {
        [
            model.healthMonitorsUpdatedAt,
            model.wolTargetsUpdatedAt,
            model.cards.map(\.updatedAt).max(),
            model.auditRecords.map(\.createdAt).max()
        ]
        .compactMap { $0 }
        .max()
    }

    private var bridgeLastConfirmedText: String? {
        bridgeLastConfirmedAt.map { AppFormat.relativeShort($0) }
    }

    private var bridgesSectionTint: Color {
        model.bridges.isEmpty ? AppDesign.Palette.stale : activeBridgeTint
    }

    private var operationStatusTint: Color {
        if inlineError != nil {
            return AppDesign.Palette.warning
        }
        if operationInProgress {
            if removingBridgeID != nil {
                return AppDesign.Palette.destructive
            }
            return AppDesign.Palette.warning
        }
        if statusMessage != nil {
            return AppDesign.Palette.success
        }
        return AppDesign.Palette.stale
    }

    private var feedbackSectionTint: Color {
        if hapticsEnabled || tonesEnabled {
            return AppDesign.Palette.action
        }
        return AppDesign.Palette.stale
    }

    private var notificationSectionTint: Color {
        switch notificationPermissionState {
        case .enabled:
            return model.credential?.relayAccessToken == nil ? AppDesign.Palette.warning : AppDesign.Palette.success
        case .denied:
            return AppDesign.Palette.warning
        case .notRequested, .unavailable:
            return AppDesign.Palette.stale
        }
    }

    private var widgetsSectionTint: Color {
        guard model.credential != nil else {
            return AppDesign.Palette.stale
        }
        return model.widgetActionSelections.isEmpty ? AppDesign.Palette.stale : AppDesign.Palette.widget
    }

    private var settingsPaneTint: Color {
        switch selectedPane {
        case .bridges:
            return bridgesSectionTint
        case .widgets:
            return widgetsSectionTint
        case .notifications:
            return notificationSectionTint
        case .feedback:
            return feedbackSectionTint
        }
    }

    private func settingsPaneItem(for pane: BridgeSettingsPane) -> SettingsPaneItem {
        switch pane {
        case .bridges:
            return SettingsPaneItem(
                title: pane.title,
                value: bridgePaneValue,
                detail: bridgePaneDetail,
                systemImage: pane.systemImage,
                tint: AppDesign.Palette.bridge,
                kind: bridgePaneKind
            )
        case .widgets:
            return SettingsPaneItem(
                title: pane.title,
                value: widgetPaneValue,
                detail: widgetPaneDetail,
                systemImage: pane.systemImage,
                tint: AppDesign.Palette.widget,
                kind: model.widgetActionSelections.isEmpty ? .stale : .success
            )
        case .notifications:
            return SettingsPaneItem(
                title: pane.title,
                value: notificationPermissionState.shortTitle,
                detail: model.credential == nil ? "Bridge required" : notificationPermissionState.detail,
                systemImage: pane.systemImage,
                tint: notificationSectionTint,
                kind: notificationPermissionState == .enabled ? .success : (notificationPermissionState == .denied ? .warning : .stale)
            )
        case .feedback:
            return SettingsPaneItem(
                title: pane.title,
                value: feedbackPaneValue,
                detail: feedbackModeDetail,
                systemImage: pane.systemImage,
                tint: AppDesign.Palette.activity,
                kind: hapticsEnabled || tonesEnabled ? .action : .stale
            )
        }
    }

    private var bridgePaneValue: String {
        if model.bridges.isEmpty {
            return "None"
        }
        return model.bridges.count == 1 ? "1 Saved" : "\(model.bridges.count) Saved"
    }

    private var bridgePaneDetail: String {
        guard let credential = model.credential else {
            return "No active bridge"
        }
        return model.bridgeReachable ? credential.bridgeName : "Cached \(credential.bridgeName)"
    }

    private var bridgePaneKind: AppStatusKind {
        guard model.credential != nil else {
            return .stale
        }
        if model.bridgeHealthy {
            return .success
        }
        return model.bridgeReachable ? .warning : .stale
    }

    private var widgetPaneValue: String {
        let count = model.widgetActionSelections.count
        if count == 0 {
            return "None"
        }
        return count == 1 ? "1 Trusted" : "\(count) Trusted"
    }

    private var widgetPaneDetail: String {
        model.credential == nil ? "Bridge required" : "Trusted only"
    }

    private var feedbackPaneValue: String {
        if hapticsEnabled && tonesEnabled {
            return "Full"
        }
        if hapticsEnabled {
            return "Touch"
        }
        if tonesEnabled {
            return "Audio"
        }
        return "Visual"
    }

    private var feedbackModeTitle: String {
        switch (hapticsEnabled, tonesEnabled) {
        case (true, true):
            return "Haptics and Audio Enabled"
        case (true, false):
            return "Haptics Enabled"
        case (false, true):
            return "Audio Only"
        case (false, false):
            return "Quiet Mode"
        }
    }

    private var feedbackModeDetail: String {
        switch (hapticsEnabled, tonesEnabled) {
        case (true, true):
            return "Tactile feedback with restrained audio cues"
        case (true, false):
            return "Tactile feedback; audio cues are off"
        case (false, true):
            return "Restrained audio cues; haptics are off"
        case (false, false):
            return "Visual confirmations remain on"
        }
    }

    private var feedbackModeIcon: String {
        switch (hapticsEnabled, tonesEnabled) {
        case (true, true):
            return "checkmark.circle"
        case (true, false):
            return "hand.tap"
        case (false, true):
            return "speaker.wave.2"
        case (false, false):
            return "speaker.slash"
        }
    }

    private func select(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        AppFeedback.actionStarted()
        Task {
            selectingBridgeID = bridge.bridgeID
            statusMessage = "Selecting \(bridge.bridgeName). Verifying bridge reachability."
            inlineError = nil
            let selected = await model.setActiveBridge(bridge)
            selectingBridgeID = nil
            if selected {
                statusMessage = "\(model.credential?.bridgeName ?? bridge.bridgeName) is active and reachable."
                AppFeedback.success()
            } else {
                let message = model.errorMessage ?? "Could not verify \(bridge.bridgeName)."
                statusMessage = nil
                if model.credential?.bridgeID == bridge.bridgeID {
                    inlineError = "Selected \(bridge.bridgeName), but verification failed: \(message)"
                } else {
                    inlineError = "Could not select \(bridge.bridgeName): \(message)"
                }
                model.errorMessage = nil
                AppFeedback.warning()
            }
        }
    }

    private func remove(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        AppFeedback.actionStarted()
        Task {
            removingBridgeID = bridge.bridgeID
            statusMessage = "Removing \(bridge.bridgeName). Trusted actions and cached state will update."
            inlineError = nil
            let removedAndVerified = await model.removeBridge(bridge)
            let removed = !model.bridges.contains { $0.bridgeID == bridge.bridgeID }
            removingBridgeID = nil
            if removedAndVerified {
                statusMessage = "Removed \(bridge.bridgeName)."
                AppFeedback.destructive()
            } else {
                let message = model.errorMessage ?? "Could not remove \(bridge.bridgeName)."
                statusMessage = nil
                if removed {
                    inlineError = "Removed \(bridge.bridgeName), but the active bridge could not be verified: \(message)"
                } else {
                    inlineError = "Could not remove \(bridge.bridgeName): \(message)"
                }
                model.errorMessage = nil
                AppFeedback.warning()
            }
        }
    }

    private func reconnect(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        AppFeedback.actionStarted()
        Task {
            reconnectingBridgeID = bridge.bridgeID
            statusMessage = "Reconnecting to \(bridge.bridgeName). Exchanging a fresh bridge credential."
            inlineError = nil
            let reconnected = await model.reconnectBridge(bridge)
            reconnectingBridgeID = nil
            if reconnected {
                statusMessage = "Reconnected to \(model.credential?.bridgeName ?? bridge.bridgeName)."
                AppFeedback.success()
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not reconnect \(bridge.bridgeName)."
                model.errorMessage = nil
                AppFeedback.warning()
            }
        }
    }

    private func bridgeRowTint(for bridge: PairingCredential) -> Color {
        guard model.credential?.bridgeID == bridge.bridgeID else {
            return AppDesign.Palette.stale
        }
        if model.bridgeHealthy {
            return AppDesign.Palette.success
        }
        return model.bridgeReachable ? AppDesign.Palette.warning : AppDesign.Palette.stale
    }

    private func removeWidgetSelection(_ selection: WidgetActionSelection) {
        if model.toggleWidgetActionSelection(
            kind: selection.kind,
            actionID: selection.actionID,
            title: selection.title,
            subtitle: selection.subtitle
        ) {
            AppFeedback.success()
            statusMessage = "Removed \(selection.title) from trusted widget actions."
            inlineError = nil
        } else {
            AppFeedback.failure()
            statusMessage = nil
            inlineError = "Could not update trusted actions."
        }
    }

    private var notificationStatusDetail: String {
        switch notificationPermissionState {
        case .enabled:
            guard let credential = model.credential else {
                return "Permission is enabled. Add a bridge to receive operational alerts."
            }
            guard credential.relayURL != nil else {
                return "Permission is enabled, but \(credential.bridgeName) does not have a notification relay configured."
            }
            guard credential.relayAccessToken != nil else {
                return "Permission is enabled, but this older pairing lacks relay access. Reconnect \(credential.bridgeName)."
            }
            return "Important alerts from \(credential.bridgeName) can reach this iPhone and its paired Apple Watch."
        case .denied:
            return "Notifications are blocked in iOS Settings. PopRocket will continue to show live and cached state in the app."
        case .notRequested:
            return "Enable important bridge failures and security alerts when you are away from the dashboard."
        case .unavailable:
            return "Notification permission and APNs registration are managed on iPhone."
        }
    }

    private var notificationActionTitle: String {
        switch notificationPermissionState {
        case .enabled:
            return "Refresh Registration"
        case .denied:
            return "Open iOS Settings"
        case .notRequested:
            return "Enable Notifications"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var notificationActionIcon: String {
        switch notificationPermissionState {
        case .enabled:
            return "arrow.clockwise"
        case .denied:
            return "gear"
        case .notRequested:
            return "bell.badge"
        case .unavailable:
            return "bell.slash"
        }
    }

    @MainActor
    private func refreshNotificationPermissionState() async {
        #if os(iOS)
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            notificationPermissionState = .enabled
        case .denied:
            notificationPermissionState = .denied
        case .notDetermined:
            notificationPermissionState = .notRequested
        @unknown default:
            notificationPermissionState = .unavailable
        }
        #else
        notificationPermissionState = .unavailable
        #endif
    }

    @MainActor
    private func manageNotifications() async {
        #if os(iOS)
        if notificationPermissionState == .denied {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(settingsURL)
            return
        }
        await RemoteNotificationRegistrar.shared.requestAuthorizationAndRegister()
        let registered = await RemoteNotificationRegistrar.shared.registerActiveCredentialIfPossible()
        await refreshNotificationPermissionState()
        if notificationPermissionState == .enabled {
            statusMessage = registered
                ? "Notification registration refreshed."
                : "Notification permission is enabled; APNs registration is pending."
            inlineError = nil
        }
        #endif
    }

    private func previewFeedback() {
        AppFeedback.success()
        statusMessage = feedbackPreviewMessage
        inlineError = nil
    }

    private var feedbackPreviewMessage: String {
        switch (hapticsEnabled, tonesEnabled) {
        case (true, true):
            return "Previewed visual, haptic, and audio feedback."
        case (true, false):
            return "Previewed visual and haptic feedback."
        case (false, true):
            return "Previewed visual and audio feedback."
        case (false, false):
            return "Previewed visual feedback. Haptics and audio are off."
        }
    }
}

private enum NotificationPermissionState: Equatable {
    case enabled
    case denied
    case notRequested
    case unavailable

    var title: String {
        switch self {
        case .enabled: return "Notifications Enabled"
        case .denied: return "Notifications Blocked"
        case .notRequested: return "Notifications Off"
        case .unavailable: return "iPhone Only"
        }
    }

    var shortTitle: String {
        switch self {
        case .enabled: return "On"
        case .denied: return "Blocked"
        case .notRequested: return "Off"
        case .unavailable: return "iPhone"
        }
    }

    var detail: String {
        switch self {
        case .enabled: return "Permission granted"
        case .denied: return "Open iOS Settings"
        case .notRequested: return "Optional alerts"
        case .unavailable: return "Manage on iPhone"
        }
    }

    var systemImage: String {
        switch self {
        case .enabled: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notRequested: return "bell.badge"
        case .unavailable: return "iphone"
        }
    }
}

private struct SettingsPaneItem {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let kind: AppStatusKind
}

private struct SettingsPaneSelector: View {
    let panes: [BridgeSettingsPane]
    let selectedPane: BridgeSettingsPane
    let operationInProgress: Bool
    let item: (BridgeSettingsPane) -> SettingsPaneItem
    let select: (BridgeSettingsPane) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(panes) { pane in
                let paneItem = item(pane)
                Button {
                    select(pane)
                } label: {
                    SettingsPaneTile(
                        item: paneItem,
                        selected: pane == selectedPane,
                        disabled: operationInProgress
                    )
                }
                .buttonStyle(AppPressButtonStyle(tint: paneItem.tint, isEnabled: !operationInProgress))
                .disabled(operationInProgress)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(paneItem.title), \(paneItem.value), \(paneItem.detail)")
                .accessibilityAddTraits(pane == selectedPane ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppDesign.panelFill, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .background(AppDesign.Palette.bridge.opacity(0.035), in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(AppDesign.Palette.bridge.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SettingsPaneTile: View {
    let item: SettingsPaneItem
    let selected: Bool
    let disabled: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.bold))
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? item.tint : AppDesign.Palette.stale)
        .background(selected ? item.tint.opacity(0.20) : Color.clear, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(selected ? item.tint.opacity(0.36) : Color.clear, lineWidth: 1)
        }
        .opacity(disabled ? AppDesign.disabledOpacity : 1)
    }
}

private struct BridgeCapabilityItem: Identifiable {
    let title: String
    let systemImage: String
    let kind: AppStatusKind

    var id: String { title }
}

private struct ActiveBridgeAuthorityPanel: View {
    let bridgeName: String
    let address: String
    let pairedText: String
    let statusTitle: String
    let statusDetail: String?
    let statusKind: AppStatusKind
    let statusIconName: String
    let cacheTitle: String
    let cacheDetail: String
    let capabilities: [BridgeCapabilityItem]
    let tint: Color
    let reconnecting: Bool
    let operationInProgress: Bool
    let reconnect: () -> Void
    let rename: () -> Void

    private var capabilityColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 82), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconBubble(systemImage: statusIconName, tint: tint, size: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text(bridgeName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                    Text(headerDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AppStatusPill(
                    title: statusTitle,
                    systemImage: statusIconName,
                    color: statusKind.color
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                AppStateLine(
                    title: cacheTitle,
                    detail: cacheDetail,
                    kind: statusKind == .stale ? .stale : .success
                )
                BridgeAuthorityInfoLine(
                    title: "Address",
                    value: address,
                    systemImage: "link",
                    monospace: true
                )
                BridgeAuthorityInfoLine(
                    title: "Paired",
                    value: pairedText,
                    systemImage: "calendar"
                )
            }

            if !capabilities.isEmpty {
                LazyVGrid(columns: capabilityColumns, alignment: .leading, spacing: 8) {
                    ForEach(capabilities) { capability in
                        BridgeCapabilityChip(item: capability)
                    }
                }
            }

            HStack(spacing: 10) {
                AppActionButton(
                    title: reconnecting ? "Verifying" : "Verify",
                    systemImage: "arrow.clockwise",
                    kind: statusKind == .stale ? .warning : .action,
                    isRunning: reconnecting,
                    isEnabled: !operationInProgress,
                    disabledReason: "Wait for the current bridge operation to finish.",
                    runningReason: "Verifying this bridge and refreshing credentials."
                ) {
                    reconnect()
                }
                AppActionButton(
                    title: "Rename",
                    systemImage: "pencil",
                    kind: .action,
                    isEnabled: !operationInProgress,
                    disabledReason: "Wait for the current bridge operation to finish."
                ) {
                    rename()
                }
            }

            if operationInProgress && !reconnecting {
                AppDisabledReasonRow(reason: "Bridge controls are locked until the current operation finishes.")
            }
        }
        .padding(12)
        .appSemanticPanel(
            tint: tint,
            isActive: true,
            prominence: statusKind == .success ? .standard : .quiet
        )
    }

    private var headerDetail: String {
        guard let statusDetail else {
            return "Trusted local authority"
        }
        let trimmed = statusDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Trusted local authority" : trimmed
    }
}

private struct BridgeAuthorityInfoLine: View {
    let title: String
    let value: String
    let systemImage: String
    var monospace = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(monospace ? AppDesign.Typography.monoMetadata : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BridgeCapabilityChip: View {
    let item: BridgeCapabilityItem

    var body: some View {
        Label(item.title, systemImage: item.kind == .success ? item.systemImage : "minus.circle")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(item.kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(item.kind.color.opacity(0.11), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(item.kind.color.opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("\(item.title) \(item.kind == .success ? "available" : "unavailable")")
    }
}

private struct BridgeManagementCard: View {
    let bridge: PairingCredential
    let active: Bool
    let statusText: String
    let statusDetail: String
    let statusKind: AppStatusKind
    let selecting: Bool
    let reconnecting: Bool
    let removing: Bool
    let operationInProgress: Bool
    let use: () -> Void
    let reconnect: () -> Void
    let rename: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: statusIconName, tint: statusTint, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(bridge.bridgeName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if active {
                            AppStatusBadge(title: "Active", kind: statusKind, systemImage: "checkmark")
                                .accessibilityLabel("Active bridge")
                        }
                    }
                    Text(bridgeAddressText)
                        .font(AppDesign.Typography.monoMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    AppStateLine(
                        title: statusText,
                        detail: statusDetail,
                        kind: statusKind
                    )
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                if active {
                    Menu {
                        managementMenuItems
                    } label: {
                        AppIconButtonLabel(
                            systemImage: "ellipsis",
                            tint: AppDesign.Palette.action,
                            isEnabled: !operationInProgress
                        )
                    }
                    .disabled(operationInProgress)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Options for \(bridge.bridgeName)")
                } else {
                    HStack(spacing: 6) {
                        AppActionButton(
                            title: selecting ? "Using" : "Use",
                            systemImage: "arrow.right.circle",
                            kind: .action,
                            isRunning: selecting,
                            isEnabled: !operationInProgress,
                            disabledReason: "Wait for the current bridge operation to finish.",
                            runningReason: "Selecting and verifying this bridge."
                        ) {
                            use()
                        }
                        .frame(width: 82)

                        Menu {
                            managementMenuItems
                        } label: {
                            AppIconButtonLabel(
                                systemImage: "ellipsis",
                                tint: AppDesign.Palette.action,
                                isEnabled: !operationInProgress
                            )
                        }
                        .disabled(operationInProgress)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Options for \(bridge.bridgeName)")
                    }
                }
            }

            if let operationLine {
                AppStateLine(
                    title: operationLine,
                    detail: nil,
                    kind: removing ? .destructive : .warning
                )
            }

            if operationInProgress && !selecting && !reconnecting && !removing {
                AppDisabledReasonRow(reason: "Wait for the current bridge operation to finish.")
            }
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusTint,
            isActive: active,
            prominence: active ? .standard : .quiet,
            showsRail: active
        )
    }

    @ViewBuilder
    private var managementMenuItems: some View {
        Button {
            reconnect()
        } label: {
            Label("Reconnect", systemImage: "arrow.clockwise")
        }
        Button {
            rename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            remove()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private var statusIconName: String {
        guard active else {
            return "antenna.radiowaves.left.and.right"
        }
        return statusKind.symbolName
    }

    private var statusTint: Color {
        guard active else {
            return AppDesign.Palette.stale
        }
        return statusKind.color
    }

    private var bridgeAddressText: String {
        bridge.directURLs.first?.absoluteString ?? "No bridge URL saved"
    }

    private var operationLine: String? {
        if selecting {
            return "Selecting bridge"
        }
        if reconnecting {
            return "Reconnecting"
        }
        if removing {
            return "Removing bridge"
        }
        return nil
    }
}

private struct FeedbackPreferenceLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppDesign.Palette.action)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FeedbackModeSummary: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            AppIconBubble(systemImage: systemImage, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            AppStatusBadge(title: "VISUAL", kind: .stale, systemImage: "eye")
                .accessibilityLabel("Visual feedback always enabled")
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: .quiet)
    }
}

private struct WidgetSurfaceSummary: View {
    let trustedCount: Int
    let bridgeName: String
    let bridgeReachable: Bool
    let lastConfirmedText: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: "apps.iphone", tint: statusKind.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summaryTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(summaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AppStatusPill(
                    title: trustedText,
                    systemImage: trustedCount == 0 ? "checkmark.seal" : "checkmark.seal.fill",
                    color: statusKind.color
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                AppStateLine(
                    title: bridgeReachable ? "Cache Source" : "Cached Source",
                    detail: bridgeSourceDetail,
                    kind: statusKind
                )
                if trustedCount == 0 {
                    AppStateLine(
                        title: "Actions",
                        detail: "Trust tiles from Actions.",
                        kind: .stale
                    )
                }
            }
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusKind.color,
            isActive: bridgeReachable || trustedCount > 0,
            prominence: trustedCount > 0 ? .standard : .quiet
        )
    }

    private var summaryTitle: String {
        "Widget Cache"
    }

    private var summaryDetail: String {
        "Home Screen and Lock Screen use cached bridge state."
    }

    private var trustedText: String {
        if trustedCount == 0 {
            return "No Actions"
        }
        return trustedCount == 1 ? "1 Trusted" : "\(trustedCount) Trusted"
    }

    private var bridgeSourceDetail: String {
        if bridgeReachable {
            return "\(bridgeName) cache updates when the app refreshes"
        }
        return lastConfirmedText.map { "Last confirmed \($0)" } ?? "Open the app to refresh"
    }

    private var statusKind: AppStatusKind {
        if !bridgeReachable {
            return .stale
        }
        return trustedCount == 0 ? .action : .success
    }
}

private struct WidgetActionSelectionRow: View {
    let selection: WidgetActionSelection
    let addedText: String
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIconBubble(systemImage: systemImage, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(selection.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    AppStatusPill(title: actionKindTitle, systemImage: systemImage, color: tint)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Trusted \(addedText)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            AppCompactActionButton(
                title: "Remove",
                systemImage: "minus.circle",
                accessibilityLabel: "Remove \(selection.title) from trusted widget actions",
                kind: .destructive,
                disabledReason: "Trusted action removal is unavailable.",
                runningReason: "Removing this trusted widget action.",
                action: remove
            )
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: .quiet)
    }

    private var systemImage: String {
        switch selection.kind {
        case .wol:
            return "power"
        case .command:
            return "terminal"
        }
    }

    private var tint: Color {
        switch selection.kind {
        case .wol:
            return AppDesign.Palette.wake
        case .command:
            return AppDesign.Palette.command
        }
    }

    private var detailText: String {
        let fallback = selection.kind == .wol ? "Wake-on-LAN" : "Command tile"
        let trimmedSubtitle = selection.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitle = trimmedSubtitle.isEmpty ? fallback : trimmedSubtitle
        return subtitle
    }

    private var actionKindTitle: String {
        switch selection.kind {
        case .wol:
            return "Wake"
        case .command:
            return "Command"
        }
    }
}

private struct BridgeNameEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let bridge: PairingCredential
    @State private var name: String
    @State private var saving = false
    @State private var inlineError: String?
    @FocusState private var focusedField: BridgeNameFocusField?

    init(bridge: PairingCredential) {
        self.bridge = bridge
        _name = State(initialValue: bridge.bridgeName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppDesign.Spacing.section) {
                    AppSection(
                        title: "Name",
                        subtitle: "",
                        systemImage: "textformat"
                    ) {
                        AppFieldLabel(title: "Bridge Name", systemImage: "antenna.radiowaves.left.and.right")
                        #if canImport(UIKit)
                        TextField("Bridge Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .appField()
                        #else
                        TextField("Bridge Name", text: $name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .appField()
                        #endif
                    }
                    if let validationMessage {
                        AppSection(
                            title: "Validation",
                            subtitle: "",
                            systemImage: "exclamationmark.circle"
                        ) {
                            AppNoticeRow(
                                title: "Name Required",
                                message: validationMessage,
                                systemImage: "exclamationmark.circle",
                                tint: AppDesign.Palette.warning
                            )
                        }
                    }
                    if let inlineError {
                        AppSection(
                            title: "Status",
                            subtitle: "",
                            systemImage: "waveform"
                        ) {
                            AppNoticeRow(
                                title: "Rename Failed",
                                message: inlineError,
                                systemImage: "exclamationmark.triangle",
                                tint: AppDesign.Palette.warning
                            )
                        }
                    }
                    AppSection(
                        title: "Address",
                        subtitle: "",
                        systemImage: "link"
                    ) {
                        Text(bridge.directURLs.first?.absoluteString ?? "No bridge URL saved")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppDesign.Spacing.fieldPadding)
                            .appSemanticPanel(tint: AppDesign.Palette.stale, isActive: false, prominence: .quiet)
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.page)
                .padding(.vertical, AppDesign.Spacing.page)
            }
            .appPage()
            .navigationTitle("Rename Bridge")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: name) { _, _ in
                inlineError = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppFeedback.selection()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving" : "Save") {
                        AppFeedback.actionStarted()
                        Task {
                            inlineError = nil
                            saving = true
                            let saved = await model.renameBridge(bridge, name: name)
                            saving = false
                            if saved {
                                AppFeedback.success()
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not rename this bridge."
                                model.errorMessage = nil
                                AppFeedback.failure()
                            }
                        }
                    }
                    .disabled(saving || validationMessage != nil)
                    .accessibilityValue(saveAccessibilityValue)
                    .accessibilityHint(saveAccessibilityHint)
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
            return "Name this bridge."
        }
        return nil
    }

    private var saveAccessibilityValue: String {
        if saving {
            return "In progress"
        }
        return validationMessage == nil ? "Available" : "Unavailable"
    }

    private var saveAccessibilityHint: String {
        if saving {
            return "Saving this bridge name."
        }
        return validationMessage ?? "Saves this bridge name."
    }
}

private enum BridgeNameFocusField: Hashable {
    case name
}

private struct BridgeRemoval: Identifiable {
    let bridge: PairingCredential
    var id: String { bridge.bridgeID }
}

private struct BridgeRename: Identifiable {
    let bridge: PairingCredential
    var id: String { bridge.bridgeID }
}
