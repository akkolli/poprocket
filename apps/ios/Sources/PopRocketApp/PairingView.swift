import PopRocketKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var qrText = ""
    @State private var bridgeURL = ""
    @State private var bridgeName = ""
    @State private var pairingCode = ""
    @State private var showingScanner = false
    @State private var pairing = false
    @State private var pairingMode: PairingMode = .manual
    @State private var statusMessage: String?
    @State private var inlineError: String?
    @State private var enableNotifications = true
    @FocusState private var focusedField: PairingFocusField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppDesign.Spacing.section) {
                    PairingTrustPanel(
                        mode: pairingMode,
                        bridgeURL: bridgeURL,
                        payload: qrText,
                        pairing: pairing,
                        statusMessage: statusMessage,
                        inlineError: inlineError
                    )

                    methodSection

                    AppSection(
                        title: "Bridge",
                        subtitle: "",
                        systemImage: pairingMode.systemImage,
                        tint: activePairingTint
                    ) {
                        AppFieldLabel(title: "Display Name", systemImage: "textformat")
                        nameField

                        Toggle(isOn: $enableNotifications) {
                            Label("Important Notifications", systemImage: "bell.badge")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(AppDesign.Palette.bridge)
                        .disabled(pairing)
                        Text("Ask after pairing so bridge failures and security alerts can reach this iPhone and Apple Watch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        switch pairingMode {
                        case .manual:
                            manualPairingControls
                        case .payload:
                            payloadPairingControls
                        }
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.page)
                .padding(.vertical, AppDesign.Spacing.page)
            }
            .appPage()
            .navigationTitle("Add Bridge")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppFeedback.selection()
                        dismiss()
                    }
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
            .sheet(isPresented: $showingScanner) {
                QRScannerView { value in
                    AppFeedback.selection()
                    qrText = value
                    inlineError = nil
                    statusMessage = nil
                    focusedField = nil
                    showingScanner = false
                }
            }
        }
    }

    private var methodSection: some View {
        AppSection(
            title: "Method",
            subtitle: "",
            systemImage: "switch.2",
            tint: activePairingTint
        ) {
            Picker("Pairing Method", selection: $pairingMode) {
                ForEach(PairingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pairing)
            .tint(activePairingTint)
            .accessibilityLabel("Pairing method")
            .onChange(of: pairingMode) { oldValue, newValue in
                guard oldValue != newValue else { return }
                AppFeedback.selection()
                resetTransientPairingState()
            }

            if pairing {
                AppDisabledReasonRow(reason: "Method locked while verifying.", systemImage: "clock")
            }
        }
    }

    private var nameField: some View {
        #if canImport(UIKit)
        TextField("Optional name", text: $bridgeName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeName)
            .submitLabel(.next)
            .onSubmit {
                focusedField = pairingMode == .manual ? .bridgeURL : .payload
            }
            .appField()
        #else
        TextField("Optional name", text: $bridgeName)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeName)
            .submitLabel(.next)
            .onSubmit {
                focusedField = pairingMode == .manual ? .bridgeURL : .payload
            }
            .appField()
        #endif
    }

    private var pairingCodeField: some View {
        #if canImport(UIKit)
        SecureField("Shown by the bridge installer", text: $pairingCode)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .appField()
        #else
        SecureField("Shown by the bridge installer", text: $pairingCode)
            .autocorrectionDisabled()
            .appField()
        #endif
    }

    private var urlField: some View {
        #if canImport(UIKit)
        TextField("http://bridge.local:6567", text: $bridgeURL)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeURL)
            .submitLabel(.go)
            .onSubmit {
                connectManually()
            }
            .appField()
        #else
        TextField("http://bridge.local:6567", text: $bridgeURL)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeURL)
            .submitLabel(.go)
            .onSubmit {
                connectManually()
            }
            .appField()
        #endif
    }

    private var payloadEditor: some View {
        #if canImport(UIKit)
        payloadEditorBody
            .textInputAutocapitalization(.never)
        #else
        payloadEditorBody
        #endif
    }

    private var payloadEditorBody: some View {
        ZStack(alignment: .topLeading) {
            if qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Paste pairing payload")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $qrText)
                .frame(minHeight: 108)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .payload)
                .padding(8)
        }
        .appSemanticPanel(
            tint: payloadReadinessKind.color,
            isActive: payloadReadinessKind != .stale,
            prominence: .quiet
        )
    }

    @ViewBuilder
    private var manualPairingControls: some View {
        AppFieldLabel(title: "Bridge URL", systemImage: "network")
        urlField
        AppFieldLabel(title: "Pairing Code", systemImage: "key.fill")
        pairingCodeField
        Text("Required by new bridges; older bridges may leave this blank.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let manualActionDisabledReason {
            AppDisabledReasonRow(reason: manualActionDisabledReason, systemImage: "link")
        }
        AppActionButton(
            title: pairing ? "Verifying" : "Verify & Save",
            systemImage: "checkmark.seal",
            kind: inlineError == nil ? .action : .warning,
            isRunning: pairing,
            isEnabled: canConnectManually,
            disabledReason: manualActionDisabledReason,
            runningReason: "Verifying the bridge URL and saving credentials."
        ) {
            AppFeedback.actionStarted()
            connectManually()
        }
    }

    @ViewBuilder
    private var payloadPairingControls: some View {
        HStack(spacing: AppDesign.Spacing.control) {
            AppActionButton(
                title: "Scan QR",
                systemImage: "qrcode.viewfinder",
                kind: .action,
                isEnabled: !pairing,
                disabledReason: "Wait for the current pairing check to finish."
            ) {
                AppFeedback.selection()
                focusedField = nil
                showingScanner = true
            }

            if !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Clear pairing payload",
                    tint: AppDesign.Palette.stale,
                    isEnabled: !pairing,
                    disabledReason: "Wait for the current pairing check to finish before clearing the payload."
                ) {
                    AppFeedback.selection()
                    qrText = ""
                    resetTransientPairingState()
                }
            }
        }
        AppFieldLabel(title: "Payload", systemImage: "key")
        payloadEditor
        if let payloadActionDisabledReason {
            AppDisabledReasonRow(reason: payloadActionDisabledReason, systemImage: "qrcode")
        }
        AppActionButton(
            title: pairing ? "Verifying" : "Verify & Save",
            systemImage: "checkmark.seal",
            kind: inlineError == nil ? .action : .warning,
            isRunning: pairing,
            isEnabled: canPairFromPayload,
            disabledReason: payloadActionDisabledReason,
            runningReason: "Verifying the pairing payload and saving credentials."
        ) {
            AppFeedback.actionStarted()
            pairFromPayload()
        }
    }

    private var canConnectManually: Bool {
        !pairing && manualURLValidationMessage == nil
    }

    private var canPairFromPayload: Bool {
        !pairing && !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var manualActionDisabledReason: String? {
        guard !pairing else { return nil }
        return manualURLValidationMessage
    }

    private var manualURLValidationMessage: String? {
        PairingURLFormatter.validationMessage(for: bridgeURL)
    }

    private var payloadActionDisabledReason: String? {
        guard !pairing else { return nil }
        return qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scan or paste a pairing payload." : nil
    }

    private var manualPairingTint: Color {
        if inlineError != nil {
            return AppDesign.Palette.warning
        }
        if pairing {
            return AppDesign.Palette.action
        }
        if let manualURLValidationMessage {
            return manualURLValidationMessage == "Enter a bridge URL." ? AppDesign.Palette.stale : AppDesign.Palette.warning
        }
        if !bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PairingMode.manual.tint
        }
        return AppDesign.Palette.stale
    }

    private var payloadPairingTint: Color {
        if inlineError != nil {
            return AppDesign.Palette.warning
        }
        if !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pairing ? AppDesign.Palette.action : PairingMode.payload.tint
        }
        return AppDesign.Palette.stale
    }

    private var activePairingTint: Color {
        switch pairingMode {
        case .manual:
            return manualPairingTint
        case .payload:
            return payloadPairingTint
        }
    }

    private var payloadReadinessKind: AppStatusKind {
        if pairing {
            return .action
        }
        return qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .stale : .action
    }

    private func connectManually() {
        guard !pairing else { return }
        focusedField = nil
        guard let normalizedBridgeURL = PairingURLFormatter.normalizedDisplayURL(bridgeURL) else {
            inlineError = manualURLValidationMessage ?? "Enter a valid bridge URL."
            statusMessage = nil
            AppFeedback.warning()
            return
        }
        Task {
            pairing = true
            inlineError = nil
            statusMessage = "Requesting credential from \(normalizedBridgeURL)."
            let pairingAccessToken = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let paired = await model.completeManualPairing(
                bridgeURL: normalizedBridgeURL,
                pairingAccessToken: pairingAccessToken.isEmpty ? nil : pairingAccessToken,
                displayName: bridgeName
            )
            pairing = false
            if paired {
                statusMessage = "Credential saved for \(model.credential?.bridgeName ?? "bridge")."
                AppFeedback.success()
                await requestNotificationsIfEnabled()
                await dismissAfterSuccess()
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not connect to \(normalizedBridgeURL)."
                model.errorMessage = nil
                AppFeedback.failure()
            }
        }
    }

    private func pairFromPayload() {
        guard canPairFromPayload else { return }
        focusedField = nil
        Task {
            pairing = true
            inlineError = nil
            statusMessage = "Verifying payload and requesting credential."
            let paired = await model.completePairing(rawPayload: qrText, displayName: bridgeName)
            pairing = false
            if paired {
                statusMessage = "Credential saved for \(model.credential?.bridgeName ?? "bridge")."
                AppFeedback.success()
                await requestNotificationsIfEnabled()
                await dismissAfterSuccess()
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not add this payload."
                model.errorMessage = nil
                AppFeedback.failure()
            }
        }
    }

    private func resetTransientPairingState() {
        inlineError = nil
        statusMessage = nil
        focusedField = nil
    }

    private func dismissAfterSuccess() async {
        try? await Task.sleep(nanoseconds: 550_000_000)
        dismiss()
    }

    private func requestNotificationsIfEnabled() async {
        #if os(iOS)
        guard enableNotifications else { return }
        await RemoteNotificationRegistrar.shared.requestAuthorizationAndRegister()
        #endif
    }

}

