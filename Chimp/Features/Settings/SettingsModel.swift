import Foundation
import Observation

/// Une carte du compte, telle que les réglages la montrent (nom et couleur locaux).
struct SettingsCard: Hashable, Identifiable {
    /// Clé publique (hexadécimal).
    let id: String
    /// « 0007 », ou « ···· ».
    let number: String
    let name: String?
    let color: ChimpCardColor
    /// De quoi enregistrer la carte si ce téléphone ne la connaissait pas encore.
    let chip: ChipKind?
    let tokenID: UInt32?
    let pocket: String?

    /// Nom affiché : le nom local, ou « Card » (comme le Wallet).
    var displayName: String { name ?? String(localized: "Card") }
}

/// ViewModel des réglages de base (I2) : prénom, nom et couleur des cartes, « Disconnect this phone ».
/// Rien n'y touche la chaîne ni une carte : ce sont des données du téléphone (« No card needed here »).
@Observable
final class SettingsModel {
    private let session: AppSession
    /// Cartes lues par le Wallet (`cards()` du compte) ; complétées par celles enregistrées sur le téléphone.
    private let walletCards: [CardBalance]

    /// Carte en cours de modification (« Rename & colour »).
    private(set) var editingCard: SettingsCard?
    var editedName = ""
    var editedColor: ChimpCardColor = .jungle

    var isEditingFirstName = false
    var editedFirstName = ""

    var isConfirmingDisconnect = false
    /// Dernière écriture ratée (texte technique).
    private(set) var saveError: String?

    /// Prix de l'oracle Reflector, pour savoir quelles devises de I3 il cote ; `nil` : toutes proposées.
    private let oracle: PriceOracle?

    init(session: AppSession, walletCards: [CardBalance], oracle: PriceOracle? = nil) {
        self.session = session
        self.walletCards = walletCards
        self.oracle = oracle
    }

    static let maximumCardNameLength = AccountSetupModel.maximumCardNameLength
    static let maximumFirstNameLength = AccountSetupModel.maximumFirstNameLength

    var firstName: String? { session.wallet.firstName }

    /// Les cartes du compte : d'abord celles que le compte déclare (ordre du contrat, lu par le Wallet), puis celles que
    /// seul le téléphone connaît (Wallet pas encore chargé). Nom et couleur viennent toujours du téléphone.
    var cards: [SettingsCard] {
        let saved = session.wallet.account?.cards ?? []
        var result: [SettingsCard] = walletCards.map { card in
            let local = saved.first { $0.publicKey == card.id }
            return SettingsCard(
                id: card.id,
                number: card.number,
                name: local?.name,
                color: local?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle,
                chip: card.chip ?? local.flatMap { ChipKind(rawValue: $0.chip) },
                tokenID: card.tokenID ?? local?.tokenID,
                pocket: card.pocket ?? local?.pocket
            )
        }
        for local in saved where !result.contains(where: { $0.id == local.publicKey }) {
            result.append(SettingsCard(
                id: local.publicKey,
                number: local.tokenID.map { String(format: "%04u", $0) } ?? "····",
                name: local.name,
                color: local.color.flatMap(ChimpCardColor.init(rawValue:)) ?? .jungle,
                chip: ChipKind(rawValue: local.chip),
                tokenID: local.tokenID,
                pocket: local.pocket
            ))
        }
        return result
    }

    /// Cartes dont on peut changer le PIN : les Infineon (une DUOX n'a pas de PIN).
    var pinCards: [PINCard] {
        cards.compactMap { card in
            guard card.chip == .infineon2Go, let key = try? ChipPublicKey(Data(hex: card.id) ?? Data()) else { return nil }
            return PINCard(key: key, name: card.displayName, color: card.color, number: card.number)
        }
    }

    // MARK: Rename & colour

    func edit(_ card: SettingsCard) {
        editingCard = card
        editedName = card.name ?? ""
        editedColor = card.color
        saveError = nil
    }

    /// Retour sans enregistrer.
    func cancelEditing() {
        editingCard = nil
        saveError = nil
    }

