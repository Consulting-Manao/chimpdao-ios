import AVFoundation
import SwiftUI

/// C1 « Scan QR » : la caméra lit un code QR (AVFoundation, fourni par iOS, aucune dépendance). Le premier code lu est
/// rendu tel quel à `onCode` ; c'est `ScannedCodeParser` qui décide s'il est accepté.
///
/// L'accès à la caméra est demandé ici, la première fois seulement (texte `NSCameraUsageDescription` de l'Info.plist).
/// Refusé : explication et lien vers les Réglages. Sans caméra (simulateur) : coller l'adresse ; en Debug et Testing,
/// des codes d'exemple permettent d'essayer chaque cas.
struct QRScannerScreen: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void

    @State private var access: CameraAccess?
    @State private var detected = false
    @Environment(\.openURL) private var openURL

    enum CameraAccess {
        case allowed
        case denied
        case unavailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if access == .allowed {
                QRCameraPreview { code in
                    guard !detected else { return }
                    detected = true
                    onCode(code)
                }
                .ignoresSafeArea()
                viewfinder
            }
            VStack(spacing: 0) {
                VStack(spacing: ChimpSpacing.xs) {
                    Text("Scan their code")
                        .chimpFont(.displayM)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("Point at the QR code of a Stellar address.")
                        .chimpFont(.bodyS)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                .padding(.top, ChimpSpacing.xxl)
                .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                Spacer()
                if let access, access != .allowed {
                    problem(access)
                    Spacer()
                }
                ChimpButton("Cancel", kind: .secondary, action: onCancel)
                    .padding(.horizontal, ChimpSpacing.fullScreenMargin)
                    .padding(.bottom, ChimpSpacing.l)
            }
        }
        .sensoryFeedback(.success, trigger: detected)
        .chimpSound(.tap, trigger: detected) { _, new in new }
        .task { access = await Self.requestAccess() }
    }

    /// Cadre de visée jaune au centre.
    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: ChimpRadius.panel)
            .strokeBorder(Color(.chimpAccent), lineWidth: ChimpBorder.thick)
            .frame(width: 250, height: 250)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func problem(_ access: CameraAccess) -> some View {
        VStack(spacing: ChimpSpacing.m) {
            switch access {
            case .denied:
                ChimpySays(text: "I can't use the camera. Allow it in Settings, or go back and paste the address.", pose: .head)
                ChimpButton("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .unavailable:
                ChimpySays(text: "There's no camera here. Go back and paste the address.", pose: .head)
                #if DESIGN_CATALOG
                sampleCodes
                #endif
            case .allowed:
                EmptyView()
            }
        }
        .padding(.horizontal, ChimpSpacing.fullScreenMargin)
    }

    #if DESIGN_CATALOG
    /// Debug et Testing, sans caméra (simulateur) : des codes d'exemple, un par cas géré.
    private var sampleCodes: some View {
        VStack(spacing: ChimpSpacing.xs) {
            ForEach(QRScannerSamples.all, id: \.label) { sample in
                Button(sample.label) { onCode(sample.payload) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
        }
    }
    #endif

    /// Demande l'accès la première fois ; ensuite, la réponse déjà donnée.
    static func requestAccess() async -> CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .allowed : .denied
        default: return .denied
        }
    }
}

#if DESIGN_CATALOG
/// Codes d'exemple du catalogue (non traduits : outil de test).
enum QRScannerSamples {
    struct Sample {
        let label: String
        let payload: String
    }

    static let all: [Sample] = [
        Sample(label: "G address (Maya)", payload: MockSendService.mayaAddress),
        Sample(label: "M address (exchange)", payload: MockSendService.exchangeMuxedAddress),
        Sample(label: "SEP-7 · 12.5 XLM", payload: "web+stellar:pay?destination=\(MockSendService.mayaAddress)&amount=12.5&network_passphrase=Test%20SDF%20Network%20%3B%20September%202015"),
        Sample(label: "SEP-7 · 5 USDC + memo ID", payload: "web+stellar:pay?destination=\(MockSendService.tomAddress)&amount=5&asset_code=USDC&asset_issuer=\(ChimpNetworkConfig.testnet.usdcIssuer)&memo=1234567890&memo_type=MEMO_ID&network_passphrase=Test%20SDF%20Network%20%3B%20September%202015"),
        Sample(label: "SEP-7 · public network", payload: "web+stellar:pay?destination=\(MockSendService.mayaAddress)&amount=1"),
        Sample(label: "SEP-7 · sign request (tx)", payload: "web+stellar:tx?xdr=AAAA"),
        Sample(label: "Own Main account", payload: MockReceiveDataSource.mainAddress),
        Sample(label: "Website link", payload: "https://chimpdao.xyz"),
    ]
}
#endif

/// Aperçu de la caméra et lecture des codes QR (AVCaptureMetadataOutput).
private struct QRCameraPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = context.coordinator.session
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return view }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return view }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        private let onCode: (String) -> Void
        private let queue = DispatchQueue(label: "chimp.qr-camera")
        private var delivered = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        /// La caméra démarre hors du fil principal (`startRunning` bloque).
        func start() {
            queue.async { [session] in session.startRunning() }
        }

        func stop() {
            queue.async { [session] in session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered,
                  let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue
            else { return }
            delivered = true
            stop()
            onCode(code)
        }
    }
}
