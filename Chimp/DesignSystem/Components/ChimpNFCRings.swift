import SwiftUI

/// Anneaux jaunes qui grossissent et s'effacent autour de la carte : « approchez la carte ».
/// Si « Réduire les animations » est activé, les anneaux restent visibles mais figés.
struct ChimpNFCRings<Center: View>: View {
    var config: ChimpMotion.Ring.Config = ChimpMotion.Ring.sheet
    var size: CGFloat = ChimpSize.nfcRingArea
    @ViewBuilder let center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<config.count, id: \.self) { index in
                    let progress = reduceMotion ? frozenProgress(index) : progress(index, at: time)
                    Circle()
                        .strokeBorder(Color(.chimpAccent), lineWidth: ChimpMotion.Ring.lineWidth)
                        .scaleEffect(scale(progress))
                        .opacity(opacity(progress))
                }
                center
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement(children: .contain)
    }

    /// Avancement d'un anneau dans son cycle (0 à 1), décalé selon son rang.
    private func progress(_ index: Int, at time: TimeInterval) -> Double {
        let shifted = time - Double(index) * config.stagger
        let cycle = shifted.truncatingRemainder(dividingBy: config.duration)
        return (cycle < 0 ? cycle + config.duration : cycle) / config.duration
    }

    /// Anneaux figés, répartis régulièrement dans le cycle.
    private func frozenProgress(_ index: Int) -> Double {
        (Double(index) + 0.5) / Double(config.count)
    }

    private func eased(_ progress: Double) -> Double {
        UnitCurve.easeOut.value(at: progress)
    }

    private func scale(_ progress: Double) -> CGFloat {
        let e = eased(progress)
        return ChimpMotion.Ring.startScale + (ChimpMotion.Ring.endScale - ChimpMotion.Ring.startScale) * e
    }

    private func opacity(_ progress: Double) -> Double {
        let e = eased(progress)
        return ChimpMotion.Ring.startOpacity + (ChimpMotion.Ring.endOpacity - ChimpMotion.Ring.startOpacity) * e
    }
}

/// Vignette de carte au centre des anneaux : couleur de la carte, contour épais, logo.
struct ChimpCardThumbnail: View {
    /// Couleur de la carte attendue ; `nil` : carte pas encore nommée (gris, logo estompé).
    let color: ChimpCardColor?
    /// Petit badge en bas à droite (« NEW ») : dit **quelle** carte poser (retour du 2026-10-01).
    var badge: LocalizedStringKey?

    init(color: ChimpCardColor?, badge: LocalizedStringKey? = nil) {
        self.color = color
        self.badge = badge
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.tab)
        Image(.tileLogo)
            .resizable()
            .scaledToFit()
            .frame(width: ChimpSize.cardThumbnailLogo)
            .opacity(color == nil ? 0.45 : 1)
            .frame(width: ChimpSize.cardThumbnail.width, height: ChimpSize.cardThumbnail.height)
            .cartoonSurface(shape, fill: color?.fill ?? Color(.chimpSurfaceSecondary), border: ChimpBorder.thick, shadow: .card)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(badge)
                        .chimpFont(.labelS)
                        .textCase(.uppercase)
                        .foregroundStyle(.chimpOnAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.chimpAccent)))
                        .overlay { Capsule().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin) }
                        .offset(x: 8, y: 8)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Feuille") {
    ChimpNFCRings {
        ChimpCardThumbnail(color: .jungle)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.chimpBackground))
}

#Preview("Plein écran") {
    ChimpNFCRings(config: ChimpMotion.Ring.fullScreen, size: 260) {
        Image(.tileHead).resizable().scaledToFit().frame(width: 140)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.chimpHeader))
}