    var trimmedName: String { editedName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSaveCard: Bool {
        guard let editingCard else { return false }
        guard !trimmedName.isEmpty, trimmedName.count <= Self.maximumCardNameLength else { return false }
        return trimmedName != editingCard.name || editedColor != editingCard.color
    }

    /// Enregistre le nom et la couleur sur le téléphone. Renvoie vrai si c'est fait.
    @discardableResult
    func saveCard() -> Bool {
        guard canSaveCard, let card = editingCard else { return false }
        // Une carte que le téléphone ne connaît pas : sa puce vient de la courbe déclarée par le compte. Sans elle, on
        // suppose une Infineon (le PIN sera demandé ; la carte dira au tap si elle en a vraiment un).
        let saved = SavedCard(
            publicKey: card.id, chip: (card.chip ?? .infineon2Go).rawValue, tokenID: card.tokenID, pocket: card.pocket,
            name: trimmedName, color: editedColor.rawValue
        )
        do {
            try session.renameCard(saved)
            saveError = nil
            editingCard = nil
            return true
        } catch {
            saveError = OnboardingModel.details(error)
            return false
        }
    }

    // MARK: Prénom

    func editFirstName() {
        editedFirstName = firstName ?? ""
        saveError = nil
        isEditingFirstName = true
    }

    var trimmedFirstName: String { editedFirstName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSaveFirstName: Bool {
        !trimmedFirstName.isEmpty && trimmedFirstName.count <= Self.maximumFirstNameLength && trimmedFirstName != firstName
    }

    func saveFirstName() {
        guard canSaveFirstName else { return }
        do {
            try session.setFirstName(trimmedFirstName)
            saveError = nil
            isEditingFirstName = false
        } catch {
            saveError = OnboardingModel.details(error)
        }
    }

    // MARK: Disconnect this phone

    /// Un paiement signé attend encore son issue : le téléphone doit le garder, la déconnexion est refusée.
    var hasPendingPayment: Bool { session.wallet.pendingSend != nil }

    /// Après confirmation : le compte est oublié sur ce téléphone, l'app revient à A1.
    func disconnect() {
        do {
            try session.disconnect()
            saveError = nil
        } catch {
            saveError = OnboardingModel.details(error)
        }
    }

    // MARK: Erase everything on this phone

    var isConfirmingErase = false

    /// Après confirmation : tout ce que l'app garde sur ce téléphone est effacé, l'app revient à A1.
    func eraseEverything() {
        do {
            try session.eraseEverything()
            saveError = nil
        } catch {
            saveError = OnboardingModel.details(error)
        }
    }

    // MARK: Display

    /// « Show amounts in » (I3) : ne change que l'affichage du Wallet et des pages de tiroir.
    var currency: DisplayCurrency {
        get { session.preferences.currency }
        set { session.preferences.currency = newValue }
    }

    var isChoosingCurrency = false
    /// Devises que l'oracle ne cote pas (aujourd'hui : CHF, absent du flux FX de Reflector) : grisées dans I3, comme
    /// `listDenominations` du terminal ne propose que les devises cotées. Vide tant qu'on ne sait pas.
    private(set) var unavailableCurrencies: Set<DisplayCurrency> = []

    /// À l'ouverture de I3 : demande à l'oracle le prix de chaque devise (5 minutes en mémoire). Si l'oracle ne répond
    /// pour aucune (réseau absent), rien n'est grisé : on ne sait pas.
    func loadCurrencyRates() async {
        guard let oracle else { return }
        let codes = Set(DisplayCurrency.allCases.filter { $0 != .usd }.map(\.code))
        let prices = await oracle.usdPrices(for: codes)
        unavailableCurrencies = Self.unavailable(prices: prices)
    }

    static func unavailable(prices: [String: Decimal]) -> Set<DisplayCurrency> {
        guard !prices.isEmpty else { return [] }
        return Set(DisplayCurrency.allCases.filter { $0 != .usd && (prices[$0.code] ?? 0) <= 0 })
    }

    /// Choix d'une devise dans la feuille I3 : enregistré, puis la feuille se ferme.
    func choose(_ currency: DisplayCurrency) {
        guard !unavailableCurrencies.contains(currency) else { return }
        self.currency = currency
        isChoosingCurrency = false
    }

    /// « Look » : comme l'iPhone, Yellow banana (clair) ou Jungle night (sombre). Toute l'app change aussitôt.
    var look: ChimpLook {
        get { session.preferences.look }
        set { session.preferences.look = newValue }
    }

    // MARK: Network (affichage seulement)

    /// Ce que montre la ligne « Network » (I2). **Jamais un interrupteur** : le réseau vient de la configuration de build,
    /// l'app ne le change pas (DESIGN_NOTES §12, 2026-09-30).
    struct NetworkRow: Equatable {
        /// Segments affichés, dans l'ordre.
        let options: [StellarNetwork]
        /// Réseau réellement utilisé par l'app : le segment choisi.
        let current: StellarNetwork
        /// Segments grisés « Coming soon » : un toucher montre la bulle de Chimpy, rien ne change.
        let comingSoon: Set<StellarNetwork>
    }

    /// Debug et Testing : Testnet (le réseau utilisé) et Mainnet grisé « Coming soon ». Release : **seulement** le réseau
    /// réellement utilisé, sans autre option ni « Coming soon » (décision de Barth du 2026-09-30).
    static func networkRow(current: StellarNetwork, isDeveloperBuild: Bool) -> NetworkRow {
        guard isDeveloperBuild else { return NetworkRow(options: [current], current: current, comingSoon: []) }
        let options: [StellarNetwork] = [.testnet, .mainnet]
        return NetworkRow(options: options, current: current, comingSoon: Set(options.filter { $0 != current }))
    }

    /// Build de développement (Debug, Testing) : ceux qui ont le catalogue et le mode admin.
    static var isDeveloperBuild: Bool {
        #if DESIGN_CATALOG
        true
        #else
        false
        #endif
    }

    var networkRow: NetworkRow {
        Self.networkRow(current: session.network, isDeveloperBuild: Self.isDeveloperBuild)
    }

    /// Bulle « Real bananas are coming soon! » après un toucher sur un réseau grisé.
    var isShowingNetworkBubble = false

    // MARK: Visite, aide, version

    /// « How ChimpDAO works · Replay the tour ».
    var isReplayingTour = false

    /// Adresse d'aide et de contact (demande de Barth du 2026-09-30).
    static let helpEmail = "chimpdao@consulting-manao.com"

    /// « Help » : un e-mail prêt à écrire, avec la version de l'app dans l'objet (utile au support).
    static var helpURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = helpEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "ChimpDAO help (\(versionText))")]
        return components.url
    }

    /// Version de l'app et numéro de build : « 1.1.0 (1) ».
    static var versionText: String { versionText(bundle: .main) }

    static func versionText(bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
