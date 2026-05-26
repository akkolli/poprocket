import PopRocketKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var qrText = ""
    @State private var bridgeURL = ""
    @State private var showingScanner = false
    @State private var pairing = false
    @State private var statusMessage: String?
    @State private var inlineError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Manual") {
                    urlField
                    Button(pairing ? "Connecting" : "Connect") {
                        Task {
                            pairing = true
                            inlineError = nil
                            statusMessage = "Connecting to \(displayURL(bridgeURL))"
                            let paired = await model.completeManualPairing(bridgeURL: bridgeURL)
                            pairing = false
                            if paired {
                                statusMessage = "Connected to \(model.credential?.bridgeName ?? "bridge")"
                                dismiss()
                            } else {
                                statusMessage = nil
                                inlineError = model.errorMessage ?? "Could not connect to \(displayURL(bridgeURL))."
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
                            inlineError = nil
                            statusMessage = "Pairing from QR payload"
                            let paired = await model.completePairing(rawPayload: qrText)
                            pairing = false
                            if paired {
                                statusMessage = "Connected to \(model.credential?.bridgeName ?? "bridge")"
                                dismiss()
                            } else {
                                statusMessage = nil
                                inlineError = model.errorMessage ?? "Could not pair with this payload."
                            }
                        }
                    }
                    .disabled(pairing || qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if pairing || statusMessage != nil || inlineError != nil {
                    Section("Status") {
                        if pairing {
                            HStack {
                                ProgressView()
                                Text(statusMessage ?? "Connecting")
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
        TextField("http://pi.local:6567", text: $bridgeURL)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("http://pi.local:6567", text: $bridgeURL)
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

    private func displayURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }
}
