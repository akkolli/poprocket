import PopRocketKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var qrText = ""
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    TextEditor(text: $qrText)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Pair") {
                        Task {
                            await model.completePairing(rawPayload: qrText)
                            if model.credential != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Pair Bridge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { value in
                    qrText = value
                    showingScanner = false
                }
            }
        }
    }
}
