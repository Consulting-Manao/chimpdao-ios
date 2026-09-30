import SwiftUI
import UIKit

/// Les trois polices de la maquette.
enum ChimpFontFamily: Equatable {
    /// Police « cartoon » : titres, montants, boutons, onglets, touches.
    case luckiestGuy
    /// Texte courant. Police variable : la graisse (700, 800, 900) est fixée par code.
    case nunito(weight: CGFloat)
    /// Libellés techniques, numéros de carte, montants des lignes d'actifs, XDR.
    case spaceMono(bold: Bool)

    /// Axe de graisse d'une police variable (étiquette OpenType « wght »).
    private static let weightAxis = NSNumber(value: 0x7767_6874)

    var displayName: String {
        switch self {
        case .luckiestGuy: "Luckiest Guy"
        case .nunito(let weight): "Nunito \(Int(weight))"
        case .spaceMono(let bold): bold ? "Space Mono 700" : "Space Mono 400"
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        ChimpFonts.register()
        let font: UIFont?
        switch self {
        case .luckiestGuy:
            font = UIFont(name: "LuckiestGuy-Regular", size: size)
        case .spaceMono(let bold):
            font = UIFont(name: bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
        case .nunito(let weight):
            let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: "Nunito",
                variation: [Self.weightAxis: weight],
            ])
            let nunito = UIFont(descriptor: descriptor, size: size)
            font = nunito.familyName == "Nunito" ? nunito : nil
        }
        guard let font else {
            assertionFailure("Police non chargée : \(displayName)")
            return .systemFont(ofSize: size, weight: .heavy)
        }
        return font
    }
}

/// Échelle typographique extraite de la maquette (tailles en points pour la taille de texte par défaut).
///
/// Chaque style grossit avec la taille de texte choisie par l'utilisateur (Dynamic Type),
/// en suivant la courbe du style système `relativeTo`.
/// Les styles Luckiest Guy sont plafonnés à XXXL pour que les montants ne débordent pas ;
/// le texte courant (Nunito, Space Mono) n'a pas de plafond.
enum ChimpTextStyle: String, CaseIterable, Identifiable {
    // Luckiest Guy
    case celebration   // Swoosh!, Planted!, easter eggs (60–68)
    case amountEntry   // montant en cours de saisie (C2)
    case displayXL     // solde du Wallet
    case amountL       // solde de Main, montant saisi
    case welcomeTitle  // titre de l'accueil (A1 « Your wallet is a card. »)
    case tourTitle     // titres de la visite guidée (A1·1 à A1·4)
    case amountM       // montant d'une carte « tiroir » (Main, B1)
    case displayL      // titres des écrans pleins
    case sheetTitle    // titre d'une feuille
    case key           // touches du pavé numérique
    case brand         // nom de l'app sur l'accueil (A1)
    case stampL        // grand tampon du reçu imprimé (I1.1d)
    case receiptTotal  // TOTAL du reçu imprimé (I1.1d)
    case tabTitle      // titre de l'en-tête d'un onglet (Activity, I1)
    case displayM      // titre de l'en-tête
    case amountS       // montant sur une carte
    case greeting      // accroche de l'en-tête du Wallet (« Hey Léo »)
    case displayS      // titres de section
    case buttonLarge   // bouton principal des écrans d'accueil (« Let's start », « Next »)
    case button        // bouton principal
    case buttonSecondary // bouton secondaire
    case tab           // onglets
    case link          // liens texte (« Cancel », « Skip »)
    case buttonSmall   // petits boutons
    case pill          // pilule « + Add »
    case cardName      // nom sur une Chimp Card
    case tile          // libellés des tuiles d'action
    case stamp         // tampon d'une ligne du ticket de l'Activity (I1)
    case seal          // « CHIMPY-CERTIFIED » au pied du ticket (I1)
    case segment       // segments d'un sélecteur des réglages (« Yellow banana », « Testnet », I2)
    // Nunito
    case lead          // phrase principale de la visite guidée (A1·1 à A1·4)
    case fieldL        // saisie du prénom (A4)
    case fieldM        // saisie du nom de la carte (A5)
    case bodyL         // texte des écrans pleins
    case tourBody      // phrase secondaire de la visite guidée
    case bodyM         // bandeau des écrans « tapez la carte » (A2), texte des cartes-choix (A3)
    case rowTitle      // titre d'une ligne
    case ticketTitle   // titre d'une ligne du ticket (I1)
    case receiptLink   // « Stellar Expert ↗ », « Copy » sur le reçu imprimé (I1.1d)
    case optionTitle   // titre d'une ligne de choix dans une feuille (C3, D1)
    case reviewStep    // étape de la carte « What happens » (C4)
    case body          // texte courant
    case bodyS         // texte de la bulle de Chimpy
    case caption       // méta-infos, sous-titres
    case captionStrong // petites méta-infos appuyées, texte sous le montant d'une carte
    case captionS      // petites méta-infos
    // Space Mono
    case overline      // « HOW CHIMP WORKS · 1 OF 4 » (visite guidée)
    case labelWide     // « STEP 2 OF 3 », étape d'une feuille
    case label         // libellés de section (« READY TO SPEND »)
    case labelS        // « CHIMPY »
    case cardNumber    // « N°0421 » sur une Chimp Card
    case monoValue     // montants des lignes d'actifs
    case mono          // XDR
    case ticketMeta    // « 14:02 · from Jungle » sur le ticket (I1)
    case ticketAmount  // montant d'une ligne du ticket (I1)
    case receiptLabel  // « TO », « FROM » sur le reçu imprimé (I1.1d)
    case receiptValue  // valeur d'une ligne du reçu imprimé (I1.1d)
    case address       // adresse raccourcie dans sa pilule (D1)

