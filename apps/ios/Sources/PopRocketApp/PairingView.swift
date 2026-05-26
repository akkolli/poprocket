import PopRocketKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var qrText = ""
    @State private var bridgeURL = ""
    @State private var showingScanner = false
    @State private var pairing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Manual") {
                    urlField
                    Button(pairing ? "Connecting" : "Connect") {
                        Task {
                            pairing = true
                            await model.completeManualPairing(bridgeURL: bridgeURL)
                            pairing = false
                            if model.credential != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(pairing || bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("QR") {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    payloadEditor
                }

                Section {
                    Button("Pair") {
                        Task {
                            pairing = true
                            await model.completePairing(rawPayload: qrText)
                            pairing = false
                            if model.credential != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(pairing || qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var urlField: some View {
        #if canImport(UIKit)
        TextField("http://pi.local:8080", text: $bridgeURL)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("http://pi.local:8080", text: $bridgeURL)
            .autocorrectionDisabled()
        #endif
    }

    private var payloadEditor: some View {
        #if canImport(UIKit)
        TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .autocorrectionDisabled()
        #endif
    }
}
