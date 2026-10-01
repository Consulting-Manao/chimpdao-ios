import CoreImage
import SwiftUI
import Testing
@testable import ChimpDAO

/// D1 · le QR code de Recevoir, avec la tête de Chimpy seule au centre (décision de Barth du 2026-10-01) : rendu comme à
/// l'écran, en clair et en sombre, puis **décodé** (détecteur de QR de Core Image : Vision ne tourne pas dans le simulateur),
/// il doit redonner exactement l'adresse. Les captures du simulateur sont aussi décodées par Vision sur le Mac.
@MainActor
struct QRCodeTests {
    /// Adresses C (Main, wallet d'une carte) et G : 56 caractères, la longueur de toutes les adresses de Recevoir.
    static let addresses = [
        MockReceiveDataSource.mainAddress,
        MockReceiveDataSource.jungleAddress,
        MockSendService.mayaAddress,
    ]

    @Test("Le QR de Recevoir se décode en clair et en sombre, à la taille de l'écran et en petit (iPhone SE)", arguments: addresses)
    func decodes(address: String) throws {
        for scheme in [ColorScheme.light, .dark] {
            for side in [ChimpSize.qrCode, 150] {
                let decoded = try Self.decode(ChimpQRCode(message: address, side: side), scheme: scheme)
                #expect(decoded == [address], "\(scheme) · \(side) pt")
            }
        }
    }

    /// Rend la vue (échelle 3, comme un iPhone) et lit les QR codes qu'elle contient.
    static func decode(_ view: some View, scheme: ColorScheme) throws -> [String] {
        let renderer = ImageRenderer(content: view.padding(20).background(Color(.chimpBackground)).environment(\.colorScheme, scheme))
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        return detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
