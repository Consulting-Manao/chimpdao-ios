import SwiftUI

/// Ce que montre le bandeau d'une page de tiroir (maquette « Chimp Main & Card v2 », B1, 2026-11-12) : Chimpy dans son
/// hamac sous un bananier pour Main, Chimpy et la carte pour le wallet d'une carte.
enum ChimpDrawerScene: Equatable {
    case main
    case card(name: String, color: ChimpCardColor, number: String)
    /// La carte n'est pas encore lue : le fond de l'en-tête, sans scène.
    case blank

    /// Fond du bandeau : vert pour Main, sinon celui de la couleur de la carte (Jungle a un brun plus clair que la carte,
    /// pour que la carte se détache).
    var banner: Color {
        switch self {
        case .main: Color(.chimpCardLeaf)
        case .card(_, let color, _): color.sceneBanner
        case .blank: Color(.chimpHeader)
        }
    }
}

extension ChimpCardColor {
    /// Fond du bandeau B1 d'une carte de cette couleur.
    var sceneBanner: Color {
        switch self {
        case .jungle: Color(.chimpBannerJungle)
        case .banana, .leaf, .pink: fill
        }
    }

    /// Sticker de Chimpy dans le bandeau B1, choisi par la couleur (décision de Barth du 2026-11-12) : explorer et wave
    /// viennent de la maquette (Jungle, Banana) ; plant (Leaf) et hearts (Pink) sont un choix de l'app.
    var sceneSticker: ImageResource {
        switch self {
        case .jungle: .stickerExplorer
        case .banana: .stickerWave
        case .leaf: .stickerPlant
        case .pink: .stickerHearts
        }
    }
}

/// Bandeau illustré en haut d'une page de tiroir (B1) : fond, motif, scène, retour et titre. Il passe sous la barre
/// d'état ; le panneau du total (`ChimpSplitPanel`) se pose sur ses 56 derniers points.
///
/// Positions de la maquette (téléphone de 874 pt, barre d'état de 54 pt), comptées ici depuis le haut de la zone sûre.
struct ChimpDrawerBanner: View {
    let scene: ChimpDrawerScene
    /// « Main », « Jungle card ».
    let title: Text
    let onBack: () -> Void

    /// Hauteur sous la zone sûre (290 pt dans la maquette, moins sa barre d'état de 54 pt).
    static let height: CGFloat = 236
    /// Ce que le panneau du total recouvre.
    static let panelOverlap: CGFloat = 56

    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        ZStack(alignment: .topLeading) {
            art
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, screenInsets.top)
                .accessibilityHidden(true)
            HStack(spacing: ChimpSpacing.m) {
                ChimpHeaderBackButton(action: onBack)
                title
                    .chimpFont(.greeting)
                    .foregroundStyle(Color(.chimpOnHeaderPrimary))
                    .shadow(color: Color(.chimpOutline), radius: 0, x: 2, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, screenInsets.top + ChimpSpacing.xxs)
            .padding(.horizontal, ChimpSpacing.screenMargin)
        }
        .frame(height: screenInsets.top + Self.height)
        .frame(maxWidth: .infinity)
        .background {
            scene.banner.overlay { ChimpPattern(opacity: 0.14) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.chimpOutline)).frame(height: ChimpBorder.regular)
        }
        .clipped()
    }

    @ViewBuilder
    private var art: some View {
        switch scene {
        case .main:
            ZStack(alignment: .topLeading) {
                Image(.bananaTree)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 250)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 30, y: 14)
                Image(.chimpyHamac)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240)
                    .chimpSway(duration: 4, angle: .degrees(3))
                    .offset(x: -6, y: 58)
            }
        case .card(let name, let color, let number):
            ZStack(alignment: .topLeading) {
                Image(color.sceneSticker)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 190)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 6)
                    .offset(y: 34)
                ChimpCard(name: name, color: color, number: number)
                    .frame(width: 200)
                    .rotationEffect(.degrees(-8))
                    .chimpBob(duration: 4)
                    .offset(x: 22, y: 68)
            }
        case .blank:
            EmptyView()
        }
    }
}

/// Le panneau blanc du total (B1) : ce que c'est (« MAIN · SHARED »), le total, la barre « ready » (jaune) et « growing »
/// (vert), leurs montants, puis l'adresse copiable (ajout de l'app, décision de Barth du 2026-11-12).
struct ChimpSplitPanel: View {
    /// « MAIN · SHARED », « N°0421 · ONLY THIS CARD SIGNS » (déjà en majuscules).
    let kind: String
    let total: String
    /// « $820 ».
    let ready: String
    /// « $500 » ; `nil` : rien ne pousse (« nothing growing yet »).
    let growing: String?
    /// Parts de la barre ; toutes deux à 0 : la barre reste vide (tiroir vide).
    let readyWeight: Double
    let growingWeight: Double
    var address: String?
    var isCopied = false
    var onCopy: () -> Void = {}

    @Environment(\.chimpHidesAmounts) private var hidesAmounts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: kind)
                .chimpFont(.label)
                .foregroundStyle(.chimpTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: ChimpPrivacy.amount(total, hidden: hidesAmounts))
                .chimpFont(.amountL)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, ChimpSpacing.s)
            ChimpSplitBar(readyWeight: readyWeight, growingWeight: growingWeight)
                .padding(.top, ChimpSpacing.ml)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.s) {
                Text("\(ChimpPrivacy.amount(ready, hidden: hidesAmounts)) ready")
                    .foregroundStyle(.chimpTextSecondary)
                Spacer(minLength: 0)
                Group {
                    if let growing {
                        Text("\(ChimpPrivacy.amount(growing, hidden: hidesAmounts)) growing")
                    } else {
                        Text("nothing growing yet")
                    }
                }
                .foregroundStyle(.chimpPositive)
            }
            .chimpFont(.captionStrong)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 7)
            if let address {
                ChimpAddressPill(address: address, isCopied: isCopied, action: onCopy)
                    .padding(.top, ChimpSpacing.m)
            }
        }
        .padding(.vertical, ChimpSpacing.l + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.lg + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: 24), fill: Color(.chimpSurface), shadow: ChimpShadow.qrCard)
    }
}

