#if DESIGN_CATALOG
import Observation
import SwiftUI

/// Catalogue du design system : affiche tous les jetons et composants.
/// Compilé uniquement en Debug et Testing (drapeau `DESIGN_CATALOG`), jamais en Release.
struct DesignSystemCatalogView: View {
    @State private var settings = CatalogSettings()
    /// Session de l'app, pour « oublier le compte » et refaire l'onboarding.
    @Environment(AppSession.self) private var session: AppSession?
    @State private var isConfirmingForget = false
    @State private var forgetError: String?
    #if DEBUG
    @State private var swapProtocol = SwapProtocolOverride.current
    #endif

    var body: some View {
        CatalogPage("Design System", settings: settings, scrolls: false) {
            List {
                #if CHIMP_ADMIN && !CHIMP_ADMIN_APP
                // Dans Chimp Admin, ces outils sont dans l'onglet Tools. Textes du mode admin hors String Catalog (voir `AdminView`).
                Section {
                    link(untranslated("Admin mode (testnet)"), systemImage: "wrench.and.screwdriver.fill") { AdminView() }
                    if let session, session.hasAccount {
                        Button(role: .destructive) {
                            isConfirmingForget = true
                        } label: {
                            Label {
                                Text(verbatim: "Forget this phone's account (onboarding again)").chimpFont(.rowTitle)
                            } icon: {
                                Image(systemName: "arrow.counterclockwise").fontWeight(.heavy)
                            }
                            .foregroundStyle(.chimpNegative)
                        }
                    }
                    if let forgetError {
                        Text(verbatim: forgetError).chimpFont(.caption).foregroundStyle(.chimpNegative)
                    }
                    #if DEBUG
                    // Forcer un protocole d'échange (preuve d'un swap Soroswap sur testnet, où Aquarius gagne toujours).
                    Picker(selection: $swapProtocol) {
                        ForEach(SwapProtocolOverride.allCases) { option in
                            Text(verbatim: option.title).tag(option)
                        }
                    } label: {
                        Label {
                            Text(verbatim: "Swap protocol").chimpFont(.rowTitle)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right").fontWeight(.heavy)
                        }
                    }
                    .onChange(of: swapProtocol) { _, new in SwapProtocolOverride.current = new }
                    #endif
                } header: {
                    Text(verbatim: "Admin")
                }
                .listRowBackground(Color(.chimpSurface))
                #endif

                Section("Tokens") {
                    link("Colors", systemImage: "paintpalette.fill") { CatalogColorsPage(settings: settings) }
                    link("Contrast", systemImage: "circle.lefthalf.filled") { CatalogContrastPage(settings: settings) }
                    link("Typography", systemImage: "textformat") { CatalogTypographyPage(settings: settings) }
                    link("Spacing, radii, borders, shadows", systemImage: "square.dashed") { CatalogLayoutPage(settings: settings) }
                    link("Motion", systemImage: "wind") { CatalogMotionPage(settings: settings) }
                    link("Images", systemImage: "photo.fill") { CatalogImagesPage(settings: settings) }
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Components") {
                    link("Buttons", systemImage: "button.horizontal.fill") { CatalogButtonsPage(settings: settings) }
                    link("Header", systemImage: "rectangle.topthird.inset.filled") { CatalogHeaderPage(settings: settings) }
                    link("Tab bar", systemImage: "dock.rectangle") { CatalogTabBarPage(settings: settings) }
                    link("Card", systemImage: "creditcard.fill") { CatalogCardPage(settings: settings) }
                    link("Keypad and PIN", systemImage: "circle.grid.3x3.fill") { CatalogPinPage(settings: settings) }
                    link("Chimpy and motion", systemImage: "bubble.left.fill") { CatalogChimpyPage(settings: settings) }
                    link("Sheets", systemImage: "rectangle.bottomhalf.inset.filled") { CatalogSheetsPage(settings: settings) }
                    link("Wallet parts", systemImage: "square.grid.2x2.fill") { CatalogWalletPartsPage(settings: settings) }
                    link("Receive parts", systemImage: "qrcode") { CatalogReceivePartsPage(settings: settings) }
                    link("Send parts", systemImage: "paperplane.fill") { CatalogSendPartsPage(settings: settings) }
                }
                .listRowBackground(Color(.chimpSurface))

                Section("Screens") {
                    link("Onboarding", systemImage: "hand.wave.fill") { OnboardingCatalogPage(settings: settings) }
                    link("Wallet states", systemImage: "wallet.pass.fill") { WalletStatesCatalogPage(settings: settings) }
                    link("Receive states", systemImage: "qrcode") { ReceiveStatesCatalogPage(settings: settings) }
                    link("Send", systemImage: "paperplane.fill") { SendCatalogPage(settings: settings) }
                    link("Swap", systemImage: "arrow.left.arrow.right") { SwapCatalogPage(settings: settings) }
                    link("Grow", systemImage: "leaf.fill") { GrowCatalogPage(settings: settings) }
                    link("Activity states", systemImage: "list.bullet.rectangle.portrait.fill") { ActivityStatesCatalogPage(settings: settings) }
                }
                .listRowBackground(Color(.chimpSurface))
            }
            .scrollContentBackground(.hidden)
        }
        #if CHIMP_ADMIN
        .confirmationDialog(
            Text(verbatim: "Forget this phone's account?"),
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                do {
                    try session?.forgetAccount()
                } catch {
                    forgetError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                }
            } label: {
                Text(verbatim: "Forget and start onboarding again")
            }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "Only this phone forgets: the account, its cards and the money stay on testnet. Tapping a card of the account opens it again.")
        }
        #endif
    }

    private func link(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> some View
    ) -> some View {
        NavigationLink(destination: destination) {
            CatalogLinkLabel(title: title, systemImage: systemImage)
        }
    }
}

