import SwiftUI

/// Un composant tiers embarqué dans l'app, avec le texte de sa licence (fichier du paquet de l'app).
struct ThirdPartyLicense: Identifiable, Hashable {
    let id: String
    /// « stellar-ios-mac-sdk ».
    let name: String
    /// « Stellar SDK by Soneso ».
    let detail: String
    /// « Apache License 2.0 ».
    let license: String
    /// Nom du fichier texte dans le paquet (sans l'extension `.txt`).
    let file: String

    /// Tout ce que l'app embarque : la seule dépendance (le SDK Stellar), les trois polices et les sons.
    static let all: [ThirdPartyLicense] = [
        ThirdPartyLicense(id: "stellar-sdk", name: "stellar-ios-mac-sdk", detail: "Stellar SDK by Soneso",
                          license: "Apache License 2.0", file: "LICENSE-stellar-ios-mac-sdk"),
        ThirdPartyLicense(id: "luckiest-guy", name: "Luckiest Guy", detail: "Font by Astigmatic",
                          license: "Apache License 2.0", file: "LICENSE-LuckiestGuy"),
        ThirdPartyLicense(id: "nunito", name: "Nunito", detail: "Font by The Nunito Project Authors",
                          license: "SIL Open Font License 1.1", file: "OFL-Nunito"),
        ThirdPartyLicense(id: "space-mono", name: "Space Mono", detail: "Font by Google and Colophon Foundry",
                          license: "SIL Open Font License 1.1", file: "OFL-SpaceMono"),
        // Sons de l'app : taps en bois (Kenney), feuillages, oiseaux et ruisseau (CC0), sons faits pour ChimpDAO.
        ThirdPartyLicense(id: "sounds", name: "Sound effects", detail: "Kenney, qubodup, BigSoundBank, isaiah658, syncopika",
                          license: "Creative Commons Zero (CC0)", file: "LICENSE-Sounds"),
        // Feuillages leaves1 à leaves6 : CC BY 4.0, le crédit à l'auteur est obligatoire.
        ThirdPartyLicense(id: "nature-sounds-pack", name: "Nature Sounds Pack", detail: "Foliage by Antoine Goumain",
                          license: "CC BY 4.0", file: "LICENSE-NatureSoundsPack"),
    ]

    /// Texte de la licence, `nil` si le fichier manque au paquet.
    func text(in bundle: Bundle = .main) -> String? {
        bundle.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

/// « Licenses » (réglages, non dessiné) : les composants tiers de l'app et le texte de leur licence.
struct LicensesView: View {
    let onBack: () -> Void
    @State private var selected: ThirdPartyLicense?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "Licenses", subtitle: "What ChimpDAO is built with", onBack: onBack)
            ScrollView {
                VStack(spacing: ChimpSpacing.listGap) {
                    ForEach(ThirdPartyLicense.all) { item in
                        Button { selected = item } label: {
                            HStack(spacing: ChimpSpacing.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: item.name)
                                        .chimpFont(.rowTitle)
                                        .foregroundStyle(.chimpTextPrimary)
                                    Text(verbatim: "\(item.detail) · \(item.license)")
                                        .chimpFont(.captionS)
                                        .foregroundStyle(.chimpTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(.chimpTextSecondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, ChimpSpacing.m + ChimpBorder.regular)
                            .padding(.horizontal, 15 + ChimpBorder.regular)
                            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.control), fill: Color(.chimpSurface))
                            .contentShape(RoundedRectangle(cornerRadius: ChimpRadius.control))
                        }
                        .buttonStyle(ChimpPressableStyle())
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.vertical, ChimpSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.chimpBackground))
        .navigationDestination(item: $selected) { item in
            LicenseTextView(item: item) { selected = nil }
                .toolbar(.hidden, for: .navigationBar)
        }
        // Easter egg (demande de Barth du 2026-10-02) : un petit ruisseau coule ici, là où personne ne vient. Il continue
        // sur le texte d'une licence, reprend au retour dans l'app, et s'éteint en fondu en quittant la page.
        .onAppear { ChimpAmbience.shared.startStream() }
        .onDisappear { if selected == nil { ChimpAmbience.shared.stopStream() } }
        .onChange(of: selected) { _, new in if new == nil { ChimpAmbience.shared.startStream() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ChimpAmbience.shared.startStream() } else { ChimpAmbience.shared.stopStream() }
        }
    }
}

/// Texte complet d'une licence.
private struct LicenseTextView: View {
    let item: ThirdPartyLicense
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: LocalizedStringKey(stringLiteral: item.name), subtitle: LocalizedStringKey(stringLiteral: item.license), onBack: onBack)
            ScrollView {
                Text(verbatim: item.text() ?? String(localized: "This license text is missing from the app."))
                    .chimpFont(.mono)
                    .foregroundStyle(.chimpTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ChimpSpacing.xxl)
                    .padding(.vertical, ChimpSpacing.xl)
            }
        }
        .background(Color(.chimpBackground))
    }
}

/// « How ChimpDAO works · Replay the tour » (réglages) : la visite de l'onboarding (A1·1 à A1·4), en plein écran.
/// « Skip » ou le bouton de la dernière page la ferment ; rien d'autre ne change.
struct TourReplayView: View {
    let onClose: () -> Void
    @State private var page = 0

    var body: some View {
        TourView(
            page: $page,
            onNext: {
                if page < OnboardingModel.tourPageCount - 1 { page += 1 } else { onClose() }
            },
            onSkip: onClose,
            lastPageTitle: "Got it"
        )
    }
}