private enum PairingFocusField: Hashable {
    case bridgeName
    case bridgeURL
    case payload
}

private struct PairingTrustPanel: View {
    let mode: PairingMode
    let bridgeURL: String
    let payload: String
    let pairing: Bool
    let statusMessage: String?
    let inlineError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: statusIconName, tint: statusKind.color, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: badgeTitle, kind: statusKind, systemImage: statusKind.symbolName)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if pairing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            PairingStepStrip(steps: steps)
        }
        .padding(14)
        .appSemanticPanel(
            tint: statusKind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: statusKind == .stale ? .quiet : .standard
        )
        .animation(AppDesign.Motion.stateChange, value: statusKind)
        .animation(AppDesign.Motion.stateChange, value: sourceDetail)
    }

    private var trimmedURL: String {
        bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPayload: String {
        payload.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        if inlineError != nil {
            return "Bridge Not Added"
        }
        if statusMessage != nil && !pairing {
            return "Bridge Verified"
        }
        if pairing {
            return "Verifying Bridge"
        }
        if sourceKind == .action {
            return "Can Verify Bridge"
        }
        return "Add Local Bridge"
    }

    private var detail: String {
        if let inlineError {
            return inlineError
        }
        if let statusMessage {
            return statusMessage
        }
        switch mode {
        case .manual:
            if sourceKind == .warning {
                return "Use local HTTP or HTTPS for a remote bridge."
            }
            return sourceKind == .action ? "\(sourceDetail) can be verified." : "Enter a local bridge URL."
        case .payload:
            return sourceKind == .action ? "Payload is ready to verify." : "Scan or paste a pairing payload."
        }
    }

    private var badgeTitle: String {
        if inlineError != nil {
            return "Check"
        }
        if statusMessage != nil && !pairing {
            return "Verified"
        }
        if pairing {
            return "Working"
        }
        if sourceKind == .warning {
            return "Check"
        }
        return sourceKind == .action ? "Can Verify" : "Needed"
    }

    private var statusKind: AppStatusKind {
        if inlineError != nil {
            return .warning
        }
        if statusMessage != nil && !pairing {
            return .success
        }
        if pairing {
            return .action
        }
        return sourceKind
    }

    private var statusIconName: String {
        if inlineError != nil {
            return "exclamationmark.triangle.fill"
        }
        if statusMessage != nil && !pairing {
            return "checkmark.seal.fill"
        }
        if pairing {
            return "antenna.radiowaves.left.and.right"
        }
        return "checkmark.seal"
    }

    private var sourceDetail: String {
        switch mode {
        case .manual:
            if trimmedURL.isEmpty {
                return "URL required"
            }
            return PairingURLFormatter.normalizedDisplayURL(trimmedURL) ?? "URL invalid"
        case .payload:
            return trimmedPayload.isEmpty ? "Payload required" : "Payload loaded"
        }
    }

    private var sourceKind: AppStatusKind {
        switch mode {
        case .manual:
            guard !trimmedURL.isEmpty else {
                return .stale
            }
            return PairingURLFormatter.normalizedDisplayURL(trimmedURL) == nil ? .warning : .action
        case .payload:
            return trimmedPayload.isEmpty ? .stale : .action
        }
    }

    private var verifyDetail: String {
        if inlineError != nil {
            return "Failed"
        }
        if statusMessage != nil && !pairing {
            return "Verified"
        }
        return pairing ? "Checking" : "Pending"
    }

    private var verifyKind: AppStatusKind {
        if inlineError != nil {
            return .warning
        }
        if statusMessage != nil && !pairing {
            return .success
        }
        return pairing ? .action : .stale
    }

    private var credentialDetail: String {
        if inlineError != nil {
            return "Not saved"
        }
        if statusMessage != nil && !pairing {
            return "Saved"
        }
        return pairing ? "Saving" : "Pending"
    }

    private var credentialKind: AppStatusKind {
        if inlineError != nil {
            return .warning
        }
        if statusMessage != nil && !pairing {
            return .success
        }
        return pairing ? .action : .stale
    }

    private var steps: [PairingStep] {
        [
            PairingStep(
                title: mode.sourceTitle,
                detail: sourceDetail,
                systemImage: mode.systemImage,
                kind: sourceKind
            ),
            PairingStep(
                title: "Verify",
                detail: verifyDetail,
                systemImage: verifyKind.symbolName,
                kind: verifyKind
            ),
            PairingStep(
                title: "Save",
                detail: credentialDetail,
                systemImage: credentialKind.symbolName,
                kind: credentialKind
            )
        ]
    }

    private func displayURL(_ value: String) -> String {
        PairingURLFormatter.normalizedDisplayURL(value) ?? value
    }
}

