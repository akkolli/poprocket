import PopRocketKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var showingPairing = false
    @State private var showingBridgeSettings = false
    @State private var targetEditor: TargetEditorState?
    @State private var commandText = ""

    var body: some View {
        NavigationStack {
            List {
                bridgeSection
                wakeSection
                commandSection
                cardsSection
            }
            .navigationTitle("PopRocket")
            .toolbar {
                ToolbarItemGroup(placement: Self.toolbarPlacement) {
                    Button {
                        showingBridgeSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Bridge Settings")

                    Button {
                        Task { try? await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showingPairing) {
                PairingView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingBridgeSettings) {
                BridgeSettingsView()
                    .environmentObject(model)
            }
            .sheet(item: $targetEditor) { state in
                WOLTargetEditorView(target: state.target)
                    .environmentObject(model)
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
                                    .fill(model.bridgeReachable ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(model.bridgeStatusText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(model.bridgeReachable ? .green : .orange)
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
                if model.wolTargets.isEmpty {
                    ContentUnavailableView("No Targets", systemImage: "desktopcomputer")
                } else {
                    ForEach(model.wolTargets) { target in
                        WOLTargetRow(target: target) {
                            Task { await model.wake(target) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                targetEditor = TargetEditorState(target: target)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            if target.source != "config" {
                                Button(role: .destructive) {
                                    Task { await model.deleteWOLTarget(target) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Button {
                    targetEditor = TargetEditorState(target: nil)
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        Section("Commands") {
            if model.credential == nil {
                ContentUnavailableView("Pair Bridge", systemImage: "terminal")
            } else {
                TextField("ssh lepton@pluto wake neptune", text: $commandText, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .lineLimit(1...4)

                Button {
                    Task { await model.runCommand(commandText) }
                } label: {
                    HStack {
                        Label(model.commandRunning ? "Running" : "Run Command", systemImage: "terminal")
                        Spacer()
                        if model.commandRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(model.commandRunning || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
        Section("Cards") {
            if model.cards.isEmpty {
                ContentUnavailableView("No Cards", systemImage: "rectangle.grid.2x2")
            } else {
                ForEach(model.cards) { card in
                    CardRow(card: card)
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
}

private struct TargetEditorState: Identifiable {
    let id = UUID()
    let target: WOLTarget?
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

private struct WOLTargetRow: View {
    let target: WOLTarget
    let wake: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.headline)
                Text(target.ipAddress ?? target.broadcastIP)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(target.mac)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: wake) {
                Image(systemName: "power")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Wake \(target.name)")
        }
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
                    TextField("MAC Address", text: $mac)
                    TextField("IP Address", text: $ipAddress)
                }
                Section("Network") {
                    TextField("Broadcast IP", text: $broadcastIP)
                    TextField("UDP Port", text: $udpPort)
                }
            }
            .navigationTitle(target == nil ? "Add Device" : "Edit Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving" : "Save") {
                        Task {
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
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving || !canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !mac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (!ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             !broadcastIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status == "fresh" ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
            .foregroundStyle(status == "fresh" ? .green : .orange)
            .clipShape(Capsule())
    }
}
