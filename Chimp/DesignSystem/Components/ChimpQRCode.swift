import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Grille de modules (les petits carrés) d'un QR code.
///
/// Générée **localement** par Core Image, fourni par iOS : aucune dépendance, rien n'est envoyé sur le réseau.
/// Correction d'erreur au niveau le plus fort (H, 30 %) : le code reste lisible malgré la tête de Chimpy
/// posée en son centre.
nonisolated struct ChimpQRMatrix: Equatable {
    /// Nombre de modules par côté (21, 25, 29… selon la longueur du message).
    let count: Int
    /// Modules ligne par ligne, du haut vers le bas ; `true` = module sombre.
    private let modules: [Bool]

    /// `nil` si Core Image ne sait pas encoder le message (vide ou trop long).
    init?(message: String) {
        guard !message.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "H"
        // Core Image rend un pixel par module, marge blanche comprise.
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            // Dans un contexte bitmap, la première ligne de la mémoire est le haut de l'image.
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // On retire la marge blanche : les motifs de repérage touchent les bords du code.
        let isDark = { (x: Int, y: Int) in pixels[y * width + x] < 128 }
        let darkRows = (0..<height).filter { y in (0..<width).contains { isDark($0, y) } }
        let darkColumns = (0..<width).filter { x in (0..<height).contains { isDark(x, $0) } }
        guard let top = darkRows.first, let bottom = darkRows.last,
              let left = darkColumns.first, let right = darkColumns.last,
              bottom - top == right - left
        else { return nil }

        count = bottom - top + 1
        var modules: [Bool] = []
        modules.reserveCapacity(count * count)
        for y in top...bottom {
            for x in left...right {
                modules.append(isDark(x, y))
            }
        }
        self.modules = modules
    }

    func isDark(row: Int, column: Int) -> Bool {
        modules[row * count + column]
    }
}

/// QR code de la maquette D1 : modules sombres sur une carte blanche (dans les deux thèmes,
/// pour que les scanners le lisent bien), **tête de Chimpy seule** au centre (décision de Barth du 2026-10-01 : sans le
/// carré jaune). La tête (`ChimpyHead`, détourée de `tile-head`) est posée sur une petite zone blanche sans modules,
/// alignée sur la grille ; la correction d'erreur H couvre cette zone (vérifié par décodage, `QRCodeTests`).
///
/// Sans message (`nil`) : la carte vide avec une roue d'attente (chargement).
struct ChimpQRCode: View {
    private let matrix: ChimpQRMatrix?
    private let isLoading: Bool
    var side: CGFloat = ChimpSize.qrCode

    @Environment(\.displayScale) private var displayScale

    init(message: String?, side: CGFloat = ChimpSize.qrCode) {
        matrix = message.flatMap(ChimpQRMatrix.init(message:))
        isLoading = message == nil
        self.side = side
    }

    var body: some View {
        content
            .frame(width: side, height: side)
            .padding(ChimpSpacing.lg + ChimpBorder.regular)
            .cartoonSurface(
                RoundedRectangle(cornerRadius: ChimpRadius.qrCard),
                fill: Color(.chimpQRBackground),
                shadow: .qrCard
            )
    }

    @ViewBuilder
    private var content: some View {
        if let matrix {
            symbol(matrix)
        } else if isLoading {
            ProgressView()
                .tint(Color(.chimpQRModule))
                .accessibilityLabel(Text("Loading"))
        } else {
            // Ne devrait pas arriver avec une adresse Stellar : on le dit plutôt que d'afficher un code faux.
            Text("QR code unavailable")
                .chimpFont(.caption)
                .foregroundStyle(.chimpQRModule)
                .multilineTextAlignment(.center)
        }
    }

    private func symbol(_ matrix: ChimpQRMatrix) -> some View {
        // Modules alignés sur les pixels de l'écran : pas de fines lignes blanches entre deux modules.
        let moduleSide = (side * displayScale / CGFloat(matrix.count)).rounded(.down) / displayScale
        let symbolSide = moduleSide * CGFloat(matrix.count)
        // Nombre impair de modules pour que la tête de Chimpy tombe pile au centre du code.
        var badgeModules = Int((CGFloat(matrix.count) * ChimpSize.qrBadgeFraction).rounded())
        if badgeModules % 2 == 0 { badgeModules += 1 }
        // La tête est plus large que haute : la zone blanche suit ses proportions (moins de modules cachés).
        var clearRows = Int((CGFloat(badgeModules) * ChimpSize.qrHeadAspect).rounded())
        if clearRows % 2 == 0 { clearRows += 1 }

        return ZStack {
            Canvas { context, _ in
                var path = Path()
                for row in 0..<matrix.count {
                    for column in 0..<matrix.count where matrix.isDark(row: row, column: column) {
                        path.addRect(CGRect(
                            x: CGFloat(column) * moduleSide,
                            y: CGFloat(row) * moduleSide,
                            width: moduleSide,
                            height: moduleSide
                        ))
                    }
                }
                context.fill(path, with: .color(Color(.chimpQRModule)))
            }
            .frame(width: symbolSide, height: symbolSide)

            Rectangle()
                .fill(Color(.chimpQRBackground))
                .frame(width: CGFloat(badgeModules) * moduleSide, height: CGFloat(clearRows) * moduleSide)
            Image(.chimpyHead)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                // Une demi-marge de module autour de la tête : elle ne touche jamais un module.
                .padding(moduleSide / 2)
                .frame(width: CGFloat(badgeModules) * moduleSide, height: CGFloat(clearRows) * moduleSide)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("QR code"))
    }
}

#Preview("Adresse") {
    ChimpQRCode(message: "CAIO2SJ6UNDZELXIPQTONOBOURBWJFNNB5DHQWRVUDVZVPZRJLAZVOX2")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.chimpBackground))
}

#Preview("Chargement · sombre") {
    ChimpQRCode(message: nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.chimpBackground))
        .preferredColorScheme(.dark)
}
