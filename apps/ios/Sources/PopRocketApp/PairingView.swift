import PopRocketKit
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var qrText = ""
    @State private var bridgeURL = ""
    @State private var bridgeName = ""
    @State private var showingScanner = false
    @State private var pairing = false
    @State private var statusMessage: String?
    @State private var inlineError: String?
    @FocusState private var focusedField: PairingFocusField?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    nameField
                }

                Section("Manual") {
                    urlField
                    Button(pairing ? "Connecting" : "Connect") {
                        connectManually()
                    }
                    .disabled(!canConnectManually)
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
                        pairFromPayload()
                    }
                    .disabled(!canPairFromPayload)
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
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                    qrText = value
                    showingScanner = false
                }
            }
        }
    }

    private var nameField: some View {
        #if canImport(UIKit)
        TextField("Bridge Name", text: $bridgeName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeName)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .bridgeURL
            }
        #else
        TextField("Bridge Name", text: $bridgeName)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeName)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .bridgeURL
            }
        #endif
    }

    private var urlField: some View {
        #if canImport(UIKit)
        TextField("http://pi.local:6567", text: $bridgeURL)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeURL)
            .submitLabel(.go)
            .onSubmit {
                connectManually()
            }
        #else
        TextField("http://pi.local:6567", text: $bridgeURL)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .bridgeURL)
            .submitLabel(.go)
            .onSubmit {
                connectManually()
            }
        #endif
    }

    private var payloadEditor: some View {
        #if canImport(UIKit)
        TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .payload)
        #else
        TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .payload)
        #endif
    }

    private var canConnectManually: Bool {
        !pairing && !bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canPairFromPayload: Bool {
        !pairing && !qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connectManually() {
        guard canConnectManually else { return }
        focusedField = nil
        Task {
            pairing = true
            inlineError = nil
            statusMessage = "Connecting to \(displayURL(bridgeURL))"
            let paired = await model.completeManualPairing(bridgeURL: bridgeURL, displayName: bridgeName)
            pairing = false
            if paired {
                statusMessage = "Connected to \(model.credential?.bridgeName ?? "bridge")"
                dismiss()
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not connect to \(displayURL(bridgeURL))."
                model.errorMessage = nil
            }
        }
    }

    private func pairFromPayload() {
        guard canPairFromPayload else { return }
        focusedField = nil
        Task {
            pairing = true
            inlineError = nil
            statusMessage = "Pairing from QR payload"
            let paired = await model.completePairing(rawPayload: qrText, displayName: bridgeName)
            pairing = false
            if paired {
                statusMessage = "Connected to \(model.credential?.bridgeName ?? "bridge")"
                dismiss()
            } else {
                statusMessage = nil
                inlineError = model.errorMessage ?? "Could not pair with this payload."
                model.errorMessage = nil
            }
        }
    }

    private func displayURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }
}

private enum PairingFocusField: Hashable {
    case bridgeName
    case bridgeURL
    case payload
}
