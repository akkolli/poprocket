import PopRocketKit
import SwiftUI

struct BridgeSettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false
    @State private var pendingRemoval: BridgeRemoval?
    @State private var renameTarget: BridgeRename?

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
                                    Task { await model.setActiveBridge(bridge) }
                                } label: {
                                    BridgeRow(
                                        bridge: bridge,
                                        active: model.credential?.bridgeID == bridge.bridgeID
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    renameTarget = BridgeRename(bridge: bridge)
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Rename \(bridge.bridgeName)")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    renameTarget = BridgeRename(bridge: bridge)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    pendingRemoval = BridgeRemoval(bridge: bridge)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingPairing = true
                    } label: {
                        Label("Add Bridge", systemImage: "plus")
                    }
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
                        Task { await model.removeBridge(removal.bridge) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

private struct BridgeRow: View {
    let bridge: PairingCredential
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(bridge.bridgeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(active ? "Active bridge" : "Tap to make active")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(active ? .green : .secondary)
                Text(bridge.directURLs.first?.absoluteString ?? bridge.bridgeID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Active")
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
                    #else
                    TextField("Bridge Name", text: $name)
                    #endif
                }
                Section("Address") {
                    Text(bridge.directURLs.first?.absoluteString ?? bridge.bridgeID)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Bridge")
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
                            let saved = await model.renameBridge(bridge, name: name)
                            saving = false
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BridgeRemoval: Identifiable {
    let bridge: PairingCredential
    var id: String { bridge.bridgeID }
}

private struct BridgeRename: Identifiable {
    let bridge: PairingCredential
    var id: String { bridge.bridgeID }
}
