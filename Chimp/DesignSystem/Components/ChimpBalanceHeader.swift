import SwiftUI

/// En-tête de solde du Wallet (B1) : tête de Chimpy, accroche, roue dentée, puis le total.
///
/// Il est fait pour défiler avec l'écran : le défilement doit ignorer la zone sûre du haut
/// (`.ignoresSafeArea(edges: .top)`) et passer sa hauteur dans `topSafeArea`. L'en-tête la
/// comble lui-même, pour que son fond et son motif montent sans coupure sous la barre d'état.
/// VoiceOver lit le total d'un bloc (libellé, montant, variation).
struct ChimpBalanceHeader: View {
    /// Prénom (donnée locale, facultative) : « Hey Léo », ou « Hey there » s'il est absent.
    var firstName: String?
    /// Libellé au-dessus du total (« Your whole banana pile »).
    let label: LocalizedStringKey
    /// Total déjà formaté (« $1,485.00 »).
    let total: String
    /// Variation, texte complet (« +$6.20 this week »). Masquée si `nil`.
    var change: LocalizedStringKey?
    /// Roue dentée affichée seulement si une action est fournie.
    var onSettings: (() -> Void)?
    /// Hauteur de la zone sûre du haut de l'écran qui l'affiche (barre d'état).
    var topSafeArea: CGFloat = 0

    @Environment(\.chimpScreenInsets) private var screenInsets

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ChimpSpacing.m) {
                Image(.tileHead)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ChimpSize.headerAvatar)
                    .accessibilityHidden(true)
                greeting
                    .chimpFont(.greeting)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ChimpSpacing.s)
                if let onSettings {
                    ChimpHeaderSettingsButton(action: onSettings)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .chimpFont(.bodyS)
                    .foregroundStyle(.chimpOnHeaderSecondary)
                Text(verbatim: total)
                    .chimpFont(.displayXL)
                    .foregroundStyle(.chimpOnHeaderPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .chimpRollingNumber(total)
                    .padding(.top, ChimpSpacing.s)
                if let change {
                    Text(change)
                        .chimpFont(.bodyS)
                        .foregroundStyle(.chimpOnHeaderAccent)
                }
            }
            .padding(.top, ChimpSpacing.lg)
            .accessibilityElement(children: .combine)
        }
        .padding(ChimpSpacing.header(for: screenInsets, bottom: ChimpSpacing.xxl))
        .padding(.top, topSafeArea)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color(.chimpHeader)
                .overlay { ChimpPattern() }
        }
    }

    private var greeting: Text {
        if let firstName {
            Text("Hey \(firstName)")
        } else {
            Text("Hey there")
        }
    }
}

private struct ChimpBalanceHeaderPreview: View {
    var firstName: String?
    var change: LocalizedStringKey?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                ChimpBalanceHeader(
                    firstName: firstName,
                    label: "Your whole banana pile",
                    total: "$1,485.00",
                    change: change,
                    onSettings: {},
                    topSafeArea: proxy.safeAreaInsets.top
                )
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(.chimpBackground))
    }
}

#Preview("Light") {
    ChimpBalanceHeaderPreview(firstName: "Léo", change: "+$6.20 this week")
}

#Preview("Sans prénom · sombre") {
    ChimpBalanceHeaderPreview()
        .preferredColorScheme(.dark)
}
