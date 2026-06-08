import SwiftUI

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannerError: String?

    let onCode: (String) -> Void

    var body: some View {
        ZStack {
            #if canImport(UIKit) && canImport(AVFoundation)
            ScannerCameraView(
                onCode: onCode,
                onError: { message in
                    scannerError = message
                }
            )
            .ignoresSafeArea()
            #else
            AppDesign.background.ignoresSafeArea()
            #endif

            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                scannerHeader
                    .padding(.horizontal, AppDesign.Spacing.page)
                    .padding(.top, 12)

                Spacer(minLength: 24)

                ScannerFrame(tint: scannerError == nil ? AppDesign.Palette.action : AppDesign.Palette.warning)
                    .frame(width: 248, height: 248)
                    .accessibilityHidden(true)

                if let scannerError {
                    scannerErrorPanel(scannerError)
                        .padding(.horizontal, AppDesign.Spacing.page)
                        .padding(.top, 24)
                } else {
                    scannerHint
                        .padding(.horizontal, AppDesign.Spacing.page)
                        .padding(.top, 24)
                }

                Spacer(minLength: 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scannerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconBubble(systemImage: "qrcode.viewfinder", tint: AppDesign.Palette.action, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Scan Bridge QR")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Pairing stays on your local bridge.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
            AppIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Close scanner",
                tint: AppDesign.Palette.stale
            ) {
                AppFeedback.selection()
                dismiss()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var scannerHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.caption.weight(.semibold))
            Text("Place the bridge QR code inside the frame.")
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func scannerErrorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: "exclamationmark.triangle.fill", tint: AppDesign.Palette.warning, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Scanner Unavailable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        AppStatusBadge(title: "PASTE", kind: .warning, systemImage: "doc.on.clipboard")
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AppActionButton(
                title: "Paste Payload Instead",
                systemImage: "doc.on.clipboard",
                kind: .warning
            ) {
                AppFeedback.selection()
                dismiss()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(AppDesign.Palette.warning.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct ScannerFrame: View {
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            ScannerCornerSet(tint: tint)
                .padding(10)
        }
    }
}

private struct ScannerCornerSet: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let length: CGFloat = 46
            let stroke: CGFloat = 5

            Path { path in
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))

                path.move(to: CGPoint(x: size.width - length, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: length))

                path.move(to: CGPoint(x: size.width, y: size.height - length))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: size.width - length, y: size.height))

                path.move(to: CGPoint(x: length, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height - length))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .shadow(color: tint.opacity(0.38), radius: 10, x: 0, y: 0)
        }
    }
}

#if canImport(UIKit) && canImport(AVFoundation)
private struct ScannerCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.poprocket.qrscanner.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        startIfAuthorized()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func startIfAuthorized() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.reportScannerError("Camera access is off. Enable Camera access in Settings or paste the pairing payload.")
                    }
                }
            }
        case .denied, .restricted:
            reportScannerError("Camera access is off. Enable Camera access in Settings or paste the pairing payload.")
        @unknown default:
            reportScannerError("Camera access is unavailable. Paste the pairing payload instead.")
        }
    }

    private func configureAndStart() {
        guard !configured else {
            startSession()
            return
        }
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            reportScannerError("This device cannot start the camera. Paste the pairing payload instead.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            reportScannerError("This device cannot scan QR codes. Paste the pairing payload instead.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
        configured = true
        startSession()
    }

    private func startSession() {
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func reportScannerError(_ message: String) {
        onError?(message)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else {
            return
        }
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        onCode?(value)
    }
}
#endif
