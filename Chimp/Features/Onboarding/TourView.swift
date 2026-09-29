import SwiftUI

/// A1·1 à A1·4 · How ChimpDAO works : visite guidée du premier lancement (« Skip » sur chaque page).
/// Termes du glossaire (DESIGN_NOTES §1.2) : « Main account » au lieu de « Main wallet », « Jungle's wallet »
/// au lieu de « Jungle wallet ». Les pages se changent avec « Next » ou d'un glissement.
struct TourView: View {
    @Binding var page: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    private let count = OnboardingModel.tourPageCount

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How ChimpDAO works · \(page + 1) of \(count)")
                    .chimpFont(.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(.chimpTextSecondary)
                Spacer()
                Button(action: onSkip) {
                    Text("Skip")
                        .chimpFont(.body)
                        .foregroundStyle(.chimpTextSecondary)
                        // Zone de toucher de 44 pt sans agrandir la ligne (la maquette la veut basse).
                        .padding(ChimpSpacing.m)
                        .contentShape(Rectangle())
                        .padding(-ChimpSpacing.m)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ChimpSpacing.xxxl)
            .padding(.top, ChimpSpacing.sm)

            TabView(selection: $page) {
                ForEach(0..<count, id: \.self) { index in
                    TourPage(index: index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: ChimpSpacing.l) {
                ChimpPageDots(count: count, current: page)
                ChimpButton(page == count - 1 ? "Tap my card" : "Next", size: .large, action: onNext)
            }
            .padding(.top, ChimpSpacing.lg)
            .padding(.horizontal, ChimpSpacing.xxxl)
            .padding(.bottom, ChimpSpacing.xs)
        }
        .background(Color(.chimpBackground))
    }
}

/// Une page : titre, illustration, deux phrases, bulle de Chimpy. Défile seulement si elle ne tient pas.
private struct TourPage: View {
    let index: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// En dessous de cette hauteur (iPhone SE), la page se resserre : sans les hauteurs fixes de la maquette,
    /// illustration réduite.
    private static let compactHeight: CGFloat = 560

    var body: some View {
        GeometryReader { proxy in
            if dynamicTypeSize.isAccessibilitySize {
                // Grandes tailles de texte : la page défile.
                ScrollView { content(compact: true) }.scrollIndicators(.hidden)
            } else {
                content(compact: proxy.size.height < Self.compactHeight)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .chimpFont(.tourTitle)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: compact ? nil : 84, alignment: .topLeading)
                .padding(.top, compact ? ChimpSpacing.xs : ChimpSpacing.m)
                .accessibilityAddTraits(.isHeader)

            ChimpScaled(scale: compact ? compactScale : 1) { illustration }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(lead)
                    .chimpFont(.lead)
                    .foregroundStyle(.chimpTextPrimary)
                Text(detail)
                    .chimpFont(.tourBody)
                    .foregroundStyle(.chimpTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: compact ? nil : 118, alignment: .topLeading)
            .padding(.top, compact ? ChimpSpacing.s : 0)

            ChimpySays(text: chimpy, pose: pose)
                .padding(.top, ChimpSpacing.xs)
        }
        .padding(.horizontal, ChimpSpacing.xxxl)
        // La vue à pages rogne le bas de son contenu : on garde la bulle (et son ombre) à l'écart du bord.
        .padding(.bottom, ChimpSpacing.s)
    }

    /// Réduction de l'illustration sur petit écran : la page 4 (« Which card can pay? ») est la plus haute.
    private var compactScale: CGFloat {
        index == 3 ? 0.6 : 0.78
    }

    private var title: LocalizedStringKey {
        switch index {
        case 0: "Your card\nis the key"
        case 1: "One account,\none or more cards"
        case 2: "A Main account,\nplus one per card"
        default: "Tap your card\nto move money"
        }
    }

    private var lead: LocalizedStringKey {
        switch index {
        case 0: "Your money lives on the card, not on your phone."
        case 1: "Your account starts with one card. Add more whenever you want."
        case 2: "Main is shared: any of your cards can use it."
        default: "Every transaction needs your PIN and a tap of the card."
        }
    }

