import PopRocketKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshIfStale()
            }
        }
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
                    summary: healthMonitorSummary,
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
                    summary: healthMonitorSummary,
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
            return "\(credential.bridgeName) · up \(AppFormat.shortDuration(seconds: bridgeHealth.uptimeSeconds))"
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

    private var healthMonitorSummary: HealthMonitorSummary {
        HealthMonitorSummary(monitors: model.healthMonitors)
    }

    private var overviewAlertMonitors: [HealthMonitor] {
        Array(healthMonitorSummary.alertMonitors.prefix(2))
    }

    private var healthMonitorsSortedForDisplay: [HealthMonitor] {
        healthMonitorSummary.sortedMonitors
    }

    private var healthDownMonitors: [HealthMonitor] {
        healthMonitorSummary.downMonitors
    }

    private var healthUnknownMonitors: [HealthMonitor] {
        healthMonitorSummary.unknownMonitors
    }

    private var healthUpMonitors: [HealthMonitor] {
        healthMonitorSummary.upMonitors
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
        let names = healthMonitorSummary.downMonitors
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
        overviewLastConfirmedAt.map { AppFormat.relativeShort($0) }
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
        healthMonitorSummary.upCount
    }

    private var healthDownCount: Int {
        healthMonitorSummary.downCount
    }

    private var healthUnknownCount: Int {
        healthMonitorSummary.unknownCount
    }

    private func relativeUpdateText(_ date: Date) -> String {
        "updated \(AppFormat.relativeShort(date))"
    }

    private func compactRelativeUpdateText(_ date: Date) -> String {
        AppFormat.relativeShort(date)
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
        let relative = AppFormat.relativeShort(lastConfirmedAt)
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
        HealthMonitorSummary(monitors: monitors).downMonitors
    }

    private func monitorStatusMap(_ monitors: [HealthMonitor]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: monitors.map { monitor in
            (monitor.id, HealthMonitorStatusCategory.status(for: monitor).normalizedValue)
        })
    }

    private func normalizedMonitorStatus(_ status: String) -> String {
        HealthMonitorStatusCategory.status(for: status).normalizedValue
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

}