/// Barre en deux parts (B1) : « ready » en jaune, « growing » en vert, séparées par un trait ; fond `chimpSurfaceSecondary`.
struct ChimpSplitBar: View {
    let readyWeight: Double
    let growingWeight: Double

    var body: some View {
        let total = readyWeight + growingWeight
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if total > 0 {
                    let readyWidth = proxy.size.width * readyWeight / total
                    Color(.chimpAccent)
                        .frame(width: readyWidth)
                        .overlay(alignment: .trailing) {
                            if readyWeight > 0, growingWeight > 0 {
                                Rectangle().fill(Color(.chimpOutline)).frame(width: 2.5)
                            }
                        }
                    Color(.chimpCardLeaf)
                }
            }
        }
        .frame(height: 12)
        .background(Color(.chimpSurfaceSecondary))
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(Color(.chimpOutline), lineWidth: 2.5) }
        .animation(.snappy(duration: 0.4), value: readyWeight)
        .animation(.snappy(duration: 0.4), value: growingWeight)
    }
}

/// Titre d'une liste de la page d'un tiroir (N1b) : « Ready to spend » à gauche, son montant à droite.
struct ChimpDrawerListTitle: View {
    let title: LocalizedStringKey
    var amount: String?
    var tint = Color(.chimpTextPrimary)

    @Environment(\.chimpHidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .chimpFont(.displayS)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: ChimpSpacing.s)
            if let amount {
                Text(verbatim: ChimpPrivacy.amount(amount, hidden: hidesAmounts))
                    .chimpFont(.monoValue)
            }
        }
        .foregroundStyle(tint)
    }
}

/// Une ligne d'avoir (N1b) : icône de 38 pt, nom, détail, montant en Space Mono. Fond `chimpSurface`, contour 3, rayon 18.
struct ChimpHoldingRow<Icon: View>: View {
    let name: String
    let detail: String
    var detailColor = Color(.chimpTextSecondary)
    let amount: String
    @ViewBuilder let icon: () -> Icon

    @Environment(\.chimpHidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(spacing: ChimpSpacing.m) {
            icon()
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name)
                    .chimpFont(.rowTitle)
                    .foregroundStyle(.chimpTextPrimary)
                Text(verbatim: ChimpPrivacy.amount(detail, hidden: hidesAmounts))
                    .chimpFont(.captionStrong)
                    .foregroundStyle(detailColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: ChimpPrivacy.amount(amount, hidden: hidesAmounts))
                .chimpFont(.monoValue)
                .foregroundStyle(.chimpTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 11 + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .frame(maxWidth: .infinity, minHeight: ChimpSize.minimumTouchTarget)
        .cartoonSurface(RoundedRectangle(cornerRadius: 18), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }
}

private struct ChimpSwayModifier: ViewModifier {
    let duration: Double
    let angle: Angle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Même horloge que `chimpBob` (arrêtée hors de l'écran, rendu seul par `visualEffect`).
            TimelineView(.animation(paused: !isOnScreen)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
                let half = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2
                let eased = half * half * (3 - 2 * half)
                content.visualEffect { effect, _ in
                    effect.rotationEffect(.degrees(angle.degrees * (2 * eased - 1)), anchor: .top)
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
        }
    }
}

extension View {
    /// Balancement du hamac (animation « sway » de B1) : de −angle à +angle autour du haut, aller-retour en `duration`.
    /// Immobile si « Réduire les animations » est activé.
    func chimpSway(duration: Double, angle: Angle) -> some View {
        modifier(ChimpSwayModifier(duration: duration, angle: angle))
    }
}

#Preview("Main") {
    VStack(spacing: 0) {
        ChimpDrawerBanner(scene: .main, title: Text("Main")) {}
        ChimpSplitPanel(
            kind: "MAIN · SHARED", total: "$1,320.00", ready: "$820", growing: "$500", readyWeight: 820, growingWeight: 500,
            address: "CAIO2SJ6…VOX2QF"
        )
        .padding(.horizontal, ChimpSpacing.screenMargin)
        .padding(.top, -ChimpDrawerBanner.panelOverlap)
        Spacer()
    }
    .background(Color(.chimpBackground))
    .ignoresSafeArea(edges: .top)
}

#Preview("Card") {
    VStack(spacing: 0) {
        ChimpDrawerBanner(scene: .card(name: "Banana", color: .banana, number: "0688"), title: Text("Banana card")) {}
        ChimpSplitPanel(
            kind: "N°0688 · ONLY THIS CARD SIGNS", total: "$62.50", ready: "$62.50", growing: nil, readyWeight: 1, growingWeight: 0
        )
        .padding(.horizontal, ChimpSpacing.screenMargin)
        .padding(.top, -ChimpDrawerBanner.panelOverlap)
        ChimpHoldingRow(name: "Stellar", detail: "250 XLM", amount: "$62.50") { ChimpAssetIcon(glyph: .xlm, size: 38) }
            .padding(ChimpSpacing.screenMargin)
        Spacer()
    }
    .background(Color(.chimpBackground))
    .ignoresSafeArea(edges: .top)
}