    private var detail: LocalizedStringKey {
        switch index {
        case 0: "Lose your phone and nothing is lost. No card, no payment."
        case 1: "Every card is equal. A spare at home, one for a friend, one as a gift."
        case 2: "Each card also has its own wallet only it can spend. Move money between them whenever you like."
        default: "From Main, any of your cards works. From a card's own wallet, only that card. Just looking never needs a card."
        }
    }

    private var chimpy: LocalizedStringKey {
        switch index {
        case 0: "Think of me as the guide. The card is the boss."
        case 1: "No boss card here. They all count the same."
        case 2: "Keep the big money in Main, pocket money on the cards."
        default: "That's it. Ready when you are!"
        }
    }

    private var pose: ChimpyPose {
        switch index {
        case 0: .head
        case 1: .banana
        case 2: .crawl
        default: .stand
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch index {
        case 0:
            ChimpCard(name: String(localized: "Your card"), color: .jungle, number: String(localized: "CHIMP CARD"), numberIsLabel: true)
                .frame(width: 240)
                .rotationEffect(.degrees(-9))
                .chimpBob(duration: 3.4)
                .accessibilityHidden(true)
        case 1:
            TourAccountPanel()
        case 2:
            TourDrawersPanel()
        default:
            TourWhoPaysPanel()
        }
    }
}

// MARK: Illustrations

/// Carte « Léo's account » avec deux cartes et une place libre (A1·2).
private struct TourAccountPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            HStack(spacing: ChimpSpacing.s) {
                Image(.tileHead).resizable().scaledToFit().frame(width: 26).accessibilityHidden(true)
                Text("Léo's account").chimpFont(.button)
            }
            HStack(spacing: 9) {
                TourMiniCard(color: .jungle, name: "Jungle", showsLogo: true)
                TourMiniCard(color: .banana, name: "Banana", showsLogo: true)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.chimpTextSecondary), style: StrokeStyle(lineWidth: ChimpBorder.regular, dash: [6, 4]))
                    .aspectRatio(ChimpSize.cardAspectRatio, contentMode: .fit)
                    .overlay { Text(verbatim: "+").chimpFont(.greeting).foregroundStyle(.chimpTextSecondary) }
                    .frame(maxWidth: .infinity)
            }
            Text("1 card to start · add as many as you like")
                .chimpFont(.captionStrong)
                .foregroundStyle(.chimpTextSecondary)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.chimpTextPrimary)
        .modifier(TourPanelStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Main account partagé et un wallet par carte (A1·3).
private struct TourDrawersPanel: View {
    var body: some View {
        VStack(spacing: ChimpSpacing.s) {
            VStack(spacing: 2) {
                Text("Main account").chimpFont(.button)
                Text("shared by every card").chimpFont(.captionStrong)
            }
            .foregroundStyle(.chimpOnAccent)
            .padding(ChimpSpacing.sm + ChimpBorder.regular)
            .frame(maxWidth: .infinity)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.tab), fill: Color(.chimpAccent))

            HStack(spacing: ChimpSpacing.s) {
                Text(verbatim: "⇅").chimpFont(.displayS)
                Text("move money anytime").chimpFont(.captionStrong)
                Text(verbatim: "⇅").chimpFont(.displayS)
            }
            .foregroundStyle(.chimpTextSecondary)
            .accessibilityElement(children: .combine)

            HStack(spacing: 9) {
                drawer(ChimpCardColor.jungle, name: "Jungle's wallet")
                drawer(ChimpCardColor.leaf, name: "Leaf's wallet")
            }
        }
        .modifier(TourPanelStyle(padding: ChimpSpacing.ml))
        .accessibilityElement(children: .combine)
    }

    private func drawer(_ color: ChimpCardColor, name: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(name).chimpFont(.buttonSmall)
            Text("only this card").chimpFont(.captionStrong)
        }
        .foregroundStyle(color.ink)
        .padding(.vertical, 9 + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.xs)
        .frame(maxWidth: .infinity)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.tab - 2), fill: color.fill)
    }
}

