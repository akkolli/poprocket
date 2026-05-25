import PopRocketKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var showingPairing = false

    var body: some View {
        NavigationStack {
            List {
                if model.credential == nil {
                    Section {
                        Button {
                            showingPairing = true
                        } label: {
                            Label("Pair Bridge", systemImage: "qrcode.viewfinder")
                        }
                    }
                }

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
            .navigationTitle("PopRocket")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
