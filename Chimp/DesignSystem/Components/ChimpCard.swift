import SwiftUI

/// Carte bancaire ChimpDAO (« Chimp Card » dans la maquette) : format 1,58:1, couleur choisie
/// par l'utilisateur, logo, numéro, nom et montant.
///
/// La carte garde ses proportions : sa taille de texte est plafonnée à XXXL pour que le contenu
/// tienne dedans. VoiceOver lit toutes ses informations d'un bloc.
struct ChimpCard: View {
    /// Nom donné par l'utilisateur (« Jungle »), donnée locale : affiché tel quel, jamais traduit.
    let name: String
    var color: ChimpCardColor = .jungle
    /// Numéro de la carte, sans « N° » (« 0421 »).
    let number: String
    /// Montant déjà formaté (« $62.50 »).
    var amount: String?
    @Environment(\.chimpHidesAmounts) private var hidesAmounts
    /// Texte à côté du montant (« pocket »).
    var subtitle: LocalizedStringKey?
    /// `true` : `number` est un libellé affiché tel quel, sans « N° » (visite guidée : « CHIMP CARD »).
    var numberIsLabel = false
    /// Clé publique de la carte, **seulement quand son propriétaire a choisi d'afficher le dessin de son NFT**
    /// (« Rename & colour »). Le dessin remplace alors toute la face : dessin seul, sans le nom ni le numéro par-dessus
    /// (décision de Barth du 2026-11-16). Sans clé, ou si le dessin n'est pas encore arrivé, la carte garde sa couleur.
    var cardKey: String?

    @Environment(\.chimpCardArt) private var cardArt

    /// Le dessin imprimé de cette carte, s'il y en a un.
    private var art: CardArt? { cardKey.flatMap { cardArt($0) } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.chimpCard)
        let art = art
        return Color.clear
            .aspectRatio(ChimpSize.cardAspectRatio, contentMode: .fit)
            .overlay { if art == nil { content } }
            .foregroundStyle(color.ink)
            .background {
                Group {
                    if let art {
                        // Le dessin a les mêmes proportions que la carte (vérifié à la lecture) : il la remplit sans être coupé.
                        Image(uiImage: art.image).resizable().scaledToFill()
                    } else {
                        color.fill
                            .overlay { ChimpPattern(tileWidth: ChimpSize.patternTileOnCard, opacity: ChimpOpacity.patternOnCard) }
                    }
                }
                .clipShape(shape)
            }
            .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .background {
                shape.fill(Color(.chimpOutline)).offset(x: ChimpShadow.card.x, y: ChimpShadow.card.y)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(art))
            .accessibilityValue(accessibilityValue)
    }

    /// VoiceOver dit toujours le nom et le numéro, même quand le dessin les remplace à l'écran, et nomme le dessin.
    private func accessibilityLabel(_ art: CardArt?) -> Text {
        let base = numberIsLabel ? Text(verbatim: name) : Text("\(name) card, number \(number)")
        guard let design = art?.design else { return base }
        return base + Text(verbatim: ", ") + Text("\(design) design")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(.tileLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30)
                Spacer(minLength: ChimpSpacing.s)
                Text(verbatim: numberIsLabel ? number : "N°\(number)")
                    .chimpFont(.cardNumber)
            }
            Spacer(minLength: 0)
            Text(verbatim: name)
                .chimpFont(.cardName)
                .lineLimit(1)
            if amount != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.xs) {
                    if let amount {
                        Text(verbatim: ChimpPrivacy.amount(amount, hidden: hidesAmounts))
                            .chimpFont(.amountS)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .chimpFont(.captionStrong)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        // La maquette compte le rembourrage à l'intérieur du contour (border-box).
        .padding(.vertical, 13 + ChimpBorder.regular)
        .padding(.horizontal, ChimpSpacing.ml + ChimpBorder.regular)
    }

    private var accessibilityValue: Text {
        switch (amount, subtitle) {
        case let (amount?, subtitle?): Text(verbatim: amount + ", ") + Text(subtitle)
        case let (amount?, nil): Text(verbatim: amount)
        case let (nil, subtitle?): Text(subtitle)
        case (nil, nil): Text(verbatim: "")
        }
    }
}

private struct ChimpCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ChimpSpacing.xl) {
                ChimpCard(name: "Jungle", color: .jungle, number: "0421", amount: "$62.50", subtitle: "on card")
                HStack(spacing: ChimpSpacing.m) {
                    ChimpCard(name: "Banana", color: .banana, number: "0588", amount: "$12.00")
                    ChimpCard(name: "Leaf", color: .leaf, number: "0913")
                }
                ChimpCard(name: "Pinky", color: .pink, number: "0077", amount: "$4.20", subtitle: "on card")
            }
            .padding(ChimpSpacing.screenMargin)
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpCardPreview()
}

#Preview("Dark") {
    ChimpCardPreview()
        .preferredColorScheme(.dark)
}
