import PopRocketKit
import SwiftUI

struct BridgeSettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false
    @State private var pendingRemoval: BridgeRemoval?
    @State private var renameTarget: BridgeRename?
    @State private var selectingBridgeID: String?
    @State private var reconnectingBridgeID: String?
    @State private var removingBridgeID: String?
    @State private var statusMessage: String?
    @State private var inlineError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Bridges") {
                    if model.bridges.isEmpty {
                        ContentUnavailableView("No Bridges", systemImage: "antenna.radiowaves.left.and.right")
                    } else {
                        ForEach(model.bridges, id: \.bridgeID) { bridge in
                            HStack(spacing: 8) {
                                Button {
                                    select(bridge)
                                } label: {
                                    BridgeRow(
                                        bridge: bridge,
                                        active: model.credential?.bridgeID == bridge.bridgeID,
                                        activeHealthy: model.bridgeHealthy,
                                        activeStatusText: model.bridgeStatusText
                                    )
                                }
                                .disabled(operationInProgress)
                                .buttonStyle(.plain)

                                Button {
                                    reconnect(bridge)
                                } label: {
                                    if reconnectingBridgeID == bridge.bridgeID {
                                        ProgressView()
                                            .frame(width: 36, height: 36)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .frame(width: 36, height: 36)
                                    }
                                }
                                .disabled(operationInProgress)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Reconnect \(bridge.bridgeName)")

                                Button {
                                    renameTarget = BridgeRename(bridge: bridge)
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 36, height: 36)
                                }
                                .disabled(operationInProgress)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Rename \(bridge.bridgeName)")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    reconnect(bridge)
                                } label: {
                                    Label("Reconnect", systemImage: "arrow.clockwise")
                                }
                                .disabled(operationInProgress)
                                Button {
                                    renameTarget = BridgeRename(bridge: bridge)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .disabled(operationInProgress)
                                Button(role: .destructive) {
                                    pendingRemoval = BridgeRemoval(bridge: bridge)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .disabled(operationInProgress)
                            }
                        }
                    }
                }

                if statusMessage != nil || inlineError != nil {
                    Section("Status") {
                        if selectingBridgeID != nil {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(statusMessage ?? "Selecting bridge")
                            }
                        } else if reconnectingBridgeID != nil {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(statusMessage ?? "Reconnecting")
                            }
                        } else if removingBridgeID != nil {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(statusMessage ?? "Removing bridge")
                            }
                        } else if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                        if let inlineError {
                            Label(inlineError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        showingPairing = true
                    } label: {
                        Label("Add Bridge", systemImage: "plus")
                    }
                    .disabled(operationInProgress)
                }
            }
            .navigationTitle("Bridge Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
        }
    }

    private var operationInProgress: Bool {
        selectingBridgeID != nil || reconnectingBridgeID != nil || removingBridgeID != nil
    }

    private func select(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        Task {
            selectingBridgeID = bridge.bridgeID
            statusMessage = "Selecting \(bridge.bridgeName)"
            inlineError = nil
            let selected = await model.setActiveBridge(bridge)
            selectingBridgeID = nil
            if selected {
                statusMessage = "\(model.credential?.bridgeName ?? bridge.bridgeName) is online"
            } else {
                let message = model.errorMessage ?? "Could not verify \(bridge.bridgeName)."
                statusMessage = nil
                if model.credential?.bridgeID == bridge.bridgeID {
                    inlineError = "Selected \(bridge.bridgeName), but verification failed: \(message)"
                } else {
                    inlineError = "Could not select \(bridge.bridgeName): \(message)"
                }
                model.errorMessage = nil
            }
        }
    }

    private func remove(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        Task {
            removingBridgeID = bridge.bridgeID
            statusMessage = "Removing \(bridge.bridgeName)"
            inlineError = nil
            let removedAndVerified = await model.removeBridge(bridge)
            let removed = !model.bridges.contains { $0.bridgeID == bridge.bridgeID }
            removingBridgeID = nil
            if removedAndVerified {
                statusMessage = "Removed \(bridge.bridgeName)"
            } else {
                let message = model.errorMessage ?? "Could not remove \(bridge.bridgeName)."
                statusMessage = nil
                if removed {
                    inlineError = "Removed \(bridge.bridgeName), but the active bridge could not be verified: \(message)"
                } else {
                    inlineError = "Could not remove \(bridge.bridgeName): \(message)"
                }
                model.errorMessage = nil
            }
        }
    }

    private func reconnect(_ bridge: PairingCredential) {
        guard !operationInProgress else {
            return
        }
        Task {
            reconnectingBridgeID = bridge.bridgeID
            statusMessage = "Reconnecting to \(bridge.bridgeName)"
            inlineError = nil
            let reconnected = await model.reconnectBridge(bridge)
            reconnectingBridgeID = nil
            if reconnected {
                statusMessage = "Reconnected to \(model.credential?.bridgeName ?? bridge.bridgeName)"
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not reconnect \(bridge.bridgeName)."
                model.errorMessage = nil
            }
        }
    }
}

private struct BridgeRow: View {
    let bridge: PairingCredential
    let active: Bool
    let activeHealthy: Bool
    let activeStatusText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(bridge.bridgeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(active ? "Selected bridge" : "Tap to select")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(active ? .blue : .secondary)
                if active {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activeHealthy ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(activeStatusText)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(activeHealthy ? .green : .orange)
                }
                Text(bridge.directURLs.first?.absoluteString ?? bridge.bridgeID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if active {
                Text("ACTIVE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(Capsule())
                    .accessibilityLabel("Selected bridge")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
            Form {
                Section("Name") {
                    #if canImport(UIKit)
                    TextField("Bridge Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                    #else
                    TextField("Bridge Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                    #endif
                }
                if let validationMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let inlineError {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(inlineError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section("Address") {
                    Text(bridge.directURLs.first?.absoluteString ?? bridge.bridgeID)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Bridge")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: name) { _, _ in
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
                            let saved = await model.renameBridge(bridge, name: name)
                            saving = false
                            if saved {
                                dismiss()
                            } else {
                                inlineError = model.errorMessage ?? "Could not rename this bridge."
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
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name this bridge."
        }
        return nil
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
