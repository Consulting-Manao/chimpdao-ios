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
    /// Texte à côté du montant (« pocket »).
    var subtitle: LocalizedStringKey?
    /// `true` : `number` est un libellé affiché tel quel, sans « N° » (visite guidée : « CHIMP CARD »).
    var numberIsLabel = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChimpRadius.chimpCard)
        Color.clear
            .aspectRatio(ChimpSize.cardAspectRatio, contentMode: .fit)
            .overlay { content }
            .foregroundStyle(color.ink)
            .background {
                color.fill
                    .overlay { ChimpPattern(tileWidth: ChimpSize.patternTileOnCard, opacity: ChimpOpacity.patternOnCard) }
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.regular) }
            .background {
                shape.fill(Color(.chimpOutline)).offset(x: ChimpShadow.card.x, y: ChimpShadow.card.y)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(numberIsLabel ? Text(verbatim: name) : Text("\(name) card, number \(number)"))
            .accessibilityValue(accessibilityValue)
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
                        Text(verbatim: amount)
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