    var id: String { rawValue }

    var family: ChimpFontFamily {
        switch self {
        case .celebration, .amountEntry, .displayXL, .amountL, .welcomeTitle, .tourTitle, .amountM, .displayL, .sheetTitle,
             .key, .brand, .displayM, .amountS, .greeting, .displayS, .pill, .buttonLarge, .button, .buttonSecondary, .tab,
             .link, .buttonSmall, .cardName, .tile, .tabTitle, .stamp, .seal, .segment, .stampL, .receiptTotal:
            .luckiestGuy
        case .bodyL, .tourBody, .bodyM, .captionS: .nunito(weight: 700)
        case .body, .bodyS, .caption, .captionStrong, .reviewStep: .nunito(weight: 800)
        case .rowTitle, .optionTitle, .lead, .fieldL, .fieldM, .ticketTitle, .receiptLink: .nunito(weight: 900)
        case .overline, .labelWide, .label, .labelS, .cardNumber, .monoValue, .address, .ticketMeta, .ticketAmount, .receiptLabel, .receiptValue: .spaceMono(bold: true)
        case .mono: .spaceMono(bold: false)
        }
    }

    /// Taille de la maquette, en points.
    var size: CGFloat {
        switch self {
        case .celebration, .amountEntry: 64
        case .displayXL: 50
        case .amountL: 44
        case .welcomeTitle: 40
        case .tourTitle: 34
        case .displayL: 32
        case .sheetTitle: 27
        case .amountM: 26
        case .key, .brand: 24
        case .fieldL: 22
        case .stampL: 34
        case .receiptTotal: 30
        case .tabTitle: 28
        case .displayM: 23
        case .amountS: 21
        case .greeting: 20
        case .displayS, .buttonLarge, .lead, .fieldM: 18
        case .button: 17
        case .cardName: 16
        case .tab, .link, .buttonSecondary: 15
        case .buttonSmall: 14
        case .pill: 13
        case .tile, .stamp: 12
        case .seal, .segment: 11
        case .ticketTitle: 14
        case .receiptLink, .receiptLabel, .receiptValue: 12
        case .ticketAmount: 13
        case .ticketMeta: 11
        case .bodyL, .optionTitle, .reviewStep: 16
        case .rowTitle, .body, .tourBody: 15
        case .bodyS, .bodyM: 14
        case .caption, .address: 13
        case .captionS, .captionStrong, .overline: 12
        case .labelWide, .label: 11
        case .labelS, .cardNumber: 10
        case .monoValue: 14
        case .mono: 12
        }
    }

    /// Style système dont on suit la courbe de grossissement.
    var relativeTo: UIFont.TextStyle {
        switch self {
        case .celebration, .amountEntry, .displayXL, .amountL, .welcomeTitle, .tourTitle: .largeTitle
        case .displayL: .title1
        case .sheetTitle, .key, .brand, .displayM, .amountM, .tabTitle, .stampL, .receiptTotal: .title2
        case .amountS, .greeting: .title3
        case .displayS, .buttonLarge, .button, .lead, .fieldM: .headline
        case .fieldL: .title3
        case .cardName: .callout
        case .bodyL, .optionTitle, .reviewStep: .callout
        case .tab, .link, .buttonSecondary, .buttonSmall, .rowTitle, .body, .tourBody, .bodyS, .bodyM, .monoValue, .ticketTitle: .subheadline
        case .receiptLink, .receiptLabel, .receiptValue: .footnote
        case .caption, .pill, .address, .ticketAmount: .footnote
        case .tile, .captionS, .captionStrong, .overline, .mono, .stamp: .caption1
        case .labelWide, .label, .labelS, .cardNumber, .seal, .segment, .ticketMeta: .caption2
        }
    }

    /// Espacement des lettres de la maquette (px), à la taille de base.
    var tracking: CGFloat {
        switch self {
        case .tab: 0.3
        case .labelWide, .overline: 2
        case .label, .labelS: 1.6
        case .cardNumber: 1.2
        case .receiptLabel: 1
        default: 0
        }
    }

    /// Plafond Dynamic Type : XXXL pour les gros styles Luckiest Guy, aucun pour le reste.
    var maximumDynamicTypeSize: DynamicTypeSize? {
        family == .luckiestGuy ? .xxxLarge : nil
    }

    func pointSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        var effective = dynamicTypeSize
        if let maximum = maximumDynamicTypeSize, effective > maximum {
            effective = maximum
        }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(effective))
        return UIFontMetrics(forTextStyle: relativeTo).scaledValue(for: size, compatibleWith: traits)
    }

    func font(for dynamicTypeSize: DynamicTypeSize) -> Font {
        Font(family.uiFont(size: pointSize(for: dynamicTypeSize)))
    }
}

private struct ChimpFontModifier: ViewModifier {
    let style: ChimpTextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let pointSize = style.pointSize(for: dynamicTypeSize)
        content
            .font(style.font(for: dynamicTypeSize))
            .tracking(style.tracking * pointSize / style.size)
    }
}

extension View {
    /// Applique un style de texte ChimpDAO (police, taille adaptée à Dynamic Type, espacement des lettres).
    func chimpFont(_ style: ChimpTextStyle) -> some View {
        modifier(ChimpFontModifier(style: style))
    }
}