/// « PIN + tap » et « Which card can pay? » (A1·4).
private struct TourWhoPaysPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.sm) {
            HStack(spacing: ChimpSpacing.m) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(.chimpCardJungle))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                    .frame(width: 46, height: 30)
                    .accessibilityHidden(true)
                Text("PIN + tap\nfor every transaction").chimpFont(.button)
            }
            .foregroundStyle(.chimpOnAccent)
            .padding(.vertical, ChimpSpacing.m)
            .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: 18), fill: Color(.chimpAccent), shadow: .card)

            Text("Which card can pay?")
                .chimpFont(.label)
                .textCase(.uppercase)
                .foregroundStyle(.chimpTextSecondary)

            payers(title: "Money in Main", detail: "shared, any card pays", allowed: [true, true, true])
            payers(title: "Money on Jungle", detail: "only Jungle pays", allowed: [true, false, false])
        }
        .accessibilityElement(children: .combine)
    }

    private func payers(title: LocalizedStringKey, detail: LocalizedStringKey, allowed: [Bool]) -> some View {
        let cards: [(ChimpCardColor, String)] = [(.jungle, "Jungle"), (.banana, "Banana"), (.leaf, "Leaf")]
        return VStack(alignment: .leading, spacing: ChimpSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.s) {
                Text(title).chimpFont(.button)
                Text(detail).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            }
            HStack {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(card.0.fill)
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
                            .frame(width: 52, height: 32)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: allowed[index] ? "checkmark" : "xmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(allowed[index] ? Color(.chimpCardLeaf) : Color(.chimpNegative)))
                                    .overlay(Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular))
                                    .offset(x: 10, y: -10)
                            }
                        Text(verbatim: card.1).chimpFont(.captionStrong)
                    }
                    .opacity(allowed[index] ? 1 : ChimpOpacity.disabled)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, ChimpSpacing.xxs)
            .accessibilityHidden(true)
        }
        .foregroundStyle(.chimpTextPrimary)
        .padding(.vertical, ChimpSpacing.sm)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: 18), fill: Color(.chimpSurface))
    }
}

/// Petite carte d'illustration : couleur, logo, nom (A1·2).
private struct TourMiniCard: View {
    let color: ChimpCardColor
    let name: String
    var showsLogo = false

    var body: some View {
        VStack(alignment: .leading) {
            if showsLogo {
                Image(.tileLogo).resizable().scaledToFit().frame(width: 16)
            }
            Spacer(minLength: 0)
            Text(verbatim: name).chimpFont(.tile).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(color.ink)
        .padding(.vertical, ChimpSpacing.xs + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.s + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(ChimpSize.cardAspectRatio, contentMode: .fit)
        .cartoonSurface(RoundedRectangle(cornerRadius: 10), fill: color.fill)
    }
}

/// Encadré blanc des illustrations (contour, ombre dure, rayon 22).
private struct TourPanelStyle: ViewModifier {
    var padding: CGFloat = ChimpSpacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding + ChimpBorder.regular)
            .frame(maxWidth: .infinity)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
    }
}

/// Réduit une illustration en réduisant aussi la place qu'elle prend (contrairement à `scaleEffect` seul).
private struct ChimpScaled<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScaledLayout(scale: scale) {
            content.scaleEffect(scale)
        }
    }

    private struct ScaledLayout: Layout {
        let scale: CGFloat

        // L'illustration garde sa hauteur naturelle à la largeur agrandie (jamais écrasée), puis elle est réduite.
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let child = subviews.first else { return .zero }
            let size = child.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / scale }, height: nil))
            return CGSize(width: size.width * scale, height: size.height * scale)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: bounds.width / scale, height: nil)
            )
        }
    }
}

#Preview {
    @Previewable @State var page = 0
    TourView(page: $page, onNext: { page = min(page + 1, 3) }, onSkip: {})
}