private struct PairingStep: Identifiable, Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let kind: AppStatusKind

    var id: String { title }
}

private struct PairingStepStrip: View {
    let steps: [PairingStep]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                stepItems
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                stepItems
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pairing progress")
    }

    @ViewBuilder
    private var stepItems: some View {
        ForEach(steps) { step in
            PairingStepChip(step: step)
        }
    }
}

private struct PairingStepChip: View {
    let step: PairingStep

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: step.systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(step.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(step.kind.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 9)
        .background(step.kind.color.opacity(0.09), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(step.kind.color.opacity(0.16), lineWidth: 1)
        }
        .foregroundStyle(step.kind.color)
        .accessibilityElement(children: .combine)
    }
}

private enum PairingMode: String, CaseIterable, Identifiable {
    case manual
    case payload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "URL"
        case .payload:
            return "QR"
        }
    }

    var systemImage: String {
        switch self {
        case .manual:
            return "link"
        case .payload:
            return "qrcode.viewfinder"
        }
    }

    var sourceTitle: String {
        switch self {
        case .manual:
            return "URL"
        case .payload:
            return "Payload"
        }
    }

    var tint: Color {
        switch self {
        case .manual:
            return AppDesign.Palette.bridge
        case .payload:
            return AppDesign.Palette.widget
        }
    }
}
