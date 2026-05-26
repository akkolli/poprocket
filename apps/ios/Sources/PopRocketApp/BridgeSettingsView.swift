import PopRocketKit
import SwiftUI

struct BridgeSettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false
    @State private var pendingRemoval: BridgeRemoval?

    var body: some View {
        NavigationStack {
            List {
                Section("Bridges") {
                    if model.bridges.isEmpty {
                        ContentUnavailableView("No Bridges", systemImage: "antenna.radiowaves.left.and.right")
                    } else {
                        ForEach(model.bridges, id: \.bridgeID) { bridge in
                            Button {
                                Task { await model.setActiveBridge(bridge) }
                            } label: {
                                BridgeRow(
                                    bridge: bridge,
                                    active: model.credential?.bridgeID == bridge.bridgeID
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

private struct BridgeRemoval: Identifiable {
    let bridge: PairingCredential
    var id: String { bridge.bridgeID }
}