/// Ligne du sommaire. Lit la taille de texte à l'intérieur de la page, pour suivre aussi celle forcée par le catalogue.
private struct CatalogLinkLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Label {
            Text(title).chimpFont(.rowTitle)
        } icon: {
            Image(systemName: systemImage).fontWeight(.heavy)
        }
        .foregroundStyle(.chimpTextPrimary)
        // Aux tailles d'accessibilité, l'icône prendrait trop de place : on garde le texte seul.
        .labelStyle(dynamicTypeSize.isAccessibilitySize ? AnyLabelStyle(.titleOnly) : AnyLabelStyle(.titleAndIcon))
    }
}

/// Permet de choisir un style de libellé à l'exécution.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// Réglages du catalogue, partagés par toutes ses pages : thème et taille de texte forcés.
@Observable
final class CatalogSettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case system, small, standard, xxxLarge, accessibility1, accessibility3, accessibility5
        var id: String { rawValue }

        var dynamicTypeSize: DynamicTypeSize? {
            switch self {
            case .system: nil
            case .small: .small
            case .standard: .large
            case .xxxLarge: .xxxLarge
            case .accessibility1: .accessibility1
            case .accessibility3: .accessibility3
            case .accessibility5: .accessibility5
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .system: "System"
            case .small: "Small"
            case .standard: "Default"
            case .xxxLarge: "XXXL"
            case .accessibility1: "Accessibility 1"
            case .accessibility3: "Accessibility 3"
            case .accessibility5: "Accessibility 5"
            }
        }
    }

    // Mémorisés entre deux lancements. On peut aussi les fixer au lancement :
    // `-catalogAppearance dark -catalogTextSize accessibility3`.
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey) }
    }

    private static let appearanceKey = "catalogAppearance"
    private static let textSizeKey = "catalogTextSize"

    init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        textSize = defaults.string(forKey: Self.textSizeKey).flatMap(TextSize.init(rawValue:)) ?? .system
    }
}

/// Cadre commun des pages du catalogue : fond, titre, menu de réglages.
struct CatalogPage<Content: View>: View {
    let title: LocalizedStringKey
    @Bindable var settings: CatalogSettings
    let scrolls: Bool
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey,
        settings: CatalogSettings,
        scrolls: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.settings = settings
        self.scrolls = scrolls
        self.content = content()
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView {
                    VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                        content
                    }
                    .padding(ChimpSpacing.screenMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content
            }
        }
        .foregroundStyle(.chimpTextPrimary)
        .background(Color(.chimpBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Appearance") {
                        Picker("Appearance", selection: $settings.appearance) {
                            ForEach(CatalogSettings.Appearance.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Section("Text size") {
                        Picker("Text size", selection: $settings.textSize) {
                            ForEach(CatalogSettings.TextSize.allCases) { Text($0.title).tag($0) }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .fontWeight(.heavy)
                        .frame(minWidth: ChimpSize.minimumTouchTarget, minHeight: ChimpSize.minimumTouchTarget)
                }
                .accessibilityLabel(Text("Catalog settings"))
            }
        }
        .catalogOverrides(settings)
    }
}

extension View {
    /// Applique le thème et la taille de texte forcés dans le catalogue.
    func catalogOverrides(_ settings: CatalogSettings) -> some View {
        preferredColorScheme(settings.appearance.colorScheme)
            .transformEnvironment(\.dynamicTypeSize) { size in
                if let forced = settings.textSize.dynamicTypeSize { size = forced }
            }
    }
}

/// Titre de section d'une page du catalogue.
struct CatalogSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .chimpFont(.label)
            .textCase(.uppercase)
            .foregroundStyle(.chimpTextSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    NavigationStack {
        DesignSystemCatalogView()
    }
}
#endif
