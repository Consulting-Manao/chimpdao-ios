#if DESIGN_CATALOG
import SwiftUI

/// En-tête montré en vraie position, en haut de l'écran (la barre de navigation du catalogue est masquée).
struct CatalogHeaderPage: View {
    let settings: CatalogSettings
    @Environment(\.dismiss) private var dismiss
    @State private var variant = Variant.steps

    enum Variant: String, CaseIterable, Identifiable {
        case steps, subtitleAndSettings, backOnly, longTitle
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .steps: "Steps"
            case .subtitleAndSettings: "Subtitle + settings"
            case .backOnly: "Back only"
            case .longTitle: "Long title"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                    CatalogSectionTitle("Variant")
                    ForEach(Variant.allCases) { option in
                        ChimpButton(
                            option.title,
                            kind: option == variant ? .primary : .secondary,
                            size: .compact
                        ) {
                            variant = option
                        }
                    }
                    Text("The back button closes this page. Back: 40 pt visual, 44 pt touch area.")
                        .chimpFont(.body)
                        .foregroundStyle(.chimpTextSecondary)
                    ChimpButton("Close", kind: .link) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
                .padding(ChimpSpacing.screenMargin)
            }
        }
        .foregroundStyle(.chimpTextPrimary)
        .background(Color(.chimpBackground))
        .toolbar(.hidden, for: .navigationBar)
        .catalogOverrides(settings)
    }

    @ViewBuilder
    private var header: some View {
        switch variant {
        case .steps:
            ChimpHeader(title: "How much, from where", step: 2, steps: 3, onBack: { dismiss() })
        case .subtitleAndSettings:
            ChimpHeader(title: "Léo's account", subtitle: "2 cards · Main + 2 wallets", onSettings: {})
        case .backOnly:
            ChimpHeader(title: "Send", onBack: { dismiss() })
        case .longTitle:
            ChimpHeader(
                title: "Grow more bananas with a very long title",
                subtitle: "Pick where your bananas grow",
                step: 1,
                steps: 3,
                onBack: { dismiss() },
                onSettings: {}
            )
        }
    }
}

#Preview {
    NavigationStack {
        CatalogHeaderPage(settings: CatalogSettings())
    }
}
#endif
