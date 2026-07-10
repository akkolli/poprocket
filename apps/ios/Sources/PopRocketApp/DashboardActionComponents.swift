import Foundation
import PopRocketKit
import SwiftUI

struct WOLTargetGrid: View {
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

struct WOLTargetTile: View {
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

            HoldToRunControl(
                isEnabled: wakeEnabled && state?.running != true,
                tint: footerTint,
                accessibilityLabel: "Wake \(target.name)",
                accessibilityValue: footerTitle,
                accessibilityHint: footerAccessibilityHint,
                action: wake
            ) { isHolding in
                ActionTileFooter(
                    title: footerTitle,
                    systemImage: "power",
                    kind: footerKind,
                    tint: footerTint,
                    isRunning: state?.running == true,
                    isEnabled: wakeEnabled,
                    isHolding: isHolding
                )
            }
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
            return "Hold to Retry"
        }
        return "Hold to Wake"
    }

    private var footerKind: AppStatusKind {
        if state?.running == true {
            return .action
        }
        return wakeEnabled ? .action : .stale
    }

    private var footerTint: Color {
        if state?.running == true {
            return AppDesign.Palette.wake
        }
        return wakeEnabled ? AppDesign.Palette.wake : AppDesign.Palette.stale
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
        return "Hold to send Wake-on-LAN through \(bridgeName)."
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
        return wakeEnabled ? AppDesign.Palette.wake : AppDesign.Palette.stale
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
            parts.append(AppFormat.relativeShort(updatedAt))
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
            detail: AppFormat.relativeShort(lastUpdatedAt),
            kind: .stale
        )
    }

}

struct ManualCommandPanel<Content: View>: View {
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

struct CommandComposer: View {
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

struct CommandUnavailableRow: View {
    let reason: String

    var body: some View {
        Label(reason, systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

struct EditorNoticePanel: View {
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

struct CommandResultRow: View {
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

struct CommandResultTextBlock: View {
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

struct CommandShortcutGrid: View {
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

struct CommandShortcutTile: View {
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

            HoldToRunControl(
                isEnabled: commandEnabled && !commandRunning,
                tint: footerTint,
                accessibilityLabel: "Run \(shortcut.name)",
                accessibilityValue: footerTitle,
                accessibilityHint: footerAccessibilityHint,
                action: run
            ) { isHolding in
                ActionTileFooter(
                    title: footerTitle,
                    systemImage: "play.fill",
                    kind: footerKind,
                    tint: footerTint,
                    isRunning: isRunning,
                    isEnabled: commandEnabled && !commandRunning,
                    isHolding: isHolding
                )
            }
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
            return "Hold to Retry"
        }
        return "Hold to Run"
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

    private var footerTint: Color {
        if isRunning {
            return AppDesign.Palette.command
        }
        if !commandEnabled || commandRunning {
            return AppDesign.Palette.stale
        }
        return AppDesign.Palette.command
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
        return "Hold to run this saved command through \(bridgeName)."
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
        AppFormat.relativeShort(date)
    }

}

struct CommandTilePlanPanel: View {
    let name: String
    let command: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        EditorPlanPanel(
            title: planTitle,
            subtitle: commandPreview,
            subtitleUsesMonospace: true,
            subtitleIsPlaceholder: commandPreviewIsPlaceholder,
            systemImage: "terminal",
            statusTitle: statusTitle,
            statusKind: statusKind,
            primaryRow: EditorPlanStatusRow(
                title: validationMessage == nil ? "Can Save" : "Save Locked",
                detail: validationMessage ?? "via \(bridgeName)",
                kind: statusKind
            ),
            secondaryRow: nil,
            tertiaryRow: nil,
            canSave: validationMessage == nil
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
