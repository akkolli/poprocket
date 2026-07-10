import Foundation
import PopRocketKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CommandShortcutEditorView: View {
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

struct EditorPlanStatusRow {
    let title: String
    let detail: String?
    let kind: AppStatusKind
}

struct EditorPlanPanel: View {
    let title: String
    let subtitle: String
    let subtitleUsesMonospace: Bool
    let subtitleIsPlaceholder: Bool
    let systemImage: String
    let statusTitle: String
    let statusKind: AppStatusKind
    let primaryRow: EditorPlanStatusRow
    let secondaryRow: EditorPlanStatusRow?
    let tertiaryRow: EditorPlanStatusRow?
    let canSave: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: systemImage, tint: statusKind.color, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: statusTitle, kind: statusKind, systemImage: statusKind.symbolName)
                    }
                    subtitleView
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                statusLine(primaryRow)
                if let secondaryRow {
                    statusLine(secondaryRow)
                }
                if let tertiaryRow {
                    statusLine(tertiaryRow)
                }
            }
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: canSave ? .standard : .quiet
        )
    }

    private func statusLine(_ row: EditorPlanStatusRow) -> some View {
        AppStateLine(title: row.title, detail: row.detail, kind: row.kind)
    }

    @ViewBuilder
    private var subtitleView: some View {
        if subtitleUsesMonospace {
            Text(subtitle)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(subtitleIsPlaceholder ? .secondary : .primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HealthMonitorPlanPanel: View {
    let name: String
    let kind: String
    let host: String
    let port: String
    let url: String
    let timeoutSeconds: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        EditorPlanPanel(
            title: planTitle,
            subtitle: planSubtitle,
            subtitleUsesMonospace: false,
            subtitleIsPlaceholder: false,
            systemImage: statusIconName,
            statusTitle: statusTitle,
            statusKind: statusKind,
            primaryRow: EditorPlanStatusRow(title: "Identity", detail: identityDetail, kind: identityKind),
            secondaryRow: EditorPlanStatusRow(title: endpointTitle, detail: endpointDetail, kind: endpointKind),
            tertiaryRow: EditorPlanStatusRow(title: "Timing", detail: timingDetail, kind: timingKind),
            canSave: validationMessage == nil
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

struct HealthMonitorEditorView: View {
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

struct WOLWakePlanPanel: View {
    let name: String
    let mac: String
    let ipAddress: String
    let broadcastIP: String
    let udpPort: String
    let bridgeName: String
    let validationMessage: String?

    var body: some View {
        EditorPlanPanel(
            title: planTitle,
            subtitle: planSubtitle,
            subtitleUsesMonospace: false,
            subtitleIsPlaceholder: false,
            systemImage: statusIconName,
            statusTitle: statusTitle,
            statusKind: statusKind,
            primaryRow: EditorPlanStatusRow(title: "Identity", detail: identityDetail, kind: identityKind),
            secondaryRow: EditorPlanStatusRow(title: "Route", detail: routeDetail, kind: routeKind),
            tertiaryRow: EditorPlanStatusRow(title: "Packet", detail: packetDetail, kind: packetKind),
            canSave: validationMessage == nil
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

struct WOLTargetEditorView: View {
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
extension View {
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
extension View {
    func commandInputTraits() -> some View {
        self
    }

    func numberInputTraits() -> some View {
        self
    }
}
#endif

extension String {
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
