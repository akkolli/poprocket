import PopRocketKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPairing = false
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
    @State private var feedbackNotice: DashboardFeedbackNotice?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var dashboardRefreshing = false
    @State private var selectedTab: DashboardTab = .overview
    @State private var selectedActionMode: DashboardActionMode = .wake
    @State private var manualCommandExpanded = false
    @State private var bridgeTransitionPrimed = false
    @State private var monitorTransitionPrimed = false
    @State private var lastObservedBridgeID: String?
    @State private var lastObservedBridgeReachable: Bool?
    @State private var lastObservedMonitorStatuses: [String: String] = [:]
    @FocusState private var focusedField: DashboardFocusField?

    var body: some View {
        TabView(selection: selectedTabBinding) {
            dashboardTab(.overview) {
                overviewPage
            }
            dashboardTab(.health) {
                healthPage
            }
            dashboardTab(.actions) {
                actionsPage
            }
            dashboardTab(.activity) {
                activityPage
            }
            BridgeSettingsView(showsDoneButton: false, mode: .all)
                .environmentObject(model)
                .tabItem {
                    Label(DashboardTab.settings.title, systemImage: DashboardTab.settings.systemImage)
                }
                .tag(DashboardTab.settings)
                .badge(tabBadgeText(for: .settings))
        }
        .background(DashboardDesign.background.ignoresSafeArea())
        .tint(AppDesign.Palette.action)
        .overlay(alignment: .top) {
            if let feedbackNotice {
                AppTransientNotice(
                    title: feedbackNotice.title,
                    message: feedbackNotice.message,
                    systemImage: feedbackNotice.systemImage,
                    tint: feedbackNotice.tint,
                    progress: feedbackNotice.progress
                )
                .padding(.horizontal, DashboardDesign.pagePadding)
                .padding(.top, 8)
                .transition(feedbackTransition)
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingPairing) {
            PairingView()
                .environmentObject(model)
        }
        .sheet(item: $monitorEditor) { state in
            HealthMonitorEditorView(monitor: state.monitor) { name, wasEditing in
                healthOperationError = nil
                healthOperationMessage = wasEditing ? "Updated \(name)" : "Added \(name)"
                showFeedback(
                    title: wasEditing ? "Monitor Updated" : "Monitor Added",
                    message: "\(name) is saved on \(activeBridgeName).",
                    systemImage: "checkmark.circle.fill",
                    tint: AppDesign.Palette.success
                )
            }
                .environmentObject(model)
        }
        .sheet(item: $targetEditor) { state in
            WOLTargetEditorView(target: state.target) { name, wasEditing in
                wakeOperationError = nil
                wakeOperationMessage = wasEditing ? "Updated \(name)" : "Added \(name)"
                showFeedback(
                    title: wasEditing ? "Device Updated" : "Device Added",
                    message: "\(name) is ready for Wake-on-LAN through \(activeBridgeName).",
                    systemImage: "checkmark.circle.fill",
                    tint: AppDesign.Palette.success
                )
            }
                .environmentObject(model)
        }
        .sheet(item: $commandEditor) { state in
            CommandShortcutEditorView(state: state) {
                if state.clearComposerOnSave {
                    commandText = ""
                    manualCommandExpanded = false
                }
                model.clearCommandResult()
                showFeedback(
                    title: state.shortcut == nil ? "Tile Saved" : "Tile Updated",
                    message: state.shortcut?.name ?? "Command tile is ready.",
                    systemImage: "checkmark.circle.fill",
                    tint: AppDesign.Palette.success
                )
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
                    AppFeedback.destructive()
                    showFeedback(
                        title: "Tile Removed",
                        message: "\(pendingCommandDeletion.name) was removed from this bridge.",
                        systemImage: "trash.circle.fill",
                        tint: AppDesign.Palette.destructive
                    )
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
        .onChange(of: model.credential?.bridgeID) { _, _ in
            resetTransitionFeedback()
        }
        .onChange(of: model.bridgeStatusText) { _, _ in
            handleBridgeStatusTransition()
        }
        .onChange(of: model.healthMonitors) { _, monitors in
            handleMonitorStatusTransitions(monitors)
        }
        .onOpenURL { url in
            Task {
                await handleOpenURL(url)
            }
        }
    }

    private var selectedTabBinding: Binding<DashboardTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard tab != selectedTab else {
                    return
                }
                AppFeedback.selection()
                focusedField = nil
                selectedTab = tab
            }
        )
    }

    @ViewBuilder
    private func dashboardTab<Content: View>(_ tab: DashboardTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DashboardDesign.sectionSpacing) {
                    content()
                }
                .padding(.horizontal, DashboardDesign.pagePadding)
                .padding(.vertical, DashboardDesign.pagePadding)
            }
            .background(DashboardDesign.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await refreshFromDashboard()
            }
            #if canImport(UIKit)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .toolbar {
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
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .badge(tabBadgeText(for: tab))
    }

    @ViewBuilder
    private var overviewPage: some View {
        operationsHeader
        dashboardErrorBanner
        if model.credential != nil {
            overviewMonitorSection
            if shouldShowStatusSignals {
                statusSignalsSection
            }
            overviewOperateSection
            if shouldShowOverviewActivity {
                overviewActivitySection
            }
        }
    }

    @ViewBuilder
    private var healthPage: some View {
        secondaryTabContextHeader(.health)
        dashboardErrorBanner
        if model.credential == nil {
            bridgeRequiredPanel(.health)
        } else {
            healthSection
        }
    }

    @ViewBuilder
    private var actionsPage: some View {
        secondaryTabContextHeader(.actions)
        dashboardErrorBanner
        if model.credential == nil {
            bridgeRequiredPanel(.actions)
        } else {
            actionsModeSelector
            actionsAuthorityStrip
            switch selectedActionMode {
            case .wake:
                wakeSection
            case .run:
                commandSection
            }
        }
    }

    @ViewBuilder
    private var activityPage: some View {
        secondaryTabContextHeader(.activity)
        dashboardErrorBanner
        if model.credential == nil {
            bridgeRequiredPanel(.activity)
        } else {
            activitySection
        }
    }

    private func tabBadgeText(for tab: DashboardTab) -> String? {
        switch tab {
        case .overview:
            if model.credential != nil, !model.bridgeReachable {
                return "!"
            }
            if healthDownCount > 0 {
                return Self.badgeCountText(healthDownCount)
            }
            return nil
        case .health:
            if healthDownCount > 0 {
                return Self.badgeCountText(healthDownCount)
            }
            if model.healthMonitorsErrorMessage != nil {
                return "!"
            }
            return nil
        case .actions:
            if wakeOperationError != nil || model.wolTargetsErrorMessage != nil {
                return "!"
            }
            if model.commandStatusText != nil, !model.commandSucceeded, !model.commandRunning {
                return "!"
            }
            return nil
        case .activity:
            if activityFailureCount > 0 {
                return Self.badgeCountText(activityFailureCount)
            }
            if model.activityErrorMessage != nil {
                return "!"
            }
            return nil
        case .settings:
            guard model.credential != nil else {
                return nil
            }
            if !model.bridgeReachable {
                return "!"
            }
            return nil
        }
    }

    @ViewBuilder
    private func secondaryTabContextHeader(_ tab: DashboardTab) -> some View {
        if shouldShowSecondaryTabContextHeader {
            tabContextHeader(tab)
        }
    }

    private var shouldShowSecondaryTabContextHeader: Bool {
        guard model.credential != nil else {
            return false
        }
        return dashboardRefreshing || bridgeStatusKind != .success
    }

    private func tabContextHeader(_ tab: DashboardTab) -> some View {
        DashboardTabHeader(
            title: tab.title,
            systemImage: tab.systemImage,
            tint: tabTint(tab),
            hasBridge: model.credential != nil,
            bridgeTitle: model.credential?.bridgeName ?? "No Bridge",
            bridgeStatusTitle: model.credential == nil ? "Not Added" : model.bridgeStatusText,
            bridgeStatusDetail: bridgeStatusDetail,
            bridgeStatusKind: bridgeStatusKind,
            isRefreshing: dashboardRefreshing,
            refresh: {
                Task { await refreshFromDashboard() }
            },
            pairBridge: {
                AppFeedback.selection()
                showingPairing = true
            }
        )
    }

    private func bridgeRequiredPanel(_ tab: DashboardTab) -> some View {
        BridgeRequiredPanel(
            title: bridgeRequiredTitle(for: tab),
            message: bridgeRequiredMessage(for: tab),
            systemImage: tab.systemImage,
            tint: AppDesign.Palette.action
        ) {
            AppFeedback.selection()
            showingPairing = true
        }
    }

    @ViewBuilder
    private var actionsModeSelector: some View {
        DashboardActionModeSelector(
            items: actionModeItems,
            selectedMode: selectedActionMode
        ) { mode in
            AppFeedback.selection()
            focusedField = nil
            selectedActionMode = mode
        }
    }

    @ViewBuilder
    private var actionsAuthorityStrip: some View {
        ActionAuthorityStrip(
            mode: selectedActionMode,
            bridgeName: activeBridgeName,
            bridgeReachable: model.bridgeReachable,
            bridgeHealthy: model.bridgeHealthy,
            lastConfirmedText: overviewLastConfirmedText
        )
    }

    @ViewBuilder
    private var overviewMonitorSection: some View {
        DashboardSectionBand(
            title: "Health",
            systemImage: "waveform.path.ecg",
            tint: healthSectionTint,
            badgeTitle: healthOverviewValue,
            badgeKind: healthSectionBadgeKind
        ) {
            if model.healthMonitors.isEmpty {
                DashboardNavigationButton(
                    title: "Add Checks",
                    detail: "HTTP or TCP",
                    systemImage: "plus",
                    tint: AppDesign.Palette.action
                ) {
                    AppFeedback.selection()
                    selectedTab = .health
                }
            } else {
                HealthSummaryRow(
                    monitors: model.healthMonitors,
                    isLive: model.bridgeReachable,
                    lastUpdatedAt: model.healthMonitorsUpdatedAt
                )
                ForEach(overviewAlertMonitors) { monitor in
                    HealthMonitorRow(monitor: monitor, isLive: model.bridgeReachable)
                }
            }
        }
    }

    @ViewBuilder
    private var overviewOperateSection: some View {
        DashboardSectionBand(
            title: "Quick Actions",
            systemImage: "bolt.circle",
            tint: operateSectionTint,
            badgeTitle: overviewActionsValue,
            badgeKind: overviewActionsKind
        ) {
            if model.wolTargets.isEmpty && model.commandShortcuts.isEmpty {
                LazyVGrid(columns: overviewActionColumns, alignment: .leading, spacing: 10) {
                    OverviewSetupActionTile(
                        title: "Add Device",
                        detail: "Wake-on-LAN",
                        systemImage: "power",
                        tint: wakeSectionTint,
                        kind: model.wolTargetManagementUnavailableReason == nil ? .action : .stale
                    ) {
                        AppFeedback.selection()
                        selectedTab = .actions
                    }
                    OverviewSetupActionTile(
                        title: "Create Tile",
                        detail: commandSetupTileDetail,
                        systemImage: "terminal",
                        tint: commandSectionTint,
                        kind: model.commandUnavailableReason == nil ? .action : .stale
                    ) {
                        AppFeedback.selection()
                        selectedTab = .actions
                    }
                }
            } else {
                if model.wolTargets.isEmpty {
                    LazyVGrid(columns: overviewActionColumns, alignment: .leading, spacing: 10) {
                        OverviewSetupActionTile(
                            title: "Add Device",
                            detail: "Wake-on-LAN",
                            systemImage: "power",
                            tint: wakeSectionTint,
                            kind: model.wolTargetManagementUnavailableReason == nil ? .action : .stale
                        ) {
                            AppFeedback.selection()
                            selectedTab = .actions
                        }
                    }
                } else {
                    DashboardSubsectionHeader(
                        title: "Wake",
                        detail: wakeOverviewSubtitle,
                        systemImage: "power",
                        tint: wakeSectionTint
                    )
                    LazyVGrid(columns: overviewActionColumns, alignment: .leading, spacing: 10) {
                        ForEach(overviewWOLTargets) { target in
                            let reason = model.wolWakeUnavailableReason(for: target)
                            OverviewWakeActionTile(
                                target: target,
                                state: model.wakeStates[target.id],
                                isEnabled: reason == nil,
                                disabledReason: wolUnavailableDisplayReason(for: target, reason: reason),
                                bridgeName: activeBridgeName,
                                bridgeReachable: model.bridgeReachable,
                                lastUpdatedAt: model.wolTargetsUpdatedAt ?? target.updatedAt,
                                widgetPinned: model.isWidgetActionSelected(kind: .wol, actionID: target.id)
                            ) {
                                Task { await wakeTarget(target) }
                            }
                        }
                    }
                }

                if model.commandShortcuts.isEmpty {
                    LazyVGrid(columns: overviewActionColumns, alignment: .leading, spacing: 10) {
                        OverviewSetupActionTile(
                            title: "Create Tile",
                            detail: commandSetupTileDetail,
                            systemImage: "terminal",
                            tint: commandSectionTint,
                            kind: model.commandUnavailableReason == nil ? .action : .stale
                        ) {
                            AppFeedback.selection()
                            selectedTab = .actions
                        }
                    }
                } else {
                    DashboardSubsectionHeader(
                        title: "Run",
                        detail: commandOverviewSubtitle,
                        systemImage: "terminal",
                        tint: commandSectionTint
                    )
                    LazyVGrid(columns: overviewActionColumns, alignment: .leading, spacing: 10) {
                        ForEach(overviewCommandShortcuts) { shortcut in
                            OverviewCommandActionTile(
                                shortcut: shortcut,
                                isRunning: model.runningCommandShortcutID == shortcut.id,
                                commandRunning: model.commandRunning,
                                bridgeName: activeBridgeName,
                                bridgeReachable: model.bridgeReachable,
                                commandEnabled: model.canRunCommands,
                                disabledReason: commandUnavailableDisplayReason,
                                widgetPinned: model.isWidgetActionSelected(kind: .command, actionID: shortcut.id.uuidString)
                            ) {
                                focusedField = nil
                                Task { await runCommandShortcut(shortcut) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overviewActivitySection: some View {
        DashboardSectionBand(
            title: "Recent Runs",
            systemImage: "clock.arrow.circlepath",
            tint: activitySectionTint,
            badgeTitle: activityBadgeTitle,
            badgeKind: activitySummaryKind
        ) {
            if let message = model.activityErrorMessage {
                SectionNoticeRow(
                    title: "Activity Refresh Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
            } else if recentActivityRecords.isEmpty {
                SectionNoticeRow(
                    title: "No Runs",
                    message: "Wake a device or run a tile.",
                    systemImage: "clock.arrow.circlepath",
                    tint: AppDesign.Palette.stale
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recentActivityRecords.enumerated()), id: \.element.id) { index, record in
                        ActivityTimelineRow(
                            record: record,
                            bridgeName: activeBridgeName,
                            isLive: model.bridgeReachable,
                            isFirst: index == 0,
                            isLast: index == recentActivityRecords.count - 1
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dashboardErrorBanner: some View {
        if let errorMessage = model.errorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppDesign.Palette.warning)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs Attention")
                        .font(.subheadline.weight(.semibold))
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if model.credential != nil {
                        AppIconButton(
                            systemImage: "arrow.clockwise",
                            accessibilityLabel: "Retry refresh",
                            tint: AppDesign.Palette.warning,
                            isRunning: dashboardRefreshing,
                            runningReason: "Refreshing the active bridge and dashboard data."
                        ) {
                            Task { await refreshFromDashboard() }
                        }
                    }
                    Button {
                        AppFeedback.selection()
                        model.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: AppDesign.Size.iconButton, height: AppDesign.Size.iconButton)
                    }
                    .buttonStyle(AppPressButtonStyle(tint: AppDesign.Palette.stale))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss message")
                }
            }
            .padding(14)
            .appSemanticPanel(
                tint: AppDesign.Palette.warning,
                cornerRadius: AppDesign.Radius.section,
                prominence: .standard
            )
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        DashboardSectionBand(
            title: "Health",
            systemImage: "waveform.path.ecg",
            tint: healthSectionTint,
            badgeTitle: healthOverviewValue,
            badgeKind: healthSectionBadgeKind
        ) {
            if deletingMonitorID != nil {
                SectionStatusRow(
                    title: "Deleting Monitor",
                    message: healthOperationMessage ?? "Deleting monitor",
                    systemImage: "trash",
                    tint: AppDesign.Palette.destructive,
                    progress: true
                )
            } else if let healthOperationMessage {
                SectionStatusRow(
                    title: "Monitor Updated",
                    message: healthOperationMessage,
                    systemImage: "checkmark.circle",
                    tint: AppDesign.Palette.success
                )
            }
            if let healthOperationError {
                SectionNoticeRow(
                    title: "Monitor Action Failed",
                    message: healthOperationError,
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
            }

            if model.healthMonitors.isEmpty {
                if let reason = healthMonitorControlsDisplayReason {
                    SectionNoticeRow(
                        title: "Monitors Unavailable",
                        message: reason,
                        systemImage: "exclamationmark.triangle",
                        tint: AppDesign.Palette.warning
                    )
                } else {
                    AppEmptyState(
                        title: "No Monitors",
                        message: "Add TCP or HTTP checks.",
                        systemImage: "waveform.path.ecg",
                        tint: AppDesign.Palette.health
                    )
                }
            } else {
                if let message = model.healthMonitorsErrorMessage {
                    SectionNoticeRow(
                        title: "Monitor Refresh Failed",
                        message: message,
                        systemImage: "exclamationmark.triangle",
                        tint: AppDesign.Palette.warning
                    )
                } else if let reason = healthMonitorControlsDisplayReason {
                    SectionNoticeRow(
                        title: "Monitor Management Unavailable",
                        message: reason,
                        systemImage: "lock",
                        tint: AppDesign.Palette.locked
                    )
                }
                HealthSummaryRow(
                    monitors: model.healthMonitors,
                    isLive: model.bridgeReachable,
                    lastUpdatedAt: model.healthMonitorsUpdatedAt
                )
                healthMonitorGroups
            }

            AppActionButton(
                title: "Add Monitor",
                systemImage: "plus",
                kind: .action,
                isEnabled: addMonitorDisabledReason == nil,
                disabledReason: addMonitorDisabledReason
            ) {
                AppFeedback.selection()
                healthOperationMessage = nil
                healthOperationError = nil
                monitorEditor = HealthMonitorEditorState(monitor: nil)
            }
            if let reason = addMonitorDisabledReason {
                AppDisabledReasonRow(reason: reason)
            }
        }
    }

    @ViewBuilder
    private var healthMonitorGroups: some View {
        if !model.bridgeReachable {
            DashboardSubsectionHeader(
                title: "Cached Checks",
                detail: model.healthMonitorsUpdatedAt.map { "last confirmed \(compactRelativeUpdateText($0))" } ?? "bridge offline",
                systemImage: "clock.badge.exclamationmark",
                tint: AppDesign.Palette.stale
            )
            healthMonitorList(healthMonitorsSortedForDisplay)
        } else {
            if !healthDownMonitors.isEmpty {
                DashboardSubsectionHeader(
                    title: "Needs Attention",
                    detail: healthDownMonitors.count == 1 ? "1 monitor down" : "\(healthDownMonitors.count) monitors down",
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
                healthMonitorList(healthDownMonitors)
            }

            if !healthUnknownMonitors.isEmpty {
                DashboardSubsectionHeader(
                    title: "Unknown",
                    detail: healthUnknownMonitors.count == 1 ? "1 check waiting" : "\(healthUnknownMonitors.count) checks waiting",
                    systemImage: "questionmark.circle",
                    tint: AppDesign.Palette.stale
                )
                healthMonitorList(healthUnknownMonitors)
            }

            if !healthUpMonitors.isEmpty {
                DashboardSubsectionHeader(
                    title: "Confirmed Up",
                    detail: healthUpMonitors.count == 1 ? "1 check confirmed" : "\(healthUpMonitors.count) checks confirmed",
                    systemImage: "checkmark.circle",
                    tint: AppDesign.Palette.success
                )
                healthMonitorList(healthUpMonitors)
            }
        }
    }

    @ViewBuilder
    private func healthMonitorList(_ monitors: [HealthMonitor]) -> some View {
        ForEach(monitors) { monitor in
            healthMonitorRow(monitor)
        }
    }

    private func healthMonitorRow(_ monitor: HealthMonitor) -> some View {
        HealthMonitorRow(monitor: monitor, isLive: model.bridgeReachable)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if monitor.source == "user", model.healthMonitorControlsUnavailableReason == nil, deletingMonitorID == nil {
                    Button {
                        AppFeedback.selection()
                        healthOperationMessage = nil
                        healthOperationError = nil
                        monitorEditor = HealthMonitorEditorState(monitor: monitor)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        AppFeedback.selection()
                        pendingMonitorDeletion = monitor
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    @ViewBuilder
    private var operationsHeader: some View {
        DashboardOperationsHeader(
            credential: model.credential,
            bridgeHealthy: model.bridgeHealthy,
            bridgeReachable: model.bridgeReachable,
            statusText: model.bridgeStatusText,
            bridgeHealth: model.bridgeHealth,
            metrics: overviewMetrics,
            lastConfirmedText: overviewLastConfirmedText,
            showsFocusRow: overviewShouldShowFocusRow,
            focusTitle: overviewSituationTitle,
            focusDetail: overviewSituationDetail,
            focusSystemImage: overviewSituationSystemImage,
            focusKind: overviewSituationKind,
            primaryTitle: overviewPrimaryActionTitle,
            primarySystemImage: overviewPrimaryActionSystemImage,
            primaryKind: overviewPrimaryActionKind,
            primaryAction: overviewPrimaryAction,
            isRefreshing: dashboardRefreshing,
            refresh: {
                Task { await refreshFromDashboard() }
            },
            pairBridge: {
                AppFeedback.selection()
                showingPairing = true
            }
        )
    }

    @ViewBuilder
    private var wakeSection: some View {
        DashboardSectionBand(
            title: "Devices",
            systemImage: "power",
            tint: wakeSectionTint,
            badgeTitle: wakeOverviewValue,
            badgeKind: wakeSectionBadgeKind
        ) {
            if model.credential == nil {
                AppNoticeRow(
                    title: "Add Bridge",
                    message: "Add a bridge to wake devices.",
                    systemImage: "lock",
                    tint: AppDesign.Palette.locked
                )
            } else {
                if deletingTargetID != nil {
                    SectionStatusRow(
                        title: "Deleting Device",
                        message: wakeOperationMessage ?? "Deleting device",
                        systemImage: "trash",
                        tint: AppDesign.Palette.destructive,
                        progress: true
                    )
                } else if let wakeOperationMessage {
                    SectionStatusRow(
                        title: "Device Updated",
                        message: wakeOperationMessage,
                        systemImage: "checkmark.circle",
                        tint: AppDesign.Palette.success
                    )
                }
                if let wakeOperationError {
                    SectionNoticeRow(
                        title: "Device Action Failed",
                        message: wakeOperationError,
                        systemImage: "exclamationmark.triangle",
                        tint: AppDesign.Palette.warning
                    )
                }

                if shouldShowWakeReadinessPanel {
                    WOLReadinessPanel(
                        title: wakeReadinessTitle,
                        detail: wakeReadinessDetail,
                        bridgeName: activeBridgeName,
                        kind: wakeReadinessKind,
                        metrics: wakeReadinessMetrics
                    )
                }

                if model.wolTargets.isEmpty {
                    if let reason = wolTargetManagementDisplayReason ?? wolControlsDisplayReason {
                        SectionNoticeRow(
                            title: "Devices Unavailable",
                            message: reason,
                            systemImage: "exclamationmark.triangle",
                            tint: AppDesign.Palette.warning
                        )
                    } else {
                        AppEmptyState(
                            title: "No Devices",
                            message: "Add WOL targets.",
                            systemImage: "desktopcomputer",
                            tint: AppDesign.Palette.wake
                        )
                    }
                } else {
                    if let message = model.wolTargetsErrorMessage {
                        SectionNoticeRow(
                            title: "Device Refresh Failed",
                            message: message,
                            systemImage: "exclamationmark.triangle",
                            tint: AppDesign.Palette.warning
                        )
                    } else if let reason = wolControlsDisplayReason {
                        SectionNoticeRow(
                            title: model.bridgeReachable ? "Wake Unavailable" : "Last Confirmed Devices",
                            message: reason,
                            systemImage: model.bridgeReachable ? "bolt.slash" : "clock.badge.exclamationmark",
                            tint: AppDesign.Palette.cached
                        )
                    } else if let reason = wolTargetManagementDisplayReason {
                        SectionNoticeRow(
                            title: "Device Management Unavailable",
                            message: reason,
                            systemImage: "lock",
                            tint: AppDesign.Palette.locked
                        )
                    }
                    wolTargetGrid(targets: model.wolTargets)
                }

                AppActionButton(
                    title: "Add Device",
                    systemImage: "plus",
                    kind: .action,
                    isEnabled: addDeviceDisabledReason == nil,
                    disabledReason: addDeviceDisabledReason
                ) {
                    AppFeedback.selection()
                    wakeOperationMessage = nil
                    wakeOperationError = nil
                    targetEditor = TargetEditorState(target: nil)
                }
                if let reason = addDeviceDisabledReason {
                    AppDisabledReasonRow(reason: reason)
                }
            }
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        if model.credential == nil {
            DashboardSectionBand(
                title: "Commands",
                systemImage: "terminal",
                tint: commandSectionTint
            ) {
                AppNoticeRow(
                    title: "Add Bridge",
                    message: "Add a bridge to run commands.",
                    systemImage: "lock",
                    tint: AppDesign.Palette.locked
                )
            }
        } else {
            commandTilesSection
            manualCommandSection
            latestCommandResultSection
        }
    }

    @ViewBuilder
    private var commandTilesSection: some View {
        DashboardSectionBand(
            title: "Command Tiles",
            systemImage: "square.grid.2x2",
            tint: commandSectionTint,
            badgeTitle: commandOverviewValue,
            badgeKind: commandSectionBadgeKind
        ) {
            if model.commandShortcuts.isEmpty {
                AppEmptyState(
                    title: "No Command Tiles",
                    message: "Save repeatable commands from Run Once.",
                    systemImage: "terminal",
                    tint: AppDesign.Palette.command
                )
            } else {
                commandShortcutGrid(shortcuts: model.commandShortcuts)
            }
        }
    }

    @ViewBuilder
    private var manualCommandSection: some View {
        DashboardSectionBand(
            title: "Run Once",
            systemImage: "terminal",
            tint: commandSectionTint
        ) {
            if let reason = commandUnavailableDisplayReason {
                CommandUnavailableRow(reason: reason)
            }

            ManualCommandPanel(
                isExpanded: manualCommandPanelExpanded,
                canCollapse: manualCommandCanCollapse,
                bridgeName: activeBridgeName,
                commandPreview: commandText,
                commandEnabled: model.canRunCommands,
                disabledReason: commandUnavailableDisplayReason,
                toggle: {
                    AppFeedback.selection()
                    withAnimation(AppDesign.Motion.stateChange) {
                        manualCommandExpanded.toggle()
                    }
                }
            ) {
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
                    commandDisabledReason: commandUnavailableDisplayReason,
                    focusedField: $focusedField,
                    run: {
                        focusedField = nil
                        Task { await runCommandFromDashboard() }
                    },
                    save: {
                        AppFeedback.selection()
                        focusedField = nil
                        commandEditor = CommandEditorState(
                            shortcut: nil,
                            initialCommand: commandText,
                            clearComposerOnSave: true
                        )
                    },
                    clear: {
                        AppFeedback.selection()
                        focusedField = nil
                        commandText = ""
                        model.clearCommandResult()
                        if !model.commandShortcuts.isEmpty {
                            withAnimation(AppDesign.Motion.stateChange) {
                                manualCommandExpanded = false
                            }
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var latestCommandResultSection: some View {
        if let status = model.commandStatusText {
            DashboardSectionBand(
                title: "Latest Result",
                systemImage: model.commandRunning ? "hourglass" : (model.commandSucceeded ? "checkmark.circle" : "exclamationmark.triangle"),
                tint: model.commandRunning ? commandSectionTint : (model.commandSucceeded ? AppDesign.Palette.success : AppDesign.Palette.warning),
                badgeTitle: model.commandRunning ? "Running" : (model.commandSucceeded ? "Done" : "Failed"),
                badgeKind: model.commandRunning ? .action : (model.commandSucceeded ? .success : .warning)
            ) {
                CommandResultRow(
                    title: model.commandResultTitle,
                    command: model.commandResultCommand,
                    bridgeName: model.commandResultBridgeName ?? activeBridgeName,
                    status: status,
                    output: model.commandOutputText,
                    succeeded: model.commandSucceeded,
                    isRunning: model.commandRunning,
                    updatedAt: model.commandResultUpdatedAt,
                    retry: commandResultRetryAction
                )
            }
        }
    }

    @ViewBuilder
    private func wolTargetGrid(targets: [WOLTarget]) -> some View {
        WOLTargetGrid(
            targets: targets,
            wakeStates: model.wakeStates,
            deletingTargetID: deletingTargetID,
            bridgeName: activeBridgeName,
            bridgeReachable: model.bridgeReachable,
            lastUpdatedAt: model.wolTargetsUpdatedAt,
            widgetPinned: { target in
                model.isWidgetActionSelected(kind: .wol, actionID: target.id)
            },
            wakeUnavailableReason: { target in
                wolUnavailableDisplayReason(for: target, reason: model.wolWakeUnavailableReason(for: target))
            },
            canManage: { target in
                target.source != "config"
                    && model.wolTargetManagementUnavailableReason == nil
                    && deletingTargetID == nil
            },
            toggleWidgetPin: { target in
                let wasPinned = model.isWidgetActionSelected(kind: .wol, actionID: target.id)
                if model.toggleWidgetActionSelection(
                    kind: .wol,
                    actionID: target.id,
                    title: "Wake \(target.name)",
                    subtitle: target.ipAddress ?? target.broadcastIP
                ) {
                    AppFeedback.success()
                    showFeedback(
                        title: wasPinned ? "Trust Removed" : "Trusted Action Added",
                        message: wasPinned ? "\(target.name) was removed from trusted actions." : "Wake \(target.name) is trusted for widgets.",
                        systemImage: wasPinned ? "checkmark.seal" : "checkmark.seal.fill",
                        tint: wasPinned ? AppDesign.Palette.stale : AppDesign.Palette.success
                    )
                } else {
                    AppFeedback.failure()
                    showFeedback(
                        title: "Widget Trust Failed",
                        message: "The active bridge could not update trusted actions.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: AppDesign.Palette.warning
                    )
                }
            },
            edit: { target in
                AppFeedback.selection()
                wakeOperationMessage = nil
                wakeOperationError = nil
                targetEditor = TargetEditorState(target: target)
            },
            delete: { target in
                AppFeedback.selection()
                pendingTargetDeletion = target
            },
            wake: { target in
                Task { await wakeTarget(target) }
            }
        )
    }

    @ViewBuilder
    private func commandShortcutGrid(shortcuts: [CommandShortcut]) -> some View {
        CommandShortcutGrid(
            shortcuts: shortcuts,
            commandRunning: model.commandRunning,
            runningShortcutID: model.runningCommandShortcutID,
            bridgeName: activeBridgeName,
            bridgeReachable: model.bridgeReachable,
            commandEnabled: model.canRunCommands,
            commandDisabledReason: commandUnavailableDisplayReason,
            run: { shortcut in
                focusedField = nil
                Task { await runCommandShortcut(shortcut) }
            },
            edit: { shortcut in
                AppFeedback.selection()
                focusedField = nil
                commandEditor = CommandEditorState(
                    shortcut: shortcut,
                    initialCommand: shortcut.command,
                    clearComposerOnSave: false
                )
            },
            delete: { shortcut in
                AppFeedback.selection()
                focusedField = nil
                pendingCommandDeletion = shortcut
            },
            widgetPinned: { shortcut in
                model.isWidgetActionSelected(kind: .command, actionID: shortcut.id.uuidString)
            },
            toggleWidgetPin: { shortcut in
                let wasPinned = model.isWidgetActionSelected(kind: .command, actionID: shortcut.id.uuidString)
                if model.toggleWidgetActionSelection(
                    kind: .command,
                    actionID: shortcut.id.uuidString,
                    title: shortcut.name,
                    subtitle: shortcut.command
                ) {
                    AppFeedback.success()
                    showFeedback(
                        title: wasPinned ? "Trust Removed" : "Trusted Action Added",
                        message: wasPinned ? "\(shortcut.name) was removed from trusted actions." : "\(shortcut.name) is trusted for widgets.",
                        systemImage: wasPinned ? "checkmark.seal" : "checkmark.seal.fill",
                        tint: wasPinned ? AppDesign.Palette.stale : AppDesign.Palette.success
                    )
                } else {
                    AppFeedback.failure()
                    showFeedback(
                        title: "Widget Trust Failed",
                        message: "The active bridge could not update trusted actions.",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: AppDesign.Palette.warning
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var statusSignalsSection: some View {
        DashboardSectionBand(
            title: "Status Alerts",
            systemImage: "rectangle.stack",
            tint: statusSectionTint,
            badgeTitle: statusSnapshotBadgeTitle,
            badgeKind: statusSnapshotBadgeKind
        ) {
            if let message = model.statusSnapshotsErrorMessage {
                SectionNoticeRow(
                    title: "Status Refresh Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
            }
            if !statusSignalCards.isEmpty {
                SectionNoticeRow(
                    title: model.bridgeReachable ? "Needs Attention" : "Cached Attention",
                    message: model.bridgeReachable
                        ? "\(activeBridgeName) reported status snapshots that need review."
                        : "These snapshots may be old. Reconnect \(activeBridgeName) for live status.",
                    systemImage: model.bridgeReachable ? "exclamationmark.triangle" : "clock.badge.exclamationmark",
                    tint: statusSectionTint
                )
            }
            ForEach(statusSignalCards) { card in
                CardRow(card: card)
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        DashboardSectionBand(
            title: "Run Log",
            systemImage: "clock.arrow.circlepath",
            tint: activitySectionTint,
            badgeTitle: activityBadgeTitle,
            badgeKind: activitySummaryKind
        ) {
            if let message = model.activityErrorMessage {
                SectionNoticeRow(
                    title: "Activity Refresh Failed",
                    message: message,
                    systemImage: "exclamationmark.triangle",
                    tint: AppDesign.Palette.warning
                )
            } else if model.auditRecords.isEmpty {
                AppEmptyState(
                    title: "No Runs Yet",
                    message: "Wake a device or run a saved command to start the audit trail.",
                    systemImage: "clock.arrow.circlepath"
                )
            }
            if !model.auditRecords.isEmpty {
                if !model.bridgeReachable {
                    SectionNoticeRow(
                        title: "Cached Audit",
                        message: overviewLastConfirmedText.map { "Cached from \(activeBridgeName). Last confirmed \($0)." } ?? "Cached from \(activeBridgeName).",
                        systemImage: "clock.badge.exclamationmark",
                        tint: AppDesign.Palette.stale
                    )
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.auditRecords.enumerated()), id: \.element.id) { index, record in
                        ActivityTimelineRow(
                            record: record,
                            bridgeName: activeBridgeName,
                            isLive: model.bridgeReachable,
                            isFirst: index == 0,
                            isLast: index == model.auditRecords.count - 1
                        )
                    }
                }
            }
        }
    }

    private func tabTint(_ tab: DashboardTab) -> Color {
        switch tab {
        case .overview:
            return bridgeOverviewTint
        case .health:
            return healthSectionTint
        case .actions:
            return actionTabTint
        case .activity:
            return activitySectionTint
        case .settings:
            return AppDesign.Palette.action
        }
    }

    private var actionTabTint: Color {
        if model.credential == nil {
            return AppDesign.Palette.stale
        }
        if wakeOperationError != nil
            || model.wolTargetsErrorMessage != nil
            || (model.commandStatusText != nil && !model.commandSucceeded) {
            return AppDesign.Palette.warning
        }
        if model.commandSucceeded {
            return AppDesign.Palette.success
        }
        if model.bridgeReachable && (!model.wolTargets.isEmpty || !model.commandShortcuts.isEmpty || model.commandUnavailableReason == nil) {
            return AppDesign.Palette.command
        }
        return AppDesign.Palette.stale
    }

    private var bridgeStatusKind: AppStatusKind {
        guard model.credential != nil else {
            return .stale
        }
        if model.bridgeHealthy {
            return .success
        }
        return model.bridgeReachable ? .warning : .stale
    }

    private var bridgeStatusDetail: String? {
        guard let credential = model.credential else {
            return "Add local bridge"
        }
        if model.bridgeReachable, let bridgeHealth = model.bridgeHealth {
            return "\(credential.bridgeName) · up \(Self.shortDuration(seconds: bridgeHealth.uptimeSeconds))"
        }
        if let overviewLastConfirmedText {
            return "Last confirmed \(overviewLastConfirmedText)"
        }
        return "No confirmed cache yet"
    }

    private func bridgeRequiredTitle(for tab: DashboardTab) -> String {
        switch tab {
        case .health, .actions, .activity, .overview, .settings:
            return "Add Bridge"
        }
    }

    private func bridgeRequiredMessage(for tab: DashboardTab) -> String {
        switch tab {
        case .health:
            return "Live checks need a bridge."
        case .actions:
            return "Wake and command actions run through the bridge."
        case .activity:
            return "Audit history comes from the bridge."
        case .overview, .settings:
            return "Add a trusted local bridge."
        }
    }

    private var overviewAlertMonitors: [HealthMonitor] {
        Array(
            model.healthMonitors
                .filter { healthPriorityRank($0) < 2 }
                .sorted { lhs, rhs in
                    if healthPriorityRank(lhs) == healthPriorityRank(rhs) {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return healthPriorityRank(lhs) < healthPriorityRank(rhs)
                }
                .prefix(2)
        )
    }

    private func healthPriorityRank(_ monitor: HealthMonitor) -> Int {
        switch monitor.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "down":
            return 0
        case "up":
            return 2
        default:
            return 1
        }
    }

    private var healthMonitorsSortedForDisplay: [HealthMonitor] {
        model.healthMonitors.sorted { lhs, rhs in
            if healthPriorityRank(lhs) == healthPriorityRank(rhs) {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return healthPriorityRank(lhs) < healthPriorityRank(rhs)
        }
    }

    private var healthDownMonitors: [HealthMonitor] {
        healthMonitorsSortedForDisplay.filter { healthPriorityRank($0) == 0 }
    }

    private var healthUnknownMonitors: [HealthMonitor] {
        healthMonitorsSortedForDisplay.filter { healthPriorityRank($0) == 1 }
    }

    private var healthUpMonitors: [HealthMonitor] {
        healthMonitorsSortedForDisplay.filter { healthPriorityRank($0) == 2 }
    }

    private var overviewWOLTargets: [WOLTarget] {
        let pinned = model.wolTargets.filter { target in
            model.isWidgetActionSelected(kind: .wol, actionID: target.id)
        }
        return Array((pinned.isEmpty ? model.wolTargets : pinned).prefix(2))
    }

    private var overviewCommandShortcuts: [CommandShortcut] {
        let pinned = model.commandShortcuts.filter { shortcut in
            model.isWidgetActionSelected(kind: .command, actionID: shortcut.id.uuidString)
        }
        return Array((pinned.isEmpty ? model.commandShortcuts : pinned).prefix(2))
    }

    private var overviewActionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 166), spacing: 10)]
    }

    private var shouldShowOverviewActivity: Bool {
        model.activityErrorMessage != nil || !recentActivityRecords.isEmpty || activityFailureCount > 0
    }

    private var shouldShowStatusSignals: Bool {
        model.statusSnapshotsErrorMessage != nil || !statusSignalCards.isEmpty
    }

    private var statusSignalCards: [CardSnapshot] {
        model.cards.filter { statusCardNeedsAttention($0) }
    }

    private func statusCardNeedsAttention(_ card: CardSnapshot) -> Bool {
        if card.error?.nilIfBlank != nil {
            return true
        }
        if card.stale && model.bridgeReachable {
            return true
        }
        switch AppStatusKind(status: card.status) {
        case .warning, .destructive:
            return true
        case .success, .stale, .action:
            return false
        }
    }

    private var actionModeItems: [DashboardActionModeItem] {
        [
            DashboardActionModeItem(
                mode: .wake,
                value: wakeOverviewValue,
                detail: wakeOverviewSubtitle,
                tint: wakeSectionTint,
                kind: wakeSectionBadgeKind
            ),
            DashboardActionModeItem(
                mode: .run,
                value: commandOverviewValue,
                detail: commandOverviewSubtitle,
                tint: commandSectionTint,
                kind: commandSectionBadgeKind
            )
        ]
    }

    private var commandSetupTileDetail: String {
        if let reason = commandUnavailableDisplayReason {
            return reason
        }
        return "Save an SSH or shell command."
    }

    private var manualCommandPanelExpanded: Bool {
        manualCommandExpanded
            || model.commandShortcuts.isEmpty
            || !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var manualCommandCanCollapse: Bool {
        !model.commandShortcuts.isEmpty
            && commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.commandRunning
    }

    private var commandUnavailableDisplayReason: String? {
        guard let reason = model.commandUnavailableReason else {
            return nil
        }
        return trustAwareMessage(reason, lastConfirmedAt: overviewLastConfirmedAt)
    }

    private var commandResultRetryAction: (() -> Void)? {
        guard !model.commandRunning,
              !model.commandSucceeded,
              let command = model.commandResultCommand?.nilIfBlank
        else {
            return nil
        }
        return {
            AppFeedback.selection()
            focusedField = nil
            commandText = command
            Task { await runCommandFromDashboard() }
        }
    }

    private func wolUnavailableDisplayReason(for target: WOLTarget, reason: String?) -> String? {
        guard let reason else {
            return nil
        }
        return trustAwareMessage(reason, lastConfirmedAt: model.wolTargetsUpdatedAt ?? target.updatedAt)
    }

    private var recentActivityRecords: [AuditRecord] {
        Array(model.auditRecords.prefix(3))
    }

    private var activityBadgeTitle: String {
        if model.credential == nil {
            return "Locked"
        }
        if activityFailureCount > 0 {
            return activityFailureCount == 1 ? "1 Failed" : "\(activityFailureCount) Failed"
        }
        if model.auditRecords.isEmpty {
            return "No Runs"
        }
        return model.bridgeReachable ? "Confirmed" : "Cached"
    }

    private var activityFailureCount: Int {
        model.auditRecords.filter { activityStatusKind($0.status) == .warning }.count
    }

    private var activityCompletedCount: Int {
        model.auditRecords.filter { activityStatusKind($0.status) == .success }.count
    }

    private var overviewSituationTitle: String {
        if !model.bridgeReachable {
            return "Cached Snapshot"
        }
        if healthDownCount > 0 {
            return healthDownCount == 1 ? "One Monitor Down" : "\(healthDownCount) Monitors Down"
        }
        if activityFailureCount > 0 {
            return activityFailureCount == 1 ? "One Recent Failure" : "\(activityFailureCount) Recent Failures"
        }
        if model.healthMonitors.isEmpty {
            return "Monitoring Not Set"
        }
        if healthUnknownCount > 0 {
            return healthUnknownCount == 1 ? "One Check Unknown" : "\(healthUnknownCount) Checks Unknown"
        }
        return "Checks Confirmed"
    }

    private var overviewSituationDetail: String {
        if !model.bridgeReachable {
            let confirmation = overviewLastConfirmedText.map { " Last confirmed \($0)." } ?? " No confirmed cache yet."
            return "\(activeBridgeName) is offline.\(confirmation)"
        }
        if healthDownCount > 0 {
            return "\(overviewDownMonitorNames) need attention."
        }
        if activityFailureCount > 0 {
            return "Review failed WOL or command runs."
        }
        if model.healthMonitors.isEmpty {
            return "Add HTTP or TCP checks so Status can prove what is healthy."
        }
        if healthUnknownCount > 0 {
            return "Some checks have not produced a confirmed healthy result yet."
        }
        return "\(healthUpCount) checks confirmed."
    }

    private var overviewSituationKind: AppStatusKind {
        if !model.bridgeReachable || model.healthMonitors.isEmpty {
            return .stale
        }
        if healthDownCount > 0 || activityFailureCount > 0 {
            return .warning
        }
        if healthUnknownCount > 0 {
            return .stale
        }
        return .success
    }

    private var overviewSituationSystemImage: String {
        switch overviewSituationKind {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .stale:
            return model.bridgeReachable ? "clock.badge.questionmark" : "clock.badge.exclamationmark"
        case .action:
            return "bolt.circle.fill"
        case .destructive:
            return "trash.circle.fill"
        }
    }

    private var overviewShouldShowFocusRow: Bool {
        model.credential == nil || overviewSituationKind != .success
    }

    private var overviewPrimaryActionTitle: String {
        if !model.bridgeReachable {
            return "Bridge Settings"
        }
        if healthDownCount > 0 || healthUnknownCount > 0 || model.healthMonitors.isEmpty {
            return "Open Monitors"
        }
        return "Open Actions"
    }

    private var overviewPrimaryActionSystemImage: String {
        if !model.bridgeReachable {
            return "gearshape"
        }
        if healthDownCount > 0 || healthUnknownCount > 0 || model.healthMonitors.isEmpty {
            return "waveform.path.ecg"
        }
        return "bolt.circle"
    }

    private var overviewPrimaryActionKind: AppStatusKind {
        if !model.bridgeReachable {
            return .stale
        }
        if healthDownCount > 0 || healthUnknownCount > 0 {
            return .warning
        }
        return .action
    }

    private var overviewPrimaryAction: () -> Void {
        {
            AppFeedback.selection()
            if !model.bridgeReachable {
                selectedTab = .settings
            } else if healthDownCount > 0 || healthUnknownCount > 0 || model.healthMonitors.isEmpty {
                selectedTab = .health
            } else {
                selectedTab = .actions
            }
        }
    }

    private var overviewBridgeMetricDetail: String {
        if model.bridgeReachable {
            return "\(activeBridgeName) · \(model.bridgeStatusText)"
        }
        return overviewLastConfirmedText.map { "Last confirmed \($0)" } ?? "No confirmed cache yet"
    }

    private var overviewBridgeMetricValue: String {
        guard model.credential != nil else {
            return "Add"
        }
        if model.bridgeHealthy {
            return "Live"
        }
        return model.bridgeReachable ? "Check" : "Cached"
    }

    private var overviewBridgeMetricIcon: String {
        guard model.credential != nil else {
            return "link.badge.plus"
        }
        if model.bridgeHealthy {
            return "antenna.radiowaves.left.and.right.circle.fill"
        }
        return model.bridgeReachable ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark"
    }

    private var overviewMetrics: [DashboardHeaderMetric] {
        [
            DashboardHeaderMetric(
                title: "Bridge",
                value: overviewBridgeMetricValue,
                detail: overviewBridgeMetricDetail,
                systemImage: overviewBridgeMetricIcon,
                tint: bridgeOverviewTint,
                isStale: model.credential == nil || !model.bridgeReachable
            ),
            DashboardHeaderMetric(
                title: "Health",
                value: healthOverviewValue,
                detail: healthOverviewSubtitle,
                systemImage: "waveform.path.ecg",
                tint: healthOverviewTint,
                isStale: healthSectionBadgeKind == .stale
            ),
            DashboardHeaderMetric(
                title: "Actions",
                value: overviewActionsMetricValue,
                detail: overviewActionsDetail,
                systemImage: "bolt.circle.fill",
                tint: operateSectionTint,
                isStale: overviewActionsKind == .stale
            ),
            DashboardHeaderMetric(
                title: "Runs",
                value: overviewRecentMetricValue,
                detail: overviewRecentDetail,
                systemImage: "clock.arrow.circlepath",
                tint: activitySummaryTint,
                isStale: activitySummaryKind == .stale
            )
        ]
    }

    private var overviewSavedActionCount: Int {
        model.wolTargets.count + model.commandShortcuts.count
    }

    private var overviewReadyActionCount: Int {
        guard model.bridgeReachable else {
            return 0
        }
        return wakeReadyCount + commandReadyCount
    }

    private var overviewLockedActionCount: Int {
        max(0, overviewSavedActionCount - overviewReadyActionCount)
    }

    private var overviewActionsValue: String {
        if overviewSavedActionCount == 0 {
            return "None"
        }
        if !model.bridgeReachable {
            return "Cached"
        }
        return "\(overviewReadyActionCount) Available"
    }

    private var overviewActionsMetricValue: String {
        if overviewSavedActionCount == 0 {
            return "None"
        }
        if !model.bridgeReachable {
            return "Cached"
        }
        return "\(overviewReadyActionCount) Ready"
    }

    private var overviewActionsDetail: String {
        let base = "\(model.wolTargets.count) wake · \(model.commandShortcuts.count) command"
        if overviewSavedActionCount == 0 {
            return model.bridgeReachable ? "Add WOL or command tiles" : "No saved actions"
        }
        if !model.bridgeReachable {
            return overviewLastConfirmedText.map { "\(base) · confirmed \($0)" } ?? base
        }
        if overviewReadyActionCount == overviewSavedActionCount {
            return base
        }
        let lockedNoun = overviewLockedActionCount == 1 ? "action" : "actions"
        return "\(base) · \(overviewLockedActionCount) locked \(lockedNoun)"
    }

    private var overviewActionsKind: AppStatusKind {
        if wakeSectionBadgeKind == .warning || commandSectionBadgeKind == .warning {
            return .warning
        }
        if overviewReadyActionCount > 0 {
            return .action
        }
        return .stale
    }

    private var overviewRecentValue: String {
        if activityFailureCount > 0 {
            return activityFailureCount == 1 ? "1 Failed" : "\(activityFailureCount) Failed"
        }
        if model.auditRecords.isEmpty {
            return "No Runs"
        }
        return "\(model.auditRecords.count)"
    }

    private var overviewRecentMetricValue: String {
        if activityFailureCount > 0 {
            return activityFailureCount == 1 ? "1 Failed" : "\(activityFailureCount) Failed"
        }
        if model.auditRecords.isEmpty {
            return "None"
        }
        return "\(model.auditRecords.count) Runs"
    }

    private var overviewRecentDetail: String {
        if model.auditRecords.isEmpty {
            return "No WOL or command history"
        }
        if !model.bridgeReachable {
            return overviewLastConfirmedText.map { "Cached · confirmed \($0)" } ?? "Cached history"
        }
        return "\(activityCompletedCount) done · \(activityFailureCount) failed"
    }

    private var overviewDownMonitorNames: String {
        let names = model.healthMonitors
            .filter { normalizedMonitorStatus($0.status) == "down" }
            .prefix(3)
            .map(\.name)
            .joined(separator: ", ")
        let extra = healthDownCount - min(healthDownCount, 3)
        if extra > 0 {
            return "\(names), +\(extra) more"
        }
        return names.nilIfBlank ?? "\(healthDownCount) monitors"
    }

    private var overviewLastConfirmedAt: Date? {
        [
            model.healthMonitorsUpdatedAt,
            model.wolTargetsUpdatedAt,
            model.cards.map(\.updatedAt).max(),
            model.auditRecords.map(\.createdAt).max()
        ]
        .compactMap { $0 }
        .max()
    }

    private var overviewLastConfirmedText: String? {
        overviewLastConfirmedAt.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) }
    }

    private var bridgeOverviewTint: Color {
        guard model.credential != nil else {
            return AppDesign.Palette.locked
        }
        if model.bridgeHealthy {
            return AppDesign.Palette.success
        }
        if model.bridgeStatusText == "Connection failed" || model.bridgeReachable {
            return AppDesign.Palette.warning
        }
        return AppDesign.Palette.cached
    }

    private var healthOverviewValue: String {
        guard model.credential != nil else {
            return "Locked"
        }
        guard !model.healthMonitors.isEmpty else {
            return "No Checks"
        }
        if !model.bridgeReachable {
            return "Cached"
        }
        if healthDownCount > 0 {
            return "\(healthDownCount) Down"
        }
        if healthUnknownCount > 0 {
            return "\(healthUnknownCount) Unknown"
        }
        return "Confirmed"
    }

    private var healthOverviewSubtitle: String {
        guard model.credential != nil else {
            return "Add bridge first"
        }
        guard !model.healthMonitors.isEmpty else {
            return "Add checks"
        }
        let counts = "\(healthUpCount) up · \(healthDownCount) down"
        guard let updated = model.healthMonitorsUpdatedAt else {
            return counts
        }
        if !model.bridgeReachable {
            return "\(counts) · confirmed \(compactRelativeUpdateText(updated))"
        }
        return "\(counts) · \(compactRelativeUpdateText(updated))"
    }

    private var healthOverviewTint: Color {
        guard model.credential != nil, !model.healthMonitors.isEmpty else {
            return AppDesign.Palette.locked
        }
        if !model.bridgeReachable {
            return AppDesign.Palette.cached
        }
        if healthDownCount > 0 {
            return AppDesign.Palette.warning
        }
        return healthUnknownCount > 0 ? AppDesign.Palette.stale : AppDesign.Palette.health
    }

    private var wakeOverviewValue: String {
        guard model.credential != nil else {
            return "Locked"
        }
        if model.wolTargets.isEmpty {
            return "No Devices"
        }
        return "\(model.wolTargets.count)"
    }

    private var wakeOverviewSubtitle: String {
        guard model.credential != nil else {
            return "Add bridge first"
        }
        let noun = model.wolTargets.count == 1 ? "wake target" : "wake targets"
        let base = model.wolTargets.isEmpty ? "Add devices" : "\(model.wolTargets.count) \(noun)"
        guard let updated = model.wolTargetsUpdatedAt, !model.wolTargets.isEmpty else {
            return base
        }
        if !model.bridgeReachable {
            return "\(base) · confirmed \(compactRelativeUpdateText(updated))"
        }
        return "\(base) · \(compactRelativeUpdateText(updated))"
    }

    private var wakeOverviewTint: Color {
        guard model.credential != nil, !model.wolTargets.isEmpty else {
            return AppDesign.Palette.locked
        }
        return model.bridgeReachable ? AppDesign.Palette.wake : AppDesign.Palette.cached
    }

    private var wakeReadyCount: Int {
        guard model.bridgeReachable else {
            return 0
        }
        return model.wolTargets.filter { model.wolWakeUnavailableReason(for: $0) == nil }.count
    }

    private var wakeLockedCount: Int {
        max(0, model.wolTargets.count - wakeReadyCount)
    }

    private var wakeTrustedActionCount: Int {
        model.widgetActionSelections.filter { $0.kind == .wol }.count
    }

    private var shouldShowWakeReadinessPanel: Bool {
        model.wolTargets.isEmpty
            || !model.bridgeReachable
            || wakeOperationError != nil
            || model.wolTargetsErrorMessage != nil
            || wakeLockedCount > 0
    }

    private var wakeReadinessTitle: String {
        guard model.credential != nil else {
            return "Add Bridge"
        }
        if model.wolTargets.isEmpty {
            return "No Devices Yet"
        }
        if !model.bridgeReachable {
            return "Cached Wake Targets"
        }
        if wakeLockedCount > 0 {
            return "\(wakeReadyCount) Can Wake"
        }
        return "Can Wake Now"
    }

    private var wakeReadinessDetail: String {
        guard model.credential != nil else {
            return "Wake-on-LAN needs a trusted local bridge."
        }
        if let reason = wolControlsDisplayReason {
            return reason
        }
        if model.wolTargets.isEmpty {
            return "Add devices that the bridge can wake on your LAN."
        }
        if !model.bridgeReachable {
            return model.wolTargetsUpdatedAt.map { "Cached targets. Last confirmed \(compactRelativeUpdateText($0))." }
                ?? "Cached targets from \(activeBridgeName)."
        }
        return "Selected devices wake through \(activeBridgeName)."
    }

    private var wakeReadinessKind: AppStatusKind {
        if model.credential == nil || model.wolTargets.isEmpty || !model.bridgeReachable {
            return .stale
        }
        if wakeOperationError != nil || model.wolTargetsErrorMessage != nil || wakeLockedCount > 0 {
            return .warning
        }
        return .action
    }

    private var wakeReadinessMetrics: [DashboardHeaderMetric] {
        [
            DashboardHeaderMetric(
                title: model.bridgeReachable ? "Can Wake" : "Cached",
                value: "\(wakeReadyCount)",
                detail: model.bridgeReachable ? "Can wake now" : "Cached state",
                systemImage: "power.circle.fill",
                tint: wakeReadyCount > 0 && model.bridgeReachable ? AppDesign.Palette.wake : AppDesign.Palette.stale,
                isStale: !model.bridgeReachable || wakeReadyCount == 0
            ),
            DashboardHeaderMetric(
                title: "Locked",
                value: "\(wakeLockedCount)",
                detail: wakeLockedCount == 0 ? "No blocked devices" : "Need bridge or config",
                systemImage: wakeLockedCount == 0 ? "checkmark.circle.fill" : "lock.fill",
                tint: wakeLockedCount == 0 ? AppDesign.Palette.success : AppDesign.Palette.warning,
                isStale: wakeLockedCount == 0
            ),
            DashboardHeaderMetric(
                title: "Widgets",
                value: "\(wakeTrustedActionCount)",
                detail: wakeTrustedActionCount == 0 ? "No trusted wake tiles" : "Trusted wake actions",
                systemImage: "checkmark.seal.fill",
                tint: wakeTrustedActionCount == 0 ? AppDesign.Palette.stale : AppDesign.Palette.widget,
                isStale: wakeTrustedActionCount == 0
            )
        ]
    }

    private var commandOverviewValue: String {
        guard model.credential != nil else {
            return "Locked"
        }
        if model.commandShortcuts.isEmpty {
            return "No Tiles"
        }
        return "\(model.commandShortcuts.count)"
    }

    private var commandOverviewSubtitle: String {
        guard model.credential != nil else {
            return "Add bridge first"
        }
        if let reason = commandUnavailableDisplayReason, !model.commandShortcuts.isEmpty {
            return reason
        }
        let tileNoun = model.commandShortcuts.count == 1 ? "command tile" : "command tiles"
        if model.commandShortcuts.isEmpty {
            let trustedNoun = commandTrustedActionCount == 1 ? "trusted command" : "trusted commands"
            return commandTrustedActionCount == 0 ? "No trusted command tiles" : "\(commandTrustedActionCount) \(trustedNoun)"
        }
        let trustedNoun = commandTrustedActionCount == 1 ? "trusted command" : "trusted commands"
        return "\(model.commandShortcuts.count) \(tileNoun) · \(commandTrustedActionCount) \(trustedNoun)"
    }

    private var commandReadyCount: Int {
        guard model.bridgeReachable, model.canRunCommands else {
            return 0
        }
        return model.commandShortcuts.count
    }

    private var commandTrustedActionCount: Int {
        model.widgetActionSelections.filter { $0.kind == .command }.count
    }

    private var commandOverviewTint: Color {
        guard model.credential != nil, !model.commandShortcuts.isEmpty else {
            return AppDesign.Palette.locked
        }
        return model.canRunCommands ? AppDesign.Palette.command : AppDesign.Palette.locked
    }

    private var healthSectionTint: Color {
        if model.credential == nil {
            return AppDesign.Palette.stale
        }
        if model.healthMonitorsErrorMessage != nil || healthDownCount > 0 {
            return AppDesign.Palette.warning
        }
        if !model.bridgeReachable || healthUnknownCount > 0 || model.healthMonitors.isEmpty {
            return AppDesign.Palette.stale
        }
        return AppDesign.Palette.success
    }

    private var healthSectionBadgeKind: AppStatusKind {
        if model.credential == nil || model.healthMonitors.isEmpty || !model.bridgeReachable || healthUnknownCount > 0 {
            return .stale
        }
        if model.healthMonitorsErrorMessage != nil || healthDownCount > 0 {
            return .warning
        }
        return .success
    }

    private var addMonitorDisabledReason: String? {
        if deletingMonitorID != nil {
            return "Finish deleting the current monitor before adding another one."
        }
        return healthMonitorControlsDisplayReason
    }

    private var addDeviceDisabledReason: String? {
        if deletingTargetID != nil {
            return "Finish deleting the current device before adding another one."
        }
        return wolTargetManagementDisplayReason
    }

    private var healthMonitorControlsDisplayReason: String? {
        guard let reason = model.healthMonitorControlsUnavailableReason else {
            return nil
        }
        return trustAwareMessage(reason, lastConfirmedAt: model.healthMonitorsUpdatedAt)
    }

    private var wolControlsDisplayReason: String? {
        guard let reason = model.wolControlsUnavailableReason else {
            return nil
        }
        return trustAwareMessage(reason, lastConfirmedAt: model.wolTargetsUpdatedAt)
    }

    private var wolTargetManagementDisplayReason: String? {
        guard let reason = model.wolTargetManagementUnavailableReason else {
            return nil
        }
        return trustAwareMessage(reason, lastConfirmedAt: model.wolTargetsUpdatedAt)
    }

    private var wakeSectionTint: Color {
        if model.credential == nil {
            return AppDesign.Palette.stale
        }
        if wakeOperationError != nil || model.wolTargetsErrorMessage != nil {
            return AppDesign.Palette.warning
        }
        if !model.bridgeReachable || model.wolTargets.isEmpty || model.wolControlsUnavailableReason != nil {
            return AppDesign.Palette.stale
        }
        return AppDesign.Palette.wake
    }

    private var wakeSectionBadgeKind: AppStatusKind {
        if model.credential == nil || model.wolTargets.isEmpty || !model.bridgeReachable || model.wolControlsUnavailableReason != nil {
            return .stale
        }
        if wakeOperationError != nil || model.wolTargetsErrorMessage != nil {
            return .warning
        }
        return .action
    }

    private var commandSectionTint: Color {
        if model.credential == nil || model.commandUnavailableReason != nil {
            return AppDesign.Palette.stale
        }
        if model.commandStatusText != nil && !model.commandSucceeded {
            return AppDesign.Palette.warning
        }
        if model.commandSucceeded {
            return AppDesign.Palette.success
        }
        return AppDesign.Palette.command
    }

    private var operateSectionTint: Color {
        if overviewActionsKind == .warning {
            return AppDesign.Palette.warning
        }
        if overviewActionsKind == .stale {
            return AppDesign.Palette.stale
        }
        if !model.commandShortcuts.isEmpty {
            return AppDesign.Palette.command
        }
        return AppDesign.Palette.wake
    }

    private var commandSectionBadgeKind: AppStatusKind {
        if model.credential == nil || model.commandShortcuts.isEmpty || model.commandUnavailableReason != nil {
            return .stale
        }
        if model.commandStatusText != nil && !model.commandSucceeded {
            return .warning
        }
        if model.commandSucceeded {
            return .success
        }
        return .action
    }

    private var activitySectionTint: Color {
        if model.activityErrorMessage != nil {
            return AppDesign.Palette.warning
        }
        return AppDesign.Palette.activity
    }

    private var activitySummaryTint: Color {
        if model.activityErrorMessage != nil || activityFailureCount > 0 {
            return AppDesign.Palette.warning
        }
        if model.credential == nil || !model.bridgeReachable || model.auditRecords.isEmpty {
            return AppDesign.Palette.stale
        }
        return AppDesign.Palette.success
    }

    private var activitySummaryKind: AppStatusKind {
        if model.activityErrorMessage != nil || activityFailureCount > 0 {
            return .warning
        }
        if model.credential == nil || !model.bridgeReachable || model.auditRecords.isEmpty {
            return .stale
        }
        return .success
    }

    private func activityTitle(for record: AuditRecord) -> String {
        if let target = record.actionID.stripPrefix("wol:") {
            return "Wake \(target)"
        }
        if record.actionID == "command:run" {
            return "Command"
        }
        return record.actionID
    }

    private func activityStatusKind(_ status: String) -> AppStatusKind {
        AppStatusKind(status: status)
    }

    private var statusSnapshotBadgeTitle: String {
        if model.statusSnapshotsErrorMessage != nil {
            return "Failed"
        }
        if statusSignalCards.isEmpty {
            return "Clear"
        }
        let staleCount = statusSignalCards.filter(\.stale).count
        if staleCount > 0 {
            return staleCount == 1 ? "1 Cached" : "\(staleCount) Cached"
        }
        return statusSignalCards.count == 1 ? "1 Alert" : "\(statusSignalCards.count) Alerts"
    }

    private var statusSnapshotBadgeKind: AppStatusKind {
        if model.statusSnapshotsErrorMessage != nil {
            return .warning
        }
        if statusSignalCards.isEmpty || statusSignalCards.contains(where: \.stale) {
            return .stale
        }
        return .warning
    }

    private var statusSectionTint: Color {
        if model.statusSnapshotsErrorMessage != nil {
            return AppDesign.Palette.warning
        }
        if statusSignalCards.contains(where: \.stale) {
            return AppDesign.Palette.stale
        }
        return statusSignalCards.isEmpty ? AppDesign.Palette.stale : AppDesign.Palette.warning
    }

    private var healthUpCount: Int {
        model.healthMonitors.filter { $0.status == "up" }.count
    }

    private var healthDownCount: Int {
        model.healthMonitors.filter { $0.status == "down" }.count
    }

    private var healthUnknownCount: Int {
        max(0, model.healthMonitors.count - healthUpCount - healthDownCount)
    }

    private func relativeUpdateText(_ date: Date) -> String {
        "updated \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func compactRelativeUpdateText(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static var toolbarPlacement: ToolbarItemPlacement {
        #if canImport(UIKit)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    private func trustAwareMessage(_ message: String, lastConfirmedAt: Date?) -> String {
        guard !model.bridgeReachable, model.bridgeStatusText != "Checking connection" else {
            return message
        }
        let sentence = Self.sentence(message)
        guard let lastConfirmedAt else {
            return "\(sentence) No confirmed cache yet."
        }
        let relative = Self.relativeFormatter.localizedString(for: lastConfirmedAt, relativeTo: Date())
        return "\(sentence) Last confirmed \(relative)."
    }

    private static func sentence(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unavailable."
        }
        return trimmed.hasSuffix(".") ? trimmed : "\(trimmed)."
    }

    private static func badgeCountText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    @MainActor
    private func showFeedback(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        progress: Bool = false,
        autoDismiss: Bool = true
    ) {
        feedbackDismissTask?.cancel()
        let notice = DashboardFeedbackNotice(
            title: title,
            message: message,
            systemImage: systemImage,
            tint: tint,
            progress: progress
        )
        withAnimation(feedbackAnimation(.entering)) {
            feedbackNotice = notice
        }
        guard autoDismiss else {
            feedbackDismissTask = nil
            return
        }
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard feedbackNotice?.id == notice.id else { return }
                withAnimation(feedbackAnimation(.exiting)) {
                    feedbackNotice = nil
                }
            }
        }
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private func feedbackAnimation(_ direction: FeedbackAnimationDirection) -> Animation? {
        guard !reduceMotion else {
            return nil
        }
        switch direction {
        case .entering:
            return AppDesign.Motion.feedbackIn
        case .exiting:
            return AppDesign.Motion.feedbackOut
        }
    }

    @MainActor
    private func resetTransitionFeedback() {
        bridgeTransitionPrimed = false
        monitorTransitionPrimed = false
        lastObservedBridgeID = nil
        lastObservedBridgeReachable = nil
        lastObservedMonitorStatuses = [:]
    }

    @MainActor
    private func handleBridgeStatusTransition() {
        guard let credential = model.credential else {
            resetTransitionFeedback()
            return
        }
        guard model.bridgeStatusText != "Checking connection" else {
            return
        }
        if lastObservedBridgeID != credential.bridgeID {
            lastObservedBridgeID = credential.bridgeID
            lastObservedBridgeReachable = model.bridgeReachable
            bridgeTransitionPrimed = true
            return
        }

        let previousReachable = lastObservedBridgeReachable
        lastObservedBridgeReachable = model.bridgeReachable
        guard bridgeTransitionPrimed, !dashboardRefreshing, previousReachable != model.bridgeReachable else {
            bridgeTransitionPrimed = true
            return
        }

        if model.bridgeReachable {
            AppFeedback.success()
            showFeedback(
                title: "Bridge Online",
                message: "\(credential.bridgeName) is reachable.",
                systemImage: "checkmark.circle.fill",
                tint: AppDesign.Palette.success
            )
        } else {
            AppFeedback.warning()
            showFeedback(
                title: "Bridge Offline",
                message: bridgeOfflineFeedbackMessage(for: credential),
                systemImage: "clock.badge.exclamationmark",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func handleMonitorStatusTransitions(_ monitors: [HealthMonitor]) {
        guard model.credential != nil, model.bridgeReachable, !monitors.isEmpty else {
            return
        }

        let currentStatuses = monitorStatusMap(monitors)
        if dashboardRefreshing {
            lastObservedMonitorStatuses = currentStatuses
            monitorTransitionPrimed = true
            return
        }
        guard monitorTransitionPrimed else {
            lastObservedMonitorStatuses = currentStatuses
            monitorTransitionPrimed = true
            return
        }

        let newlyDown = monitors.filter { monitor in
            normalizedMonitorStatus(monitor.status) == "down" &&
                lastObservedMonitorStatuses[monitor.id].map { $0 != "down" } == true
        }
        let recovered = monitors.filter { monitor in
            normalizedMonitorStatus(monitor.status) == "up" &&
                lastObservedMonitorStatuses[monitor.id] == "down"
        }
        lastObservedMonitorStatuses = currentStatuses

        if !newlyDown.isEmpty {
            AppFeedback.warning()
            showFeedback(
                title: newlyDown.count == 1 ? "Monitor Down" : "\(newlyDown.count) Monitors Down",
                message: monitorFailureMessage(newlyDown),
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        } else if !recovered.isEmpty {
            AppFeedback.success()
            showFeedback(
                title: recovered.count == 1 ? "Monitor Recovered" : "\(recovered.count) Monitors Recovered",
                message: monitorRecoveryMessage(recovered),
                systemImage: "checkmark.circle.fill",
                tint: AppDesign.Palette.success
            )
        }
    }

    @MainActor
    private func handleOpenURL(_ url: URL) async {
        guard url.scheme == "poprocket" else {
            return
        }
        if isPairingURL(url) {
            await model.handle(url)
            return
        }
        guard let destination = DashboardDeepLink(url: url) else {
            return
        }
        AppFeedback.selection()
        selectedTab = destination.tab
        if let actionMode = destination.actionMode {
            selectedActionMode = actionMode
        }
        if destination.tab != .actions {
            focusedField = nil
        }
    }

    private func isPairingURL(_ url: URL) -> Bool {
        url.host == "pair" || url.path == "/pair"
    }

    @MainActor
    private func refreshFromDashboard() async {
        guard !dashboardRefreshing else {
            return
        }
        dashboardRefreshing = true
        defer {
            dashboardRefreshing = false
        }
        AppFeedback.actionStarted()
        let previouslyDownMonitorIDs = Set(downMonitors(in: model.healthMonitors).map(\.id))
        showFeedback(
            title: "Refreshing",
            message: "Checking current state.",
            systemImage: "arrow.clockwise",
            tint: AppDesign.Palette.action,
            progress: true,
            autoDismiss: false
        )
        await model.refreshFromUser()
        if model.errorMessage == nil {
            let downMonitors = downMonitors(in: model.healthMonitors)
            let currentDownMonitorIDs = Set(downMonitors.map(\.id))
            let recoveredCount = previouslyDownMonitorIDs.subtracting(currentDownMonitorIDs).count
            if !downMonitors.isEmpty {
                AppFeedback.warning()
                showFeedback(
                    title: downMonitors.count == 1 ? "Monitor Down" : "\(downMonitors.count) Monitors Down",
                    message: monitorFailureMessage(downMonitors),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: AppDesign.Palette.warning
                )
            } else if recoveredCount > 0 {
                AppFeedback.success()
                showFeedback(
                    title: "Health Recovered",
                    message: recoveredCount == 1 ? "A previously down monitor is healthy again." : "\(recoveredCount) monitors are healthy again.",
                    systemImage: "checkmark.circle.fill",
                    tint: AppDesign.Palette.success
                )
            } else {
                AppFeedback.success()
                showFeedback(
                    title: "Dashboard Updated",
                    message: "\(activeBridgeName) responded.",
                    systemImage: "checkmark.circle.fill",
                    tint: AppDesign.Palette.success
                )
            }
        } else {
            AppFeedback.warning()
            showFeedback(
                title: "Refresh Failed",
                message: model.errorMessage ?? "Could not reach the active bridge.",
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func runCommandFromDashboard() async {
        AppFeedback.actionStarted()
        showFeedback(
            title: "Running Command",
            message: commandRunFeedbackMessage(label: nil),
            systemImage: "terminal.fill",
            tint: AppDesign.Palette.action,
            progress: true,
            autoDismiss: false
        )
        await model.runCommand(commandText)
        if model.commandSucceeded {
            AppFeedback.success()
            showFeedback(
                title: "Command Completed",
                message: commandCompletionFeedbackMessage(label: nil),
                systemImage: "checkmark.circle.fill",
                tint: AppDesign.Palette.success
            )
        } else {
            AppFeedback.failure()
            showFeedback(
                title: "Command Failed",
                message: commandFailureFeedbackMessage(label: nil),
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func runCommandShortcut(_ shortcut: CommandShortcut) async {
        AppFeedback.actionStarted()
        showFeedback(
            title: "Running \(shortcut.name)",
            message: commandRunFeedbackMessage(label: shortcut.name),
            systemImage: "terminal.fill",
            tint: AppDesign.Palette.action,
            progress: true,
            autoDismiss: false
        )
        await model.runCommandShortcut(shortcut)
        if model.commandSucceeded {
            AppFeedback.success()
            showFeedback(
                title: "\(shortcut.name) Completed",
                message: commandCompletionFeedbackMessage(label: shortcut.name),
                systemImage: "checkmark.circle.fill",
                tint: AppDesign.Palette.success
            )
        } else {
            AppFeedback.failure()
            showFeedback(
                title: "\(shortcut.name) Failed",
                message: commandFailureFeedbackMessage(label: shortcut.name),
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func wakeTarget(_ target: WOLTarget) async {
        AppFeedback.actionStarted()
        showFeedback(
            title: "Waking \(target.name)",
            message: "\(activeBridgeName) is sending Wake-on-LAN.",
            systemImage: "power",
            tint: AppDesign.Palette.action,
            progress: true,
            autoDismiss: false
        )
        await model.wake(target)
        if model.wakeStates[target.id]?.succeeded == true {
            AppFeedback.success()
            showFeedback(
                title: "Wake Sent",
                message: model.wakeStates[target.id]?.message?.nilIfBlank ?? "\(target.name) was triggered through \(activeBridgeName).",
                systemImage: "checkmark.circle.fill",
                tint: AppDesign.Palette.success
            )
        } else {
            AppFeedback.failure()
            showFeedback(
                title: "Wake Failed",
                message: model.wakeStates[target.id]?.message?.nilIfBlank ?? "\(activeBridgeName) could not wake \(target.name).",
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func deleteMonitor(_ monitor: HealthMonitor) async {
        AppFeedback.actionStarted()
        deletingMonitorID = monitor.id
        healthOperationMessage = "Deleting \(monitor.name)"
        healthOperationError = nil
        showFeedback(
            title: "Deleting Monitor",
            message: monitor.name,
            systemImage: "trash",
            tint: AppDesign.Palette.destructive,
            progress: true,
            autoDismiss: false
        )
        let deleted = await model.deleteHealthMonitor(monitor)
        deletingMonitorID = nil
        if deleted {
            healthOperationMessage = "Deleted \(monitor.name)"
            AppFeedback.destructive()
            showFeedback(
                title: "Monitor Removed",
                message: "\(monitor.name) removed.",
                systemImage: "trash.circle.fill",
                tint: AppDesign.Palette.destructive
            )
        } else {
            healthOperationMessage = nil
            healthOperationError = model.errorMessage ?? "Could not delete \(monitor.name)."
            model.errorMessage = nil
            AppFeedback.failure()
            showFeedback(
                title: "Delete Failed",
                message: healthOperationError ?? "Could not delete \(monitor.name).",
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    @MainActor
    private func deleteTarget(_ target: WOLTarget) async {
        AppFeedback.actionStarted()
        deletingTargetID = target.id
        wakeOperationMessage = "Deleting \(target.name)"
        wakeOperationError = nil
        showFeedback(
            title: "Deleting Device",
            message: target.name,
            systemImage: "trash",
            tint: AppDesign.Palette.destructive,
            progress: true,
            autoDismiss: false
        )
        let deleted = await model.deleteWOLTarget(target)
        deletingTargetID = nil
        if deleted {
            wakeOperationMessage = "Deleted \(target.name)"
            AppFeedback.destructive()
            showFeedback(
                title: "Device Removed",
                message: "\(target.name) removed.",
                systemImage: "trash.circle.fill",
                tint: AppDesign.Palette.destructive
            )
        } else {
            wakeOperationMessage = nil
            wakeOperationError = model.errorMessage ?? "Could not delete \(target.name)."
            model.errorMessage = nil
            AppFeedback.failure()
            showFeedback(
                title: "Delete Failed",
                message: wakeOperationError ?? "Could not delete \(target.name).",
                systemImage: "exclamationmark.triangle.fill",
                tint: AppDesign.Palette.warning
            )
        }
    }

    private var activeBridgeName: String {
        model.credential?.bridgeName ?? "the active bridge"
    }

    private func commandRunFeedbackMessage(label: String?) -> String {
        if let label = label?.nilIfBlank {
            return "\(label) is running through \(activeBridgeName)."
        }
        return "Command is running through \(activeBridgeName)."
    }

    private func commandCompletionFeedbackMessage(label: String?) -> String {
        let outputHint = model.commandOutputText?.nilIfBlank == nil ? " No output returned." : " Output is shown below."
        if let label = label?.nilIfBlank {
            return "\(label) finished on \(activeBridgeName).\(outputHint)"
        }
        return "Command finished on \(activeBridgeName).\(outputHint)"
    }

    private func commandFailureFeedbackMessage(label: String?) -> String {
        let detailHint: String
        if let output = model.commandOutputText?.nilIfBlank {
            detailHint = " \(Self.compactFeedbackDetail(output))"
        } else {
            detailHint = " No error text returned. Check bridge reachability, then retry."
        }
        if let label = label?.nilIfBlank {
            return "\(label) failed on \(activeBridgeName).\(detailHint)"
        }
        return "Command failed on \(activeBridgeName).\(detailHint)"
    }

    private static func compactFeedbackDetail(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard trimmed.count > 120 else {
            return sentence(trimmed)
        }
        return "\(trimmed.prefix(117))..."
    }

    private func bridgeOfflineFeedbackMessage(for credential: PairingCredential) -> String {
        if let overviewLastConfirmedText {
            return "\(credential.bridgeName) is not responding. Last confirmed \(overviewLastConfirmedText)."
        }
        return "\(credential.bridgeName) is not responding. No confirmed cache yet."
    }

    private func downMonitors(in monitors: [HealthMonitor]) -> [HealthMonitor] {
        monitors.filter { monitor in
            normalizedMonitorStatus(monitor.status) == "down"
        }
    }

    private func monitorStatusMap(_ monitors: [HealthMonitor]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: monitors.map { monitor in
            (monitor.id, normalizedMonitorStatus(monitor.status))
        })
    }

    private func normalizedMonitorStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func monitorFailureMessage(_ monitors: [HealthMonitor]) -> String {
        let names = monitors.prefix(3).map(\.name).joined(separator: ", ")
        let extraCount = monitors.count - min(monitors.count, 3)
        if extraCount > 0 {
            return "\(names), +\(extraCount) more need attention on \(activeBridgeName)."
        }
        return "\(names) need attention on \(activeBridgeName)."
    }

    private func monitorRecoveryMessage(_ monitors: [HealthMonitor]) -> String {
        let names = monitors.prefix(3).map(\.name).joined(separator: ", ")
        let extraCount = monitors.count - min(monitors.count, 3)
        if extraCount > 0 {
            return "\(names), +\(extraCount) more are healthy on \(activeBridgeName)."
        }
        return "\(names) healthy on \(activeBridgeName)."
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

private enum DashboardTab: Hashable {
    case overview
    case health
    case actions
    case activity
    case settings

    var title: String {
        switch self {
        case .overview:
            return "Home"
        case .health:
            return "Monitors"
        case .actions:
            return "Actions"
        case .activity:
            return "Activity"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.33percent"
        case .health:
            return "waveform.path.ecg"
        case .actions:
            return "bolt.circle"
        case .activity:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

private enum DashboardActionMode: Hashable {
    case wake
    case run

    var title: String {
        switch self {
        case .wake:
            return "Wake"
        case .run:
            return "Run"
        }
    }

    var systemImage: String {
        switch self {
        case .wake:
            return "power"
        case .run:
            return "terminal"
        }
    }
}

private struct DashboardDeepLink {
    let tab: DashboardTab
    let actionMode: DashboardActionMode?

    init?(url: URL) {
        let route = Self.route(for: url)
        guard let tab = Self.tab(for: route) else {
            return nil
        }
        self.tab = tab
        self.actionMode = Self.actionMode(for: url, route: route)
    }

    private static func route(for url: URL) -> String {
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if !host.isEmpty {
            return host.lowercased()
        }
        return url.path
            .split(separator: "/")
            .first
            .map { String($0).lowercased() } ?? ""
    }

    private static func tab(for route: String) -> DashboardTab? {
        switch route {
        case "home", "status", "dashboard":
            return .overview
        case "monitors", "monitor", "health":
            return .health
        case "actions", "action", "wake", "run", "commands", "command":
            return .actions
        case "activity", "audit", "history", "log":
            return .activity
        case "settings", "bridges", "bridge", "widgets", "feedback":
            return .settings
        default:
            return nil
        }
    }

    private static func actionMode(for url: URL, route: String) -> DashboardActionMode? {
        let queryMode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "mode" || $0.name == "action" }?
            .value?
            .lowercased()
        let pathComponents = url.path.split(separator: "/")
        let pathMode = (url.host?.isEmpty == false ? pathComponents.first : pathComponents.dropFirst().first)
            .map { String($0).lowercased() }
        switch queryMode ?? pathMode ?? route {
        case "wake", "wol", "device", "devices":
            return .wake
        case "run", "command", "commands", "tile", "tiles":
            return .run
        default:
            return nil
        }
    }
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

private enum WOLInputFormatter {
    static func normalizedMACAddress(_ value: String) -> String? {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard compact.count == 12,
              compact.unicodeScalars.allSatisfy({ hex.contains($0) })
        else {
            return nil
        }
        let characters = Array(compact)
        let bytes = stride(from: 0, to: characters.count, by: 2).map { index in
            String(characters[index..<(index + 2)])
        }
        return bytes.joined(separator: ":")
    }

    static func isValidIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(part) == String(number)
        }
    }

    static func suggestedBroadcastIP(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIPv4Address(trimmed) else {
            return nil
        }
        var parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return nil
        }
        parts[3] = "255"
        return parts.joined(separator: ".")
    }
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

private struct DashboardFeedbackNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let progress: Bool
}

private enum FeedbackAnimationDirection {
    case entering
    case exiting
}

private enum DashboardDesign {
    static let pagePadding = AppDesign.Spacing.page
    static let sectionSpacing = AppDesign.Spacing.section
    static let sectionCornerRadius = AppDesign.Radius.section
    static let controlSpacing = AppDesign.Spacing.control
    static let tileMinimumHeight = AppDesign.Size.actionTileMinimumHeight
    static let background = AppDesign.background
    static let sectionFill = AppDesign.sectionFill
    static let sectionStroke = AppDesign.sectionStroke
    static let disabledOpacity = AppDesign.disabledOpacity
}

private struct DashboardHeaderMetric: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    var isStale: Bool
}

private struct DashboardActionModeItem: Identifiable {
    var id: DashboardActionMode { mode }
    let mode: DashboardActionMode
    let value: String
    let detail: String
    let tint: Color
    let kind: AppStatusKind
}

private struct DashboardActionModeSelector: View {
    let items: [DashboardActionModeItem]
    let selectedMode: DashboardActionMode
    let select: (DashboardActionMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    select(item.mode)
                } label: {
                    DashboardActionModeTile(
                        item: item,
                        selected: item.mode == selectedMode
                    )
                }
                .buttonStyle(AppPressButtonStyle(tint: item.tint, isEnabled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(item.mode.title), \(item.value), \(item.detail)")
                .accessibilityAddTraits(item.mode == selectedMode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppDesign.panelFill, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(AppDesign.panelStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action mode")
    }
}

private struct DashboardActionModeTile: View {
    let item: DashboardActionModeItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.mode.systemImage)
                .font(.caption.weight(.bold))
            Text(item.mode.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? item.tint : AppDesign.Palette.stale)
        .background(selected ? item.tint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(selected ? item.tint.opacity(0.22) : Color.clear, lineWidth: 1)
        }
    }
}

private struct DashboardOperationsHeader: View {
    let credential: PairingCredential?
    let bridgeHealthy: Bool
    let bridgeReachable: Bool
    let statusText: String
    let bridgeHealth: BridgeHealth?
    let metrics: [DashboardHeaderMetric]
    let lastConfirmedText: String?
    let showsFocusRow: Bool
    let focusTitle: String
    let focusDetail: String
    let focusSystemImage: String
    let focusKind: AppStatusKind
    let primaryTitle: String
    let primarySystemImage: String
    let primaryKind: AppStatusKind
    let primaryAction: () -> Void
    let isRefreshing: Bool
    let refresh: () -> Void
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: bridgeIconName, tint: statusTint, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(contextLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .lineLimit(1)
                        if credential != nil {
                            AppStateLine(
                                title: statusPillText,
                                detail: bridgeHealth.map { "up \(Self.shortDuration(seconds: $0.uptimeSeconds))" },
                                kind: statusKind
                            )
                        }
                    }
                    Text(bridgeTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if let trustLine {
                        Text(trustLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if credential != nil {
                    AppIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Refresh Dashboard",
                        tint: AppDesign.Palette.action,
                        isRunning: isRefreshing,
                        runningReason: "Refreshing bridge status, health checks, actions, and activity.",
                        action: refresh
                    )
                }
            }

            if credential != nil, !metrics.isEmpty {
                CompactMetricPillRow(metrics: metrics)
            }

            if credential == nil {
                SetupBridgePrompt(pairBridge: pairBridge)
            } else if showsFocusRow {
                DashboardHeaderFocusRow(
                    title: focusTitle,
                    detail: focusDetail,
                    systemImage: focusSystemImage,
                    kind: focusKind,
                    showsPrimaryAction: focusKind != .success,
                    primaryTitle: primaryTitle,
                    primarySystemImage: primarySystemImage,
                    primaryKind: primaryKind,
                    primaryAction: primaryAction
                )
            }
        }
        .padding(12)
        .background(DashboardDesign.sectionFill)
        .overlay(
            RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous)
                .stroke(DashboardDesign.sectionStroke, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(statusTint)
                .frame(width: 4)
                .opacity(credential == nil ? 0.45 : 0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous))
    }

    private var bridgeTitle: String {
        credential?.bridgeName ?? "Add a Bridge"
    }

    private var contextLabel: String {
        guard credential != nil else {
            return "Bridge"
        }
        return bridgeReachable ? "Live Bridge" : "Cached Bridge"
    }

    private var trustLine: String? {
        guard let credential else {
            return "Connect one trusted LAN bridge to monitor health, run actions, and wake devices."
        }
        if bridgeReachable {
            return nil
        }
        if let lastConfirmedText {
            return "Cached from \(credential.bridgeName). Last confirmed \(lastConfirmedText). Actions paused."
        }
        return "Cached from \(credential.bridgeName). No confirmed cache yet. Actions paused."
    }

    private var statusPillText: String {
        guard credential != nil else {
            return "Not Added"
        }
        return statusText
    }

    private var statusKind: AppStatusKind {
        guard credential != nil else {
            return .stale
        }
        if bridgeHealthy {
            return .success
        }
        return bridgeReachable ? .warning : .stale
    }

    private var bridgeIconName: String {
        if bridgeHealthy {
            return "checkmark.circle.fill"
        }
        if bridgeReachable {
            return "exclamationmark.triangle.fill"
        }
        return credential == nil ? "link.badge.plus" : "clock.badge.exclamationmark"
    }

    private var statusTint: Color {
        guard credential != nil else {
            return AppDesign.Palette.locked
        }
        if bridgeHealthy {
            return AppDesign.Palette.success
        }
        return bridgeReachable ? AppDesign.Palette.warning : AppDesign.Palette.cached
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
        return "\(days)d"
    }
}

private struct DashboardHeaderFocusRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let kind: AppStatusKind
    let showsPrimaryAction: Bool
    let primaryTitle: String
    let primarySystemImage: String
    let primaryKind: AppStatusKind
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.color)
                    .frame(width: 30, height: 30)
                    .background(kind.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if showsPrimaryAction {
                AppActionButton(
                    title: primaryTitle,
                    systemImage: primarySystemImage,
                    kind: primaryKind,
                    action: primaryAction
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        switch kind {
        case .success:
            return "CONFIRMED"
        case .warning:
            return "CHECK"
        case .stale:
            return "VERIFY"
        case .action:
            return "OPEN"
        case .destructive:
            return "SECURITY"
        }
    }
}

private struct CompactMetricPillRow: View {
    let metrics: [DashboardHeaderMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric, compact: true)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 112), spacing: 7),
            GridItem(.flexible(minimum: 112), spacing: 7)
        ]
    }
}

private struct DashboardMetricTile: View {
    let metric: DashboardHeaderMetric
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(resolvedColor)
                    .frame(width: 18, height: 18)
                    .background(resolvedColor.opacity(0.15), in: Circle())
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Spacer(minLength: 0)
                Circle()
                    .fill(resolvedColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Text(metric.value)
                .font(AppDesign.Typography.dashboardMetricValue)
                .foregroundStyle(resolvedColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if !compact {
                Text(metric.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: compact ? 58 : 78, alignment: .topLeading)
        .background(resolvedColor.opacity(metric.isStale ? 0.060 : 0.095), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(resolvedColor.opacity(metric.isStale ? 0.16 : 0.26), lineWidth: 1)
        }
        .accessibilityLabel("\(metric.title), \(metric.value), \(metric.detail)")
    }

    private var resolvedColor: Color {
        metric.isStale ? AppDesign.Palette.stale : metric.tint
    }
}

private struct SetupBridgePrompt: View {
    let pairBridge: () -> Void

    var body: some View {
        AppActionButton(
            title: "Add Bridge",
            systemImage: "link.badge.plus",
            kind: .action,
            action: pairBridge
        )
        .accessibilityLabel("Add a trusted local bridge.")
    }
}

private struct BridgeRequiredPanel: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconBubble(systemImage: systemImage, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            AppActionButton(
                title: "Add Bridge",
                systemImage: "link.badge.plus",
                kind: .action,
                action: pairBridge
            )
            .accessibilityLabel("Add a trusted local bridge.")
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: .quiet)
    }
}

private struct ActionAuthorityStrip: View {
    let mode: DashboardActionMode
    let bridgeName: String
    let bridgeReachable: Bool
    let bridgeHealthy: Bool
    let lastConfirmedText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIconBubble(systemImage: mode.systemImage, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                }
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .appSemanticPanel(
            tint: tint,
            isActive: bridgeReachable,
            prominence: .quiet,
            showsRail: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        switch mode {
        case .wake:
            return "Wake Through \(bridgeName)"
        case .run:
            return "Run Through \(bridgeName)"
        }
    }

    private var detail: String? {
        if bridgeHealthy {
            return nil
        }
        if bridgeReachable {
            switch mode {
            case .wake:
                return "Wake-on-LAN requests use this bridge."
            case .run:
                return "Command tiles and one-off commands execute on this bridge."
            }
        }
        if let lastConfirmedText {
            return "Cached from \(bridgeName). Last confirmed \(lastConfirmedText). Reconnect before running actions."
        }
        return "Cached from \(bridgeName). No confirmed cache yet. Reconnect before running actions."
    }

    private var accessibilityLabel: String {
        if let detail {
            return "\(title), \(badgeTitle), \(detail)"
        }
        return "\(title), \(badgeTitle)"
    }

    private var badgeTitle: String {
        if bridgeHealthy {
            return "Live"
        }
        if bridgeReachable {
            return "Check"
        }
        return "Cached"
    }

    private var kind: AppStatusKind {
        if bridgeHealthy {
            return .success
        }
        if bridgeReachable {
            return .warning
        }
        return .stale
    }

    private var tint: Color {
        if !bridgeReachable {
            return AppDesign.Palette.stale
        }
        switch mode {
        case .wake:
            return AppDesign.Palette.wake
        case .run:
            return AppDesign.Palette.command
        }
    }
}

private struct DashboardTabHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let hasBridge: Bool
    let bridgeTitle: String
    let bridgeStatusTitle: String
    let bridgeStatusDetail: String?
    let bridgeStatusKind: AppStatusKind
    let isRefreshing: Bool
    let refresh: () -> Void
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                if hasBridge {
                    AppIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Refresh",
                        tint: AppDesign.Palette.action,
                        isRunning: isRefreshing,
                        runningReason: "Refreshing this screen from the active bridge.",
                        action: refresh
                    )
                }
            }

            if hasBridge, let contextLine {
                HStack(alignment: .center, spacing: 8) {
                    AppStatusBadge(
                        title: badgeTitle,
                        kind: bridgeStatusKind,
                        systemImage: bridgeStatusKind.symbolName
                    )
                    Text(contextLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        guard hasBridge else {
            return "LOCKED"
        }
        switch bridgeStatusKind {
        case .success:
            return "LIVE"
        case .warning:
            return "CHECK"
        case .stale:
            return "CACHED"
        case .action:
            return "OPEN"
        case .destructive:
            return "SECURITY"
        }
    }

    private var contextLine: String? {
        guard hasBridge else {
            return nil
        }
        guard bridgeStatusKind != .success else {
            return nil
        }
        if let bridgeStatusDetail, !bridgeStatusDetail.isEmpty {
            return "\(bridgeTitle) · \(bridgeStatusDetail)"
        }
        return "\(bridgeTitle) · \(bridgeStatusTitle)"
    }
}

private struct DashboardNavigationButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }
            .padding(12)
            .appSemanticPanel(tint: tint, prominence: .quiet, showsRail: false)
        }
        .buttonStyle(AppPressButtonStyle(tint: tint))
        .accessibilityLabel("\(title), \(detail)")
    }
}

private struct OverviewWakeActionTile: View {
    let target: WOLTarget
    let state: WOLActionState?
    let isEnabled: Bool
    let disabledReason: String?
    let bridgeName: String
    let bridgeReachable: Bool
    let lastUpdatedAt: Date?
    let widgetPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppIconBubble(systemImage: iconName, tint: statusKind.color, size: 28)
                    Spacer(minLength: 0)
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                    Text("Wake")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ActionContextChipRow(
                        bridgeName: bridgeName,
                        bridgeReachable: bridgeReachable,
                        widgetPinned: widgetPinned,
                        configManaged: target.source == "config",
                        showBridgeChip: !bridgeReachable
                    )
                }

                Spacer(minLength: 0)

                AppStateLine(
                    title: statusTitle,
                    detail: statusDetail,
                    kind: statusKind
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        }
        .buttonStyle(AppPressButtonStyle(tint: statusKind.color, isEnabled: isEnabled && !isRunning))
        .disabled(!isEnabled || isRunning)
        .appActionSurface(tint: statusKind.color, isEnabled: isEnabled || state != nil)
        .opacity(isEnabled || state != nil ? 1 : DashboardDesign.disabledOpacity)
        .animation(AppDesign.Motion.stateChange, value: statusTitle)
        .animation(AppDesign.Motion.stateChange, value: isRunning)
        .accessibilityLabel("Wake \(target.name)")
        .accessibilityValue(accessibilityState)
        .accessibilityHint(accessibilityHint)
    }

    private var isRunning: Bool {
        state?.running == true
    }

    private var statusTitle: String {
        if isRunning {
            return "Waking"
        }
        if state?.succeeded == true {
            return "Sent"
        }
        if state != nil {
            return "Failed"
        }
        if isEnabled && bridgeReachable {
            return "Can Wake"
        }
        return "Cached"
    }

    private var statusDetail: String? {
        if let state {
            var parts: [String] = []
            if let updatedAt = state.updatedAt {
                parts.append(Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date()))
            }
            parts.append(state.bridgeName?.nilIfBlank ?? bridgeName)
            return parts.joined(separator: " · ")
        }
        if !isEnabled {
            return disabledReason
        }
        if !bridgeReachable, let lastUpdatedAt {
            return "last confirmed \(Self.relativeFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date()))"
        }
        return "Tap to wake"
    }

    private var statusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if state?.succeeded == true {
            return .success
        }
        if state != nil {
            return .warning
        }
        if isEnabled && bridgeReachable {
            return .action
        }
        return .stale
    }

    private var iconName: String {
        if isRunning {
            return "hourglass"
        }
        if state?.succeeded == true {
            return "checkmark.circle.fill"
        }
        if state != nil {
            return "exclamationmark.triangle.fill"
        }
        return "power"
    }

    private var accessibilityState: String {
        [statusTitle, statusDetail].compactMap(\.self).joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isRunning {
            return "Wake request is running through \(bridgeName)."
        }
        if !isEnabled {
            return disabledReason ?? "Wake is unavailable."
        }
        if bridgeReachable {
            return "Sends Wake-on-LAN through \(bridgeName)."
        }
        return "Cached from \(bridgeName). Reconnect the bridge before waking this device."
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct OverviewCommandActionTile: View {
    let shortcut: CommandShortcut
    let isRunning: Bool
    let commandRunning: Bool
    let bridgeName: String
    let bridgeReachable: Bool
    let commandEnabled: Bool
    let disabledReason: String?
    let widgetPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppIconBubble(systemImage: iconName, tint: statusKind.color, size: 28)
                    Spacer(minLength: 0)
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(shortcut.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                    Text("Command")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ActionContextChipRow(
                        bridgeName: bridgeName,
                        bridgeReachable: bridgeReachable,
                        widgetPinned: widgetPinned,
                        configManaged: false,
                        showBridgeChip: !bridgeReachable
                    )
                }

                Spacer(minLength: 0)

                AppStateLine(
                    title: statusTitle,
                    detail: statusDetail,
                    kind: statusKind
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        }
        .buttonStyle(AppPressButtonStyle(tint: statusKind.color, isEnabled: commandEnabled && !commandRunning))
        .disabled(commandRunning || !commandEnabled)
        .appActionSurface(tint: statusKind.color, isEnabled: commandEnabled || isRunning)
        .opacity((commandRunning && !isRunning) || !commandEnabled ? DashboardDesign.disabledOpacity : 1)
        .animation(AppDesign.Motion.stateChange, value: statusTitle)
        .animation(AppDesign.Motion.stateChange, value: isRunning)
        .accessibilityLabel("Run \(shortcut.name)")
        .accessibilityValue(accessibilityState)
        .accessibilityHint(accessibilityHint)
    }

    private var statusTitle: String {
        if isRunning {
            return "Running"
        }
        if !commandEnabled {
            return "Unavailable"
        }
        if commandRunning {
            return "Busy"
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return Self.displayStatus(status)
        }
        return "Can Run"
    }

    private var statusDetail: String? {
        if isRunning {
            return nil
        }
        if !commandEnabled {
            return disabledReason
        }
        if commandRunning {
            return "Another command is running"
        }
        if let lastRunAt = shortcut.lastRunAt {
            let relativeRun = Self.relativeFormatter.localizedString(for: lastRunAt, relativeTo: Date())
            return bridgeReachable ? relativeRun : "\(relativeRun) · \(bridgeName)"
        }
        return "Tap to run"
    }

    private var statusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if !commandEnabled || commandRunning {
            return .stale
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status)
        }
        return .action
    }

    private var iconName: String {
        if isRunning {
            return "hourglass"
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status).symbolName
        }
        return "terminal"
    }

    private var accessibilityState: String {
        [statusTitle, statusDetail].compactMap(\.self).joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isRunning {
            return "Command is running through \(bridgeName)."
        }
        if !commandEnabled {
            return disabledReason ?? "Command runner is unavailable."
        }
        if commandRunning {
            return "Another command is already running."
        }
        if bridgeReachable {
            return "Runs this saved command through \(bridgeName)."
        }
        return "Cached from \(bridgeName). Reconnect the bridge before running this command."
    }

    private static func displayStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":
            return "Ran"
        case "failed", "request failed":
            return "Failed"
        case "accepted":
            return "Accepted"
        default:
            return AppDesign.statusLabel(status)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct OverviewSetupActionTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let kind: AppStatusKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppIconBubble(systemImage: systemImage, tint: tint, size: 28)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .opacity(0.76)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                AppStateLine(title: "Configure", detail: nil, kind: kind)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        }
        .buttonStyle(AppPressButtonStyle(tint: tint, isEnabled: true))
        .appActionSurface(tint: tint, isEnabled: true)
        .accessibilityLabel(title)
    }
}

private struct DashboardSubsectionHeader: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardSectionBand<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeTitle: String? = nil
    var badgeKind: AppStatusKind? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resolvedTint)
                    .frame(width: 30, height: 30)
                    .background(resolvedTint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppDesign.Typography.dashboardSectionTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let badgeTitle {
                    AppStatusBadge(
                        title: badgeTitle,
                        kind: badgeKind ?? .stale,
                        systemImage: badgeKind?.symbolName
                    )
                }
            }
            .accessibilityElement(children: .combine)

            content
        }
        .padding(.horizontal, DashboardDesign.pagePadding)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(DashboardDesign.sectionFill)
            Rectangle()
                .fill(resolvedTint.opacity(0.030))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(resolvedTint)
                .frame(width: 3)
                .opacity(0.62)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DashboardDesign.sectionStroke)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardDesign.sectionStroke)
                .frame(height: 1)
        }
        .padding(.horizontal, -DashboardDesign.pagePadding)
        .accessibilityElement(children: .contain)
    }

    private var resolvedTint: Color {
        badgeKind?.color ?? tint
    }
}

private struct CardRow: View {
    let card: CardSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.stale ? AppStatusKind.stale.symbolName : "rectangle.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cardStatusKind.color)
                .frame(width: 30, height: 30)
                .background(cardStatusKind.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    AppStatusBadge(status: card.stale ? "stale" : card.status)
                }
                Text(card.error?.nilIfBlank ?? card.value?.displayText ?? card.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(card.stale ? "Last confirmed" : "Updated") \(card.updatedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .appSemanticPanel(tint: cardStatusKind.color, prominence: .quiet)
    }

    private var cardStatusKind: AppStatusKind {
        card.stale ? .stale : AppStatusKind(status: card.status)
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
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: .quiet)
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
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: progress ? .standard : .quiet)
    }
}

private struct ActionMetaChip: View {
    let title: String
    let systemImage: String
    var kind: AppStatusKind = .stale
    var maxWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
            .font(AppDesign.Typography.metadata)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(kind.color.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct ActionMetaIconChip: View {
    let title: String
    let systemImage: String
    var kind: AppStatusKind

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.color)
            .frame(width: 24, height: 22)
            .background(kind.color.opacity(0.10), in: Capsule())
            .accessibilityLabel(title)
    }
}

private struct ActionContextChipRow: View {
    let bridgeName: String
    let bridgeReachable: Bool
    let widgetPinned: Bool
    let configManaged: Bool
    var showBridgeChip = false

    var body: some View {
        if showsAnyChip {
            ViewThatFits(in: .horizontal) {
                fullChipRow
                compactChipRow
                compactFallbackChipRow
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        }
    }

    private var fullChipRow: some View {
        HStack(spacing: 6) {
            if showBridgeChip {
                bridgeChip(maxWidth: 118)
            }
            if widgetPinned {
                ActionMetaChip(
                    title: "Trusted",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            }
            if configManaged {
                ActionMetaChip(
                    title: "Config",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private var compactChipRow: some View {
        HStack(spacing: 5) {
            if showBridgeChip {
                bridgeChip(maxWidth: 112)
            }
            if widgetPinned {
                ActionMetaIconChip(
                    title: "Trusted for widgets",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            }
            if configManaged {
                ActionMetaIconChip(
                    title: "Config managed",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private var compactFallbackChipRow: some View {
        HStack(spacing: 5) {
            if showBridgeChip {
                bridgeChip(maxWidth: 132)
            }
            if widgetPinned {
                ActionMetaIconChip(
                    title: "Trusted for widgets",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            } else if configManaged {
                ActionMetaIconChip(
                    title: "Config managed",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private func bridgeChip(maxWidth: CGFloat) -> some View {
        ActionMetaChip(
            title: bridgeName.nilIfBlank ?? "Bridge",
            systemImage: "antenna.radiowaves.left.and.right",
            kind: bridgeReachable ? .action : .stale,
            maxWidth: maxWidth
        )
    }

    private var showsAnyChip: Bool {
        showBridgeChip || widgetPinned || configManaged
    }
}

private struct ActionTileFooter: View {
    let title: String
    let systemImage: String
    let kind: AppStatusKind
    var isRunning = false
    var isEnabled = true

    var body: some View {
        HStack(spacing: 7) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isEnabled ? systemImage : "lock.fill")
                    .font(.caption.weight(.bold))
            }
            Text(title)
                .font(AppDesign.Typography.controlLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
            if isEnabled && !isRunning {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .opacity(0.72)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 10)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var foregroundColor: Color {
        isEnabled || isRunning ? kind.color : AppDesign.Palette.stale
    }

    private var backgroundColor: Color {
        (isEnabled || isRunning ? kind.color : AppDesign.Palette.stale).opacity(0.12)
    }

    private var borderColor: Color {
        (isEnabled || isRunning ? kind.color : AppDesign.Palette.stale).opacity(0.20)
    }
}

private struct WidgetTrustButtonLabel: View {
    let isTrusted: Bool

    var body: some View {
        Label(labelTitle, systemImage: isTrusted ? "checkmark.seal.fill" : "checkmark.seal")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 68, height: AppDesign.Size.iconButton)
            .foregroundStyle(tint)
            .background(tint.opacity(isTrusted ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(tint.opacity(isTrusted ? 0.24 : 0.16), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var labelTitle: String {
        isTrusted ? "Trusted" : "Trust"
    }

    private var tint: Color {
        isTrusted ? AppDesign.Palette.success : AppDesign.Palette.stale
    }
}

private struct FormValidationRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(AppDesign.Palette.warning)
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
                .foregroundStyle(AppDesign.Palette.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct ActivityTimelineRow: View {
    let record: AuditRecord
    let bridgeName: String
    let isLive: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            timelineRail
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    AppStatusBadge(title: AppDesign.statusLabel(record.status).uppercased(), kind: statusKind, systemImage: iconName)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Label(actionKind, systemImage: actionIconName)
                        Text("·")
                        Text(record.createdAt, style: .relative)
                        Text("·")
                        Text(bridgeContext)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Label(actionKind, systemImage: actionIconName)
                            Text("·")
                            Text(record.createdAt, style: .relative)
                        }
                        Text(bridgeContext)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let durationText {
                    AppStateLine(
                        title: "Duration",
                        detail: durationText,
                        kind: statusKind == .warning ? .warning : .stale
                    )
                }

                if let message = record.resultMessage, !message.isEmpty {
                    resultBlock(message)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
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

    private var actionKind: String {
        if record.actionID.hasPrefix("wol:") {
            return "Wake"
        }
        if record.actionID.hasPrefix("command:") {
            return "Command"
        }
        return "Action"
    }

    private var actionIconName: String {
        if record.actionID.hasPrefix("wol:") {
            return "power"
        }
        if record.actionID.hasPrefix("command:") {
            return "terminal"
        }
        return "bolt"
    }

    private var bridgeContext: String {
        isLive ? "\(bridgeName) confirmed" : "cached from \(bridgeName)"
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

    private var statusKind: AppStatusKind {
        AppStatusKind(status: record.status)
    }

    private var durationText: String? {
        guard let completedAt = record.completedAt else {
            return nil
        }
        let seconds = completedAt.timeIntervalSince(record.createdAt)
        guard seconds >= 0 else {
            return nil
        }
        if seconds < 1 {
            return "<1s"
        }
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60).rounded())
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private var accessibilitySummary: String {
        var parts = [
            title,
            AppDesign.statusLabel(record.status),
            actionKind,
            isLive ? "\(bridgeName) confirmed" : "cached from \(bridgeName)"
        ]
        if let durationText {
            parts.append("Duration \(durationText)")
        }
        if let message = record.resultMessage?.nilIfBlank {
            parts.append(message)
        }
        return parts.joined(separator: ", ")
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : statusKind.color.opacity(0.24))
                .frame(width: 2, height: 8)
            ZStack {
                Circle()
                    .fill(statusKind.color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusKind.color)
            }
            Rectangle()
                .fill(isLast ? Color.clear : statusKind.color.opacity(0.24))
                .frame(width: 2)
                .frame(minHeight: 34, maxHeight: .infinity)
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }

    private func resultBlock(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(statusKind == .warning ? AppDesign.Palette.warning : AppDesign.Palette.stale)
            .lineLimit(4)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusKind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(
                            title: isLive ? "LIVE" : "CACHED",
                            kind: isLive ? statusKind : .stale,
                            systemImage: isLive ? "dot.radiowaves.left.and.right" : "clock.badge.exclamationmark"
                        )
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isLive, let lastUpdatedAt {
                        Text("Last confirmed \(lastUpdatedAt, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HealthSummaryDistributionBar(
                upCount: upCount,
                downCount: downCount,
                unknownCount: unknownCount
            )

            HealthSummaryCountRow(
                upCount: upCount,
                downCount: downCount,
                unknownCount: unknownCount
            )
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusColor,
            isActive: isLive,
            prominence: downCount > 0 ? .standard : .quiet
        )
    }

    private var title: String {
        if !isLive {
            return "Last Confirmed Health"
        }
        if downCount > 0 {
            return "\(downCount) Down"
        }
        if unknownCount > 0 {
            return "\(unknownCount) Unknown"
        }
        return "All Checks Confirmed"
    }

    private var subtitle: String {
        let counts = "\(upCount) up / \(downCount) down / \(monitors.count) monitored"
        if !isLive {
            return "Bridge offline; showing last confirmed \(counts.lowercased())"
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
            return AppDesign.Palette.stale
        }
        return downCount > 0 ? AppDesign.Palette.warning : AppDesign.Palette.success
    }

    private var statusKind: AppStatusKind {
        if !isLive || unknownCount > 0 {
            return .stale
        }
        return downCount > 0 ? .warning : .success
    }
}

private struct HealthSummaryDistributionBar: View {
    let upCount: Int
    let downCount: Int
    let unknownCount: Int

    private var total: Int {
        max(upCount + downCount + unknownCount, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)
            let upWidth = segmentWidth(upCount, totalWidth: width)
            let downWidth = segmentWidth(downCount, totalWidth: width)
            let unknownWidth = segmentWidth(unknownCount, totalWidth: width)

            HStack(spacing: 0) {
                if upCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.success)
                        .frame(width: upWidth)
                }
                if downCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.warning)
                        .frame(width: downWidth)
                }
                if unknownCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.stale)
                        .frame(width: unknownWidth)
                }
                if upCount + downCount + unknownCount == 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.stale.opacity(0.45))
                }
            }
            .frame(width: width, height: 8, alignment: .leading)
            .background(AppDesign.Palette.stale.opacity(0.14))
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func segmentWidth(_ count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else {
            return 0
        }
        return totalWidth * CGFloat(count) / CGFloat(total)
    }
}

private struct HealthSummaryCountRow: View {
    let upCount: Int
    let downCount: Int
    let unknownCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                HealthSummaryCountPill(title: "Up", value: upCount, kind: upCount > 0 ? .success : .stale, systemImage: "checkmark.circle.fill")
                HealthSummaryCountPill(title: "Down", value: downCount, kind: downCount > 0 ? .warning : .stale, systemImage: "exclamationmark.triangle.fill")
                HealthSummaryCountPill(title: "Unknown", value: unknownCount, kind: .stale, systemImage: "questionmark.circle.fill")
            }
            VStack(alignment: .leading, spacing: 7) {
                HealthSummaryCountPill(title: "Up", value: upCount, kind: upCount > 0 ? .success : .stale, systemImage: "checkmark.circle.fill")
                HealthSummaryCountPill(title: "Down", value: downCount, kind: downCount > 0 ? .warning : .stale, systemImage: "exclamationmark.triangle.fill")
                HealthSummaryCountPill(title: "Unknown", value: unknownCount, kind: .stale, systemImage: "questionmark.circle.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(upCount) up, \(downCount) down, \(unknownCount) unknown")
    }
}

private struct HealthSummaryCountPill: View {
    let title: String
    let value: Int
    let kind: AppStatusKind
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text("\(value) \(title)")
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(kind.color.opacity(value > 0 ? 0.12 : 0.07), in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct HealthMonitorRow: View {
    let monitor: HealthMonitor
    let isLive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(monitor.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sourceLabel {
                        ActionMetaChip(title: sourceLabel, systemImage: sourceIconName)
                    }
                }
                Text(endpointText)
                    .font(AppDesign.Typography.monoMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(stateDurationText)
                    if let responseTime = monitor.responseTimeMS, monitor.status == "up" {
                        Text("\(responseTime) ms")
                    }
                    if let checkedAt = monitor.checkedAt {
                        Text(isLive ? "Checked \(checkedAt, style: .relative)" : "Cached · checked \(checkedAt, style: .relative)")
                    } else if !isLive {
                        Text("No confirmed check")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if monitor.status == "down", let message = monitor.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(AppDesign.Palette.warning)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            AppStatusBadge(status: isLive ? monitor.status : "stale")
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusColor,
            isActive: isLive,
            prominence: monitor.status == "down" ? .standard : .quiet
        )
    }

    private var statusColor: Color {
        guard isLive else {
            return AppDesign.Palette.stale
        }
        switch monitor.status {
        case "up":
            return AppDesign.Palette.success
        case "down":
            return AppDesign.Palette.warning
        default:
            return AppDesign.Palette.stale
        }
    }

    private var statusIconName: String {
        guard isLive else {
            return "clock.badge.exclamationmark"
        }
        switch monitor.status {
        case "up":
            return "checkmark.circle.fill"
        case "down":
            return "exclamationmark.triangle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private var sourceLabel: String? {
        switch monitor.source {
        case "config":
            return "Config"
        case "wol":
            return "Device"
        default:
            return nil
        }
    }

    private var sourceIconName: String {
        switch monitor.source {
        case "config":
            return "lock.fill"
        case "wol":
            return "power"
        default:
            return "tag"
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

private struct WOLReadinessPanel: View {
    let title: String
    let detail: String
    let bridgeName: String
    let kind: AppStatusKind
    let metrics: [DashboardHeaderMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconBubble(systemImage: "power.circle.fill", tint: kind.color, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer(minLength: 0)
                        AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CompactMetricPillRow(metrics: metrics)

            AppStateLine(
                title: "Bridge",
                detail: bridgeName,
                kind: kind == .warning ? .warning : .stale
            )
        }
        .padding(14)
        .appSemanticPanel(
            tint: kind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: kind == .action ? .standard : .quiet
        )
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        switch kind {
        case .success:
            return "CAN WAKE"
        case .warning:
            return "CHECK"
        case .stale:
            return "CACHED"
        case .action:
            return "CAN WAKE"
        case .destructive:
            return "SECURITY"
        }
    }
}

private struct WOLTargetGrid: View {
    let targets: [WOLTarget]
    let wakeStates: [String: WOLActionState]
    let deletingTargetID: String?
    let bridgeName: String
    let bridgeReachable: Bool
    let lastUpdatedAt: Date?
    let widgetPinned: (WOLTarget) -> Bool
    let wakeUnavailableReason: (WOLTarget) -> String?
    let canManage: (WOLTarget) -> Bool
    let toggleWidgetPin: (WOLTarget) -> Void
    let edit: (WOLTarget) -> Void
    let delete: (WOLTarget) -> Void
    let wake: (WOLTarget) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(targets) { target in
                let reason = deletingTargetID == target.id ? "Deleting device." : wakeUnavailableReason(target)
                WOLTargetTile(
                    target: target,
                    state: wakeStates[target.id],
                    wakeEnabled: reason == nil,
                    disabledReason: reason,
                    bridgeName: bridgeName,
                    bridgeReachable: bridgeReachable,
                    lastUpdatedAt: lastUpdatedAt ?? target.updatedAt,
                    widgetPinned: widgetPinned(target),
                    canManage: canManage(target),
                    toggleWidgetPin: { toggleWidgetPin(target) },
                    edit: { edit(target) },
                    delete: { delete(target) },
                    wake: { wake(target) }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WOLTargetTile: View {
    let target: WOLTarget
    let state: WOLActionState?
    let wakeEnabled: Bool
    let disabledReason: String?
    let bridgeName: String
    let bridgeReachable: Bool
    let lastUpdatedAt: Date?
    let widgetPinned: Bool
    let canManage: Bool
    let toggleWidgetPin: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let wake: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                AppIconBubble(systemImage: statusIconName, tint: statusColor, size: 32)
                AppStatusBadge(title: tileStatusTitle, kind: tileStatusKind, systemImage: tileStatusKind.symbolName)
                Spacer(minLength: 0)
                Button(action: toggleWidgetPin) {
                    WidgetTrustButtonLabel(isTrusted: widgetPinned)
                }
                .buttonStyle(AppPressButtonStyle(tint: widgetPinned ? AppDesign.Palette.success : AppDesign.Palette.stale))
                .accessibilityLabel(widgetPinned ? "Remove \(target.name) from trusted widget actions" : "Trust \(target.name) for widgets")
                if canManage {
                    Menu {
                        Button(action: edit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: delete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        AppIconButtonLabel(
                            systemImage: "ellipsis",
                            tint: AppDesign.Palette.action
                        )
                    }
                    .accessibilityLabel("Device options")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(target.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                }
                Text(endpointText)
                    .font(AppDesign.Typography.monoMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    ActionContextChipRow(
                        bridgeName: bridgeName,
                        bridgeReachable: bridgeReachable,
                        widgetPinned: false,
                        configManaged: showsConfigChip,
                        showBridgeChip: !bridgeReachable
                    )
                if let state {
                    actionStateView(state)
                    if let disabledReason, !wakeEnabled {
                        AppStateLine(
                            title: "Unavailable",
                            detail: disabledReason,
                            kind: .stale
                        )
                        if !bridgeReachable, let lastUpdatedAt {
                            lastKnownLine(lastUpdatedAt)
                        }
                    }
                } else if let disabledReason, !wakeEnabled {
                    Label(disabledReason, systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !bridgeReachable, let lastUpdatedAt {
                        lastKnownLine(lastUpdatedAt)
                    }
                } else {
                    freshnessLine
                }
            }

            Spacer(minLength: 0)

            Button(action: wake) {
                ActionTileFooter(
                    title: footerTitle,
                    systemImage: "power",
                    kind: footerKind,
                    isRunning: state?.running == true,
                    isEnabled: wakeEnabled
                )
            }
            .buttonStyle(AppPressButtonStyle(tint: footerKind.color, isEnabled: wakeEnabled && state?.running != true))
            .disabled(!wakeEnabled || state?.running == true)
            .accessibilityLabel("Wake \(target.name)")
            .accessibilityValue(footerTitle)
            .accessibilityHint(footerAccessibilityHint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .appActionSurface(tint: tileStatusKind.color, isEnabled: wakeEnabled || state != nil)
        .opacity(wakeEnabled || state != nil ? 1 : DashboardDesign.disabledOpacity)
        .animation(AppDesign.Motion.stateChange, value: tileStatusTitle)
        .animation(AppDesign.Motion.stateChange, value: state?.running == true)
    }

    private var endpointText: String {
        let endpoint: String
        if let ipAddress = target.ipAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !ipAddress.isEmpty {
            endpoint = target.broadcastIP.isEmpty ? ipAddress : "\(ipAddress) -> \(target.broadcastIP)"
        } else {
            endpoint = target.broadcastIP
        }
        return endpoint.isEmpty ? "UDP \(target.udpPort)" : "\(endpoint) · UDP \(target.udpPort)"
    }

    private var showsConfigChip: Bool {
        target.source == "config"
    }

    private var tileStatusTitle: String {
        if state?.running == true {
            return "Waking"
        }
        if state?.succeeded == true {
            return "Sent"
        }
        if state?.succeeded == false, state != nil {
            return "Failed"
        }
        if wakeEnabled && bridgeReachable {
            return "Can Wake"
        }
        return wakeEnabled ? "Cached" : "Locked"
    }

    private var tileStatusKind: AppStatusKind {
        if state?.running == true {
            return .action
        }
        if state?.succeeded == true {
            return .success
        }
        if state?.succeeded == false, state != nil {
            return .warning
        }
        if wakeEnabled && bridgeReachable {
            return .action
        }
        return .stale
    }

    private var footerTitle: String {
        if state?.running == true {
            return "Waking"
        }
        if !wakeEnabled {
            return "Unavailable"
        }
        if state?.succeeded == false, state != nil {
            return "Retry"
        }
        return "Wake Now"
    }

    private var footerKind: AppStatusKind {
        if state?.running == true {
            return .action
        }
        return wakeEnabled ? .action : .stale
    }

    private var footerAccessibilityHint: String {
        if state?.running == true {
            return "Wake request is running through \(bridgeName)."
        }
        if !wakeEnabled {
            return disabledReason ?? "Wake is unavailable."
        }
        if state?.succeeded == false, state != nil {
            return "Retries Wake-on-LAN through \(bridgeName)."
        }
        return "Sends Wake-on-LAN through \(bridgeName)."
    }

    private var statusIconName: String {
        if state?.running == true {
            return "hourglass"
        }
        if state?.succeeded == true {
            return "checkmark.circle.fill"
        }
        if state?.succeeded == false, state != nil {
            return "exclamationmark.triangle.fill"
        }
        return wakeEnabled ? "power.circle.fill" : "lock.circle.fill"
    }

    private var statusColor: Color {
        if state?.running == true {
            return AppDesign.Palette.wake
        }
        if state?.succeeded == true {
            return AppDesign.Palette.success
        }
        if state?.succeeded == false, state != nil {
            return AppDesign.Palette.warning
        }
        return wakeEnabled ? AppDesign.Palette.action : AppDesign.Palette.stale
    }

    @ViewBuilder
    private func actionStateView(_ state: WOLActionState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AppStateLine(
                title: wakeStateTitle(state),
                detail: wakeStateDetail(state),
                kind: wakeStateKind(state)
            )
            if !state.running, !state.succeeded, let message = state.message?.nilIfBlank {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(wakeStateKind(state).color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func wakeStateTitle(_ state: WOLActionState) -> String {
        if state.running {
            return "Waking"
        }
        if state.succeeded {
            return "Sent"
        }
        if state.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "unavailable" {
            return "Unavailable"
        }
        return "Failed"
    }

    private func wakeStateDetail(_ state: WOLActionState) -> String? {
        var parts: [String] = []
        parts.append(state.bridgeName?.nilIfBlank ?? bridgeName)
        if let updatedAt = state.updatedAt {
            parts.append(Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date()))
        }
        if parts.isEmpty {
            return AppDesign.statusLabel(state.status)
        }
        return parts.joined(separator: " · ")
    }

    private func wakeStateKind(_ state: WOLActionState) -> AppStatusKind {
        if state.running {
            return .action
        }
        return state.succeeded ? .success : .warning
    }

    @ViewBuilder
    private var freshnessLine: some View {
        if (!bridgeReachable || !wakeEnabled), let lastUpdatedAt {
            lastKnownLine(lastUpdatedAt)
        }
    }

    private func lastKnownLine(_ lastUpdatedAt: Date) -> some View {
        AppStateLine(
            title: "Last Confirmed",
            detail: Self.relativeFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date()),
            kind: .stale
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct ManualCommandPanel<Content: View>: View {
    let isExpanded: Bool
    let canCollapse: Bool
    let bridgeName: String
    let commandPreview: String
    let commandEnabled: Bool
    let disabledReason: String?
    let toggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 11) {
                    AppIconBubble(systemImage: iconName, tint: panelKind.color, size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("Command Line")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            AppStatusBadge(title: statusTitle, kind: panelKind, systemImage: panelKind.symbolName)
                        }
                        Text(detailText)
                            .font(trimmedPreview.isEmpty ? .caption : AppDesign.Typography.monoMetadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if canCollapse || !isExpanded {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(panelKind.color)
                            .frame(width: 30, height: 30)
                            .background(panelKind.color.opacity(0.12), in: Circle())
                    }
                }
            }
            .buttonStyle(AppPressButtonStyle(tint: panelKind.color, isEnabled: canCollapse || !isExpanded))
            .disabled(isExpanded && !canCollapse)
            .accessibilityLabel(isExpanded ? "Manual command expanded" : "Open manual command")

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .appSemanticPanel(
            tint: panelKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: isExpanded ? .standard : .quiet
        )
        .animation(AppDesign.Motion.stateChange, value: isExpanded)
    }

    private var trimmedPreview: String {
        commandPreview.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var panelKind: AppStatusKind {
        commandEnabled ? .action : .stale
    }

    private var statusTitle: String {
        commandEnabled ? "Can Run" : "Locked"
    }

    private var iconName: String {
        commandEnabled ? "terminal" : "lock.fill"
    }

    private var detailText: String {
        if !commandEnabled {
            return disabledReason ?? "Command runner unavailable."
        }
        if !trimmedPreview.isEmpty {
            return trimmedPreview
        }
        return "Run once or save a tile through \(bridgeName)."
    }
}

private struct CommandComposer: View {
    @Binding var commandText: String
    let commandRunning: Bool
    let commandEnabled: Bool
    let commandDisabledReason: String?
    let focusedField: FocusState<DashboardFocusField?>.Binding
    let run: () -> Void
    let save: () -> Void
    let clear: () -> Void

    private var trimmedCommand: String {
        commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleDisabledReason: String? {
        if commandRunning {
            return "Command running."
        }
        if !commandEnabled {
            return commandDisabledReason ?? "Command runner unavailable."
        }
        if trimmedCommand.isEmpty {
            return "Enter a command before running it."
        }
        return nil
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
                    .buttonStyle(AppPressButtonStyle(tint: AppDesign.Palette.stale))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear command")
                }
            }

            TextField("ssh user@server wake-desktop", text: $commandText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .commandInputTraits()
                .lineLimit(2...5)
                .focused(focusedField, equals: DashboardFocusField.command)
                .appField()

            HStack(spacing: DashboardDesign.controlSpacing) {
                AppActionButton(
                    title: commandRunning ? "Running" : "Run",
                    systemImage: "terminal",
                    kind: .action,
                    isRunning: commandRunning,
                    isEnabled: !trimmedCommand.isEmpty && commandEnabled,
                    disabledReason: visibleDisabledReason,
                    runningReason: "Command is running through the active bridge.",
                    action: run
                )

                AppActionButton(
                    title: trimmedCommand.isEmpty ? "New Tile" : "Save Tile",
                    systemImage: "plus.square",
                    kind: .stale,
                    isEnabled: !commandRunning,
                    disabledReason: commandRunning ? "Wait for the current command to finish before saving a tile." : nil,
                    action: save
                )
            }
            if let visibleDisabledReason {
                AppDisabledReasonRow(reason: visibleDisabledReason, systemImage: commandEnabled ? "terminal" : "lock.fill")
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

private struct EditorNoticePanel: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var progress = false

    var body: some View {
        AppNoticeRow(title: title, message: message, systemImage: systemImage, tint: tint, progress: progress)
            .padding(14)
            .appSemanticPanel(
                tint: tint,
                cornerRadius: AppDesign.Radius.section,
                prominence: .quiet
            )
    }
}

private struct CommandResultRow: View {
    let title: String?
    let command: String?
    let bridgeName: String
    let status: String
    let output: String?
    let succeeded: Bool
    let isRunning: Bool
    let updatedAt: Date?
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if isRunning {
                    ProgressView()
                        .frame(width: 30, height: 30)
                } else {
                    AppIconBubble(systemImage: statusIcon, tint: statusKind.color, size: 30)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        AppStatusBadge(title: badgeTitle, kind: statusKind, systemImage: statusIcon)
                    }

                    HStack(spacing: 5) {
                        Text(isRunning ? "Running through \(resolvedBridgeName)" : "Ran through \(resolvedBridgeName)")
                        if let updatedAt {
                            Text("·")
                            Text(isRunning ? "Started" : "Finished")
                            Text(updatedAt, style: .relative)
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let command = command?.nilIfBlank {
                CommandResultTextBlock(title: "Command", text: command, isPlaceholder: false)
            }

            CommandResultTextBlock(title: outputTitle, text: outputText, isPlaceholder: output?.nilIfBlank == nil)

            if let retry, !succeeded, !isRunning {
                AppActionButton(
                    title: "Retry Command",
                    systemImage: "arrow.clockwise",
                    kind: .warning,
                    action: retry
                )
            }
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: isRunning ? .standard : .quiet
        )
    }

    private var displayTitle: String {
        if isRunning {
            return title?.nilIfBlank ?? "Running Command"
        }
        if succeeded {
            if let title = title?.nilIfBlank {
                return "\(title) Completed"
            }
            return "Command Completed"
        }
        if let title = title?.nilIfBlank {
            return "\(title) Failed"
        }
        return "Command Failed"
    }

    private var resolvedBridgeName: String {
        bridgeName.nilIfBlank ?? "the active bridge"
    }

    private var badgeTitle: String {
        if isRunning {
            return "RUNNING"
        }
        if succeeded {
            return "DONE"
        }
        if status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "unavailable" {
            return "UNAVAILABLE"
        }
        return "FAILED"
    }

    private var statusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        return succeeded ? .success : .warning
    }

    private var statusIcon: String {
        if isRunning {
            return "terminal.fill"
        }
        return succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var outputTitle: String {
        succeeded ? "Output" : "Error"
    }

    private var outputText: String {
        if let output = output?.nilIfBlank {
            return output
        }
        if isRunning {
            return "Waiting for the bridge to return output."
        }
        return succeeded ? "No output returned." : "No error text returned by the bridge."
    }
}

private struct CommandResultTextBlock: View {
    let title: String
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .lineLimit(8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppDesign.codeBlockFill, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
    }
}

private struct CommandShortcutGrid: View {
    let shortcuts: [CommandShortcut]
    let commandRunning: Bool
    let runningShortcutID: UUID?
    let bridgeName: String
    let bridgeReachable: Bool
    let commandEnabled: Bool
    let commandDisabledReason: String?
    let run: (CommandShortcut) -> Void
    let edit: (CommandShortcut) -> Void
    let delete: (CommandShortcut) -> Void
    let widgetPinned: (CommandShortcut) -> Bool
    let toggleWidgetPin: (CommandShortcut) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(shortcuts) { shortcut in
                CommandShortcutTile(
                    shortcut: shortcut,
                    commandRunning: commandRunning,
                    isRunning: runningShortcutID == shortcut.id,
                    bridgeName: bridgeName,
                    bridgeReachable: bridgeReachable,
                    commandEnabled: commandEnabled,
                    disabledReason: commandDisabledReason,
                    widgetPinned: widgetPinned(shortcut),
                    run: { run(shortcut) },
                    edit: { edit(shortcut) },
                    delete: { delete(shortcut) },
                    toggleWidgetPin: { toggleWidgetPin(shortcut) }
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
    let bridgeName: String
    let bridgeReachable: Bool
    let commandEnabled: Bool
    let disabledReason: String?
    let widgetPinned: Bool
    let run: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let toggleWidgetPin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                AppIconBubble(systemImage: tileIconName, tint: tileStatusKind.color, size: 32)
                AppStatusBadge(title: tileStatusTitle, kind: tileStatusKind, systemImage: tileStatusKind.symbolName)
                Spacer(minLength: 0)
                Button(action: toggleWidgetPin) {
                    WidgetTrustButtonLabel(isTrusted: widgetPinned)
                }
                .buttonStyle(AppPressButtonStyle(tint: widgetPinned ? AppDesign.Palette.success : AppDesign.Palette.stale))
                .accessibilityLabel(widgetPinned ? "Remove \(shortcut.name) from trusted widget actions" : "Trust \(shortcut.name) for widgets")
                Menu {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    AppIconButtonLabel(
                        systemImage: "ellipsis",
                        tint: AppDesign.Palette.action,
                        isEnabled: !commandRunning
                    )
                }
                .disabled(commandRunning)
                .accessibilityLabel("Command tile options")
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
                    .lineLimit(1)
                ActionContextChipRow(
                    bridgeName: bridgeName,
                    bridgeReachable: bridgeReachable,
                    widgetPinned: false,
                    configManaged: false,
                    showBridgeChip: !bridgeReachable
                )
                if let lastRunAt = shortcut.lastRunAt, let lastStatus = shortcut.lastStatus {
                    AppStateLine(
                        title: Self.displayStatus(lastStatus),
                        detail: bridgeReachable ? Self.relativeRunText(lastRunAt) : "\(Self.relativeRunText(lastRunAt)) · \(bridgeName)",
                        kind: AppStatusKind(status: lastStatus)
                    )
                    .accessibilityLabel("Last run \(Self.displayStatus(lastStatus))")
                }
                if !commandEnabled, let disabledReason {
                    AppStateLine(
                        title: "Unavailable",
                        detail: disabledReason,
                        kind: .stale
                    )
                } else if commandRunning && !isRunning {
                    AppStateLine(
                        title: "Busy",
                        detail: "A command is already running.",
                        kind: .stale
                    )
                }
            }

            Spacer(minLength: 0)

            Button(action: run) {
                ActionTileFooter(
                    title: footerTitle,
                    systemImage: "play.fill",
                    kind: footerKind,
                    isRunning: isRunning,
                    isEnabled: commandEnabled && !commandRunning
                )
            }
            .buttonStyle(AppPressButtonStyle(tint: footerKind.color, isEnabled: commandEnabled && !commandRunning))
            .disabled(commandRunning || !commandEnabled)
            .accessibilityLabel("Run \(shortcut.name)")
            .accessibilityValue(footerTitle)
            .accessibilityHint(footerAccessibilityHint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: DashboardDesign.tileMinimumHeight, alignment: .topLeading)
        .appActionSurface(tint: tileStatusKind.color, isEnabled: commandEnabled || isRunning)
        .opacity((commandRunning && !isRunning) || !commandEnabled ? DashboardDesign.disabledOpacity : 1)
        .animation(AppDesign.Motion.stateChange, value: tileStatusTitle)
        .animation(AppDesign.Motion.stateChange, value: isRunning)
        .accessibilityElement(children: .contain)
    }

    private var tileStatusTitle: String {
        if isRunning {
            return "Running"
        }
        if !commandEnabled {
            return "Locked"
        }
        if commandRunning {
            return "Busy"
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return Self.displayStatus(status)
        }
        return "Can Run"
    }

    private var tileStatusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if !commandEnabled || commandRunning {
            return .stale
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status)
        }
        return .action
    }

    private var tileIconName: String {
        if isRunning {
            return "hourglass"
        }
        if !commandEnabled {
            return "lock.fill"
        }
        return "terminal"
    }

    private var footerTitle: String {
        if isRunning {
            return "Running"
        }
        if !commandEnabled {
            return "Unavailable"
        }
        if commandRunning {
            return "Busy"
        }
        if let status = shortcut.lastStatus?.nilIfBlank,
           AppStatusKind(status: status) == .warning {
            return "Retry"
        }
        return "Run Now"
    }

    private var footerKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if !commandEnabled || commandRunning {
            return .stale
        }
        return .action
    }

    private var footerAccessibilityHint: String {
        if isRunning {
            return "Command is running through \(bridgeName)."
        }
        if !commandEnabled {
            return disabledReason ?? "Command runner is unavailable."
        }
        if commandRunning {
            return "Another command is already running."
        }
        if let status = shortcut.lastStatus?.nilIfBlank,
           AppStatusKind(status: status) == .warning {
            return "Retries this saved command through \(bridgeName)."
        }
        return "Runs this saved command through \(bridgeName)."
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

    private static func relativeRunText(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct CommandTilePlanPanel: View {
    let name: String
    let command: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: "terminal", tint: statusKind.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(planTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: statusTitle, kind: statusKind, systemImage: statusKind.symbolName)
                    }
                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(commandPreviewIsPlaceholder ? .secondary : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            AppStateLine(
                title: validationMessage == nil ? "Can Save" : "Save Locked",
                detail: validationMessage ?? "via \(bridgeName)",
                kind: statusKind
            )
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: validationMessage == nil ? .standard : .quiet
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var planTitle: String {
        trimmedName.isEmpty ? "Command Tile" : trimmedName
    }

    private var commandPreview: String {
        trimmedCommand.isEmpty ? "Enter command" : trimmedCommand
    }

    private var commandPreviewIsPlaceholder: Bool {
        trimmedCommand.isEmpty
    }

    private var statusTitle: String {
        validationMessage == nil ? "Can Save" : "Needs Details"
    }

    private var statusKind: AppStatusKind {
        validationMessage == nil ? .success : .stale
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
            ScrollView {
                VStack(spacing: AppDesign.Spacing.section) {
                    CommandTilePlanPanel(
                        name: name,
                        command: command,
                        bridgeName: model.credential?.bridgeName ?? "Active bridge",
                        validationMessage: validationMessage
                    )
                    AppSection(
                        title: "Command Tile",
                        subtitle: "",
                        systemImage: "terminal"
                    ) {
                        AppFieldLabel(title: "Name", systemImage: "textformat")
                        TextField("Name", text: $name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .command
                            }
                            .appField()
                        AppFieldLabel(title: "Command", systemImage: "terminal")
                        TextField("Command", text: $command, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .commandInputTraits()
                            .lineLimit(1...5)
                            .focused($focusedField, equals: .command)
                            .appField()
                    }
                    if let validationMessage, shouldShowValidationNotice {
                        EditorNoticePanel(
                            title: "Save Locked",
                            message: validationMessage,
                            systemImage: "exclamationmark.circle",
                            tint: AppDesign.Palette.locked
                        )
                    }
                    if let inlineError {
                        EditorNoticePanel(
                            title: "Could Not Save Tile",
                            message: inlineError,
                            systemImage: "exclamationmark.triangle",
                            tint: AppDesign.Palette.warning
                        )
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.page)
                .padding(.vertical, AppDesign.Spacing.page)
            }
            .appPage()
            .navigationTitle(shortcut == nil ? "Add Tile" : "Edit Tile")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
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
                    Button("Save") {
                        AppFeedback.actionStarted()
                        inlineError = nil
                        if model.saveCommandShortcut(
                            name: name,
                            command: command,
                            existingID: shortcut?.id
                        ) {
                            AppFeedback.success()
                            focusedField = nil
                            onSaved()
                            dismiss()
                        } else {
                            inlineError = model.errorMessage ?? "Could not save this command tile."
                            model.errorMessage = nil
                            AppFeedback.failure()
                        }
                    }
                    .disabled(validationMessage != nil)
                    .accessibilityValue(validationMessage == nil ? "Available" : "Unavailable")
                    .accessibilityHint(validationMessage ?? "Saves this command tile through the active bridge.")
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

    private var shouldShowValidationNotice: Bool {
        shortcut != nil ||
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formFingerprint: String {
        "\(name)\n\(command)"
    }
}

private struct HealthMonitorPlanPanel: View {
    let name: String
    let kind: String
    let host: String
    let port: String
    let url: String
    let timeoutSeconds: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: statusIconName, tint: statusKind.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(planTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: statusTitle, kind: statusKind, systemImage: statusKind.symbolName)
                    }
                    Text(planSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                AppStateLine(title: "Identity", detail: identityDetail, kind: identityKind)
                AppStateLine(title: endpointTitle, detail: endpointDetail, kind: endpointKind)
                AppStateLine(title: "Timing", detail: timingDetail, kind: timingKind)
            }
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: validationMessage == nil ? .standard : .quiet
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPort: String {
        port.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTimeout: String {
        timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTCP: Bool {
        kind == "tcp"
    }

    private var planTitle: String {
        trimmedName.isEmpty ? "Health Monitor" : trimmedName
    }

    private var planSubtitle: String {
        validationMessage == nil ? "Can save through \(bridgeName)." : "Complete the check details before saving."
    }

    private var statusTitle: String {
        validationMessage == nil ? "Can Save" : "Needs Details"
    }

    private var statusKind: AppStatusKind {
        guard validationMessage != nil else {
            return .success
        }
        return hasInvalidInput ? .warning : .stale
    }

    private var statusIconName: String {
        validationMessage == nil ? "checkmark.circle.fill" : "waveform.path.ecg"
    }

    private var identityDetail: String {
        trimmedName.isEmpty ? "Name required" : (isTCP ? "TCP check" : "HTTP check")
    }

    private var identityKind: AppStatusKind {
        trimmedName.isEmpty ? .stale : .success
    }

    private var endpointTitle: String {
        isTCP ? "Endpoint" : "URL"
    }

    private var endpointDetail: String {
        if isTCP {
            if trimmedHost.isEmpty {
                return "Host required"
            }
            guard portIsValid else {
                return trimmedPort.isEmpty ? "\(trimmedHost) · default port" : "Port invalid"
            }
            return "\(trimmedHost):\(trimmedPort.isEmpty ? "default" : trimmedPort)"
        }
        if trimmedURL.isEmpty {
            return "URL required"
        }
        return Self.isValidHTTPURL(trimmedURL) ? trimmedURL : "URL invalid"
    }

    private var endpointKind: AppStatusKind {
        if isTCP {
            if trimmedHost.isEmpty {
                return .stale
            }
            return portIsValid ? .success : .warning
        }
        if trimmedURL.isEmpty {
            return .stale
        }
        return Self.isValidHTTPURL(trimmedURL) ? .success : .warning
    }

    private var timingDetail: String {
        if let timeout = Int(trimmedTimeout), (1...30).contains(timeout) {
            return "\(timeout)s timeout"
        }
        return trimmedTimeout.isEmpty ? "Timeout required" : "Timeout invalid"
    }

    private var timingKind: AppStatusKind {
        if let timeout = Int(trimmedTimeout), (1...30).contains(timeout) {
            return .success
        }
        return trimmedTimeout.isEmpty ? .stale : .warning
    }

    private var portIsValid: Bool {
        trimmedPort.isEmpty || (Int(trimmedPort).map { (1...65535).contains($0) } ?? false)
    }

    private var hasInvalidInput: Bool {
        (!trimmedPort.isEmpty && !portIsValid) ||
            (!trimmedURL.isEmpty && !Self.isValidHTTPURL(trimmedURL)) ||
            (!trimmedTimeout.isEmpty && timingKind == .warning)
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

private struct HealthMonitorEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let monitor: HealthMonitor?
    let onSaved: (String, Bool) -> Void

    @State private var name: String
    @State private var kind: String
    @State private var host: String
    @State private var port: String
    @State private var url: String
    @State private var timeoutSeconds: String
    @State private var saving = false
    @State private var inlineError: String?
    @FocusState private var focusedField: HealthMonitorEditorFocusField?

    init(monitor: HealthMonitor?, onSaved: @escaping (String, Bool) -> Void) {
        self.monitor = monitor
        self.onSaved = onSaved
        _name = State(initialValue: monitor?.name ?? "")
        _kind = State(initialValue: monitor?.kind ?? "tcp")
        _host = State(initialValue: monitor?.host ?? "")
        _port = State(initialValue: monitor?.port.map(String.init) ?? "22")
        _url = State(initialValue: monitor?.url ?? "")
        _timeoutSeconds = State(initialValue: monitor.map { String($0.timeoutSeconds) } ?? "3")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppDesign.Spacing.section) {
                    HealthMonitorPlanPanel(
                        name: name,
                        kind: kind,
                        host: host,
                        port: port,
                        url: url,
                        timeoutSeconds: timeoutSeconds,
                        bridgeName: model.credential?.bridgeName ?? "Active bridge",
                        validationMessage: validationMessage
                    )
                    AppSection(
                        title: "Monitor",
                        subtitle: "",
                        systemImage: "waveform.path.ecg"
                    ) {
                        AppFieldLabel(title: "Name", systemImage: "textformat")
                        TextField("Name", text: $name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = kind == "tcp" ? .host : .url
                            }
                            .appField()
                        AppFieldLabel(title: "Type", systemImage: "switch.2")
                        Picker("Type", selection: $kind) {
                            Text("TCP").tag("tcp")
                            Text("HTTP").tag("http")
                        }
                        .pickerStyle(.segmented)
                    }

                    if kind == "tcp" {
                        AppSection(
                            title: "TCP Check",
                            subtitle: "",
                            systemImage: "network"
                        ) {
                            AppFieldLabel(title: "Host", systemImage: "server.rack")
                            TextField("Host", text: $host)
                                .commandInputTraits()
                                .focused($focusedField, equals: .host)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .port
                                }
                                .appField()
                            AppFieldLabel(title: "Port", systemImage: "number")
                            TextField("Port", text: $port)
                                .numberInputTraits()
                                .focused($focusedField, equals: .port)
                                .appField()
                        }
                    } else {
                        AppSection(
                            title: "HTTP Check",
                            subtitle: "",
                            systemImage: "globe"
                        ) {
                            AppFieldLabel(title: "URL", systemImage: "link")
                            TextField("URL", text: $url)
                                .commandInputTraits()
                                .focused($focusedField, equals: .url)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .timeoutSeconds
                                }
                                .appField()
                        }
                    }

                    AppSection(
                        title: "Timing",
                        subtitle: "",
                        systemImage: "timer"
                    ) {
                        AppFieldLabel(title: "Timeout Seconds", systemImage: "timer")
                        TextField("Timeout Seconds", text: $timeoutSeconds)
                            .numberInputTraits()
                            .focused($focusedField, equals: .timeoutSeconds)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .appField()
                    }
                    if let validationMessage, shouldShowValidationNotice {
                        EditorNoticePanel(
                            title: "Save Locked",
                            message: validationMessage,
                            systemImage: "exclamationmark.circle",
                            tint: AppDesign.Palette.locked
                        )
                    }
                    if saving {
                        EditorNoticePanel(
                            title: "Saving Monitor",
                            message: "Sending this check to \(model.credential?.bridgeName ?? "the active bridge").",
                            systemImage: "waveform.path.ecg",
                            tint: AppDesign.Palette.action,
                            progress: true
                        )
                    }
                    if let inlineError {
                        EditorNoticePanel(
                            title: "Could Not Save Monitor",
                            message: inlineError,
                            systemImage: "exclamationmark.triangle",
                            tint: AppDesign.Palette.warning
                        )
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.page)
                .padding(.vertical, AppDesign.Spacing.page)
            }
            .appPage()
            .navigationTitle(monitor == nil ? "Add Monitor" : "Edit Monitor")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
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
                                AppFeedback.success()
                                focusedField = nil
                                onSaved(savedName, monitor != nil)
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not save this monitor."
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

    private var saveAccessibilityValue: String {
        if saving {
            return "In progress"
        }
        return validationMessage == nil ? "Available" : "Unavailable"
    }

    private var saveAccessibilityHint: String {
        if saving {
            return "Saving this monitor to the active bridge."
        }
        return validationMessage ?? "Saves this monitor through the active bridge."
    }

    private var formFingerprint: String {
        "\(name)\n\(kind)\n\(host)\n\(port)\n\(url)\n\(timeoutSeconds)"
    }

    private var shouldShowValidationNotice: Bool {
        if monitor != nil {
            return true
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines) != "3"
    }

    private var savedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Monitor"
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

private struct WOLWakePlanPanel: View {
    let name: String
    let mac: String
    let ipAddress: String
    let broadcastIP: String
    let udpPort: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: statusIconName, tint: statusKind.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(planTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: statusTitle, kind: statusKind, systemImage: statusKind.symbolName)
                    }
                    Text(planSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                AppStateLine(title: "Identity", detail: identityDetail, kind: identityKind)
                AppStateLine(title: "Route", detail: routeDetail, kind: routeKind)
                AppStateLine(title: "Packet", detail: packetDetail, kind: packetKind)
            }
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: validationMessage == nil ? .standard : .quiet
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedIP: String {
        ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBroadcast: String {
        broadcastIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPort: String {
        udpPort.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMAC: String? {
        WOLInputFormatter.normalizedMACAddress(mac)
    }

    private var suggestedBroadcast: String? {
        WOLInputFormatter.suggestedBroadcastIP(from: trimmedIP)
    }

    private var planTitle: String {
        trimmedName.isEmpty ? "Wake Target" : trimmedName
    }

    private var planSubtitle: String {
        validationMessage == nil ? "Can save through \(bridgeName)." : "Complete the details before saving."
    }

    private var statusTitle: String {
        validationMessage == nil ? "Can Save" : "Needs Details"
    }

    private var statusKind: AppStatusKind {
        guard validationMessage != nil else {
            return .success
        }
        return hasInvalidInput ? .warning : .stale
    }

    private var statusIconName: String {
        validationMessage == nil ? "power.circle.fill" : "power.circle"
    }

    private var identityDetail: String {
        if trimmedName.isEmpty {
            return "Name required"
        }
        guard let normalizedMAC else {
            return mac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MAC required" : "MAC invalid"
        }
        return normalizedMAC.uppercased()
    }

    private var identityKind: AppStatusKind {
        if !trimmedName.isEmpty && normalizedMAC != nil {
            return .success
        }
        return mac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .stale : .warning
    }

    private var routeDetail: String {
        if !trimmedBroadcast.isEmpty {
            if !trimmedIP.isEmpty {
                return "\(trimmedIP) -> \(trimmedBroadcast)"
            }
            return "Broadcast \(trimmedBroadcast)"
        }
        if let suggestedBroadcast {
            return "Bridge derives \(suggestedBroadcast)"
        }
        return "IP or broadcast required"
    }

    private var routeKind: AppStatusKind {
        if !trimmedBroadcast.isEmpty {
            return WOLInputFormatter.isValidIPv4Address(trimmedBroadcast) ? .success : .warning
        }
        if !trimmedIP.isEmpty {
            return WOLInputFormatter.isValidIPv4Address(trimmedIP) ? .success : .warning
        }
        return .stale
    }

    private var packetDetail: String {
        if let port = Int(trimmedPort), (1...65535).contains(port) {
            return "UDP \(port)"
        }
        return trimmedPort.isEmpty ? "UDP 9 default" : "Port invalid"
    }

    private var packetKind: AppStatusKind {
        if trimmedPort.isEmpty {
            return .success
        }
        return (Int(trimmedPort).map { (1...65535).contains($0) } ?? false) ? .success : .warning
    }

    private var hasInvalidInput: Bool {
        (!mac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedMAC == nil) ||
            (!trimmedIP.isEmpty && !WOLInputFormatter.isValidIPv4Address(trimmedIP)) ||
            (!trimmedBroadcast.isEmpty && !WOLInputFormatter.isValidIPv4Address(trimmedBroadcast)) ||
            (!trimmedPort.isEmpty && !(Int(trimmedPort).map { (1...65535).contains($0) } ?? false))
    }
}

private struct WOLTargetEditorView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    let target: WOLTarget?
    let onSaved: (String, Bool) -> Void

    @State private var name: String
    @State private var mac: String
    @State private var ipAddress: String
    @State private var broadcastIP: String
    @State private var udpPort: String
    @State private var saving = false
    @State private var inlineError: String?
    @FocusState private var focusedField: WOLTargetEditorFocusField?

    init(target: WOLTarget?, onSaved: @escaping (String, Bool) -> Void) {
        self.target = target
        self.onSaved = onSaved
        _name = State(initialValue: target?.name ?? "")
        _mac = State(initialValue: target?.mac ?? "")
        _ipAddress = State(initialValue: target?.ipAddress ?? "")
        _broadcastIP = State(initialValue: target?.broadcastIP ?? "")
        _udpPort = State(initialValue: target.map { String($0.udpPort) } ?? "9")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppDesign.Spacing.section) {
                    WOLWakePlanPanel(
                        name: name,
                        mac: mac,
                        ipAddress: ipAddress,
                        broadcastIP: broadcastIP,
                        udpPort: udpPort,
                        bridgeName: model.credential?.bridgeName ?? "Active bridge",
                        validationMessage: validationMessage
                    )
                    AppSection(
                        title: "Device",
                        subtitle: "",
                        systemImage: "desktopcomputer"
                    ) {
                        AppFieldLabel(title: "Name", systemImage: "textformat")
                        TextField("Name", text: $name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .mac
                            }
                            .appField()
                        AppFieldLabel(title: "MAC Address", systemImage: "network")
                        TextField("MAC Address", text: $mac)
                            .commandInputTraits()
                            .focused($focusedField, equals: .mac)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .ipAddress
                            }
                            .appField()
                        AppFieldLabel(title: "IP Address", systemImage: "wifi")
                        TextField("IP Address", text: $ipAddress)
                            .commandInputTraits()
                            .focused($focusedField, equals: .ipAddress)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .broadcastIP
                            }
                            .appField()
                    }
                    AppSection(
                        title: "Network",
                        subtitle: "",
                        systemImage: "dot.radiowaves.left.and.right"
                    ) {
                        AppFieldLabel(title: "Broadcast IP", systemImage: "antenna.radiowaves.left.and.right")
                        TextField("Broadcast IP", text: $broadcastIP)
                            .commandInputTraits()
                            .focused($focusedField, equals: .broadcastIP)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .udpPort
                            }
                            .appField()
                        if let suggestedBroadcastIP, broadcastIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                AppFeedback.selection()
                                broadcastIP = suggestedBroadcastIP
                            } label: {
                                Label("Use \(suggestedBroadcastIP)", systemImage: "arrow.down.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppDesign.Palette.action)
                            }
                            .buttonStyle(AppPressButtonStyle(tint: AppDesign.Palette.action))
                        }
                        AppFieldLabel(title: "UDP Port", systemImage: "number")
                        TextField("UDP Port", text: $udpPort)
                            .numberInputTraits()
                            .focused($focusedField, equals: .udpPort)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .appField()
                    }
                    if let validationMessage, shouldShowValidationNotice {
                        EditorNoticePanel(
                            title: "Save Locked",
                            message: validationMessage,
                            systemImage: "exclamationmark.circle",
                            tint: AppDesign.Palette.locked
                        )
                    }
                    if saving {
                        EditorNoticePanel(
                            title: "Saving Device",
                            message: "Sending this Wake-on-LAN target to \(model.credential?.bridgeName ?? "the active bridge").",
                            systemImage: "power",
                            tint: AppDesign.Palette.action,
                            progress: true
                        )
                    }
                    if let inlineError {
                        EditorNoticePanel(
                            title: "Could Not Save Device",
                            message: inlineError,
                            systemImage: "exclamationmark.triangle",
                            tint: AppDesign.Palette.warning
                        )
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.page)
                .padding(.vertical, AppDesign.Spacing.page)
            }
            .appPage()
            .navigationTitle(target == nil ? "Add Device" : "Edit Device")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: formFingerprint) { _, _ in
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
                            let saved = await model.saveWOLTarget(
                                name: name,
                                mac: normalizedMACForSave,
                                ipAddress: ipAddress,
                                broadcastIP: broadcastIP,
                                udpPort: udpPort,
                                existingID: target?.id
                            )
                            saving = false
                            if saved {
                                AppFeedback.success()
                                focusedField = nil
                                onSaved(savedName, target != nil)
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not save this device."
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
        if WOLInputFormatter.normalizedMACAddress(trimmedMAC) == nil {
            return "Enter a valid MAC address."
        }
        if trimmedIPAddress.isEmpty && trimmedBroadcastIP.isEmpty {
            return "Enter either an IP address or broadcast IP."
        }
        if !trimmedIPAddress.isEmpty && !WOLInputFormatter.isValidIPv4Address(trimmedIPAddress) {
            return "IP address must be IPv4."
        }
        if !trimmedBroadcastIP.isEmpty && !WOLInputFormatter.isValidIPv4Address(trimmedBroadcastIP) {
            return "Broadcast IP must be IPv4."
        }
        if !trimmedPort.isEmpty && !(Int(trimmedPort).map { (1...65535).contains($0) } ?? false) {
            return "UDP port must be between 1 and 65535."
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
            return "Saving this Wake-on-LAN device to the active bridge."
        }
        return validationMessage ?? "Saves this Wake-on-LAN device through the active bridge."
    }

    private var normalizedMACForSave: String {
        WOLInputFormatter.normalizedMACAddress(mac) ?? mac.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Device"
    }

    private var suggestedBroadcastIP: String? {
        WOLInputFormatter.suggestedBroadcastIP(from: ipAddress)
    }

    private var shouldShowValidationNotice: Bool {
        if target != nil {
            return true
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !mac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !broadcastIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            udpPort.trimmingCharacters(in: .whitespacesAndNewlines) != "9"
    }

    private var formFingerprint: String {
        "\(name)\n\(mac)\n\(ipAddress)\n\(broadcastIP)\n\(udpPort)"
    }

    private static func isValidMACAddress(_ value: String) -> Bool {
        WOLInputFormatter.normalizedMACAddress(value) != nil
    }

    private static func isValidIPv4Address(_ value: String) -> Bool {
        WOLInputFormatter.isValidIPv4Address(value)
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
