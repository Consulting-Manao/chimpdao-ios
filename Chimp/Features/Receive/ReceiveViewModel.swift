import Foundation
import Observation

/// ViewModel de Recevoir (D1) : charge les tiroirs et leurs adresses, gère le choix du tiroir,
/// la copie et les états. Ne fait aucun calcul crypto et ne connaît que le protocole `ReceiveDataSource`.
///
/// Rien à signer ici : recevoir ne demande jamais la carte (ARCHITECTURE §3.8).
@Observable
final class ReceiveViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// Tiroir prêt à afficher (textes déjà formatés).
    struct DrawerContent: Equatable, Identifiable {
        let id: String
        let icon: ChimpDrawerIcon
        /// « Main account », « Jungle's wallet ».
        let title: String
        /// Sous-titre dans la feuille de choix.
        let spendRule: String
        /// Adresse complète : copiée, partagée, dans le QR.
        let address: String
        /// Adresse raccourcie pour la pilule (8 premiers caractères…6 derniers, comme `AddrCopy` du terminal).
        let shortAddress: String
    }

    private(set) var phase: Phase = .loading
    private(set) var drawers: [DrawerContent] = []
    /// Le réseau des adresses, lu avec elles (`nil` tant qu'elles ne sont pas lues).
    private(set) var network: StellarNetwork?
    private(set) var selectedDrawerID: String?
    /// Vrai pendant quelques secondes après une copie (pilule « Copied! »).
    private(set) var isCopied = false
    /// Augmente à chaque copie : déclenche le retour haptique et l'annonce VoiceOver, même si on copie deux fois de suite.
    private(set) var copyCount = 0
    var isPickerPresented = false

    private let dataSource: ReceiveDataSource
    private let clipboard: AddressClipboard
    private let copiedDuration: Duration
    /// Tiroir à choisir à l'ouverture (ex. : depuis la page d'une carte, B3). Main sinon.
    private let initialDrawerID: String?
    private var hasLoaded = false
    private var copiedResetTask: Task<Void, Never>?

    init(
        dataSource: ReceiveDataSource,
        initialDrawerID: String? = nil,
        clipboard: AddressClipboard = SystemAddressClipboard(),
        copiedDuration: Duration = ChimpMotion.Copied.display
    ) {
        self.dataSource = dataSource
        self.initialDrawerID = initialDrawerID
        self.clipboard = clipboard
        self.copiedDuration = copiedDuration
    }

    // MARK: Contenu

    var selectedDrawer: DrawerContent? {
        drawers.first { $0.id == selectedDrawerID } ?? drawers.first
    }

    /// Le choix du tiroir n'a de sens que s'il y en a plusieurs.
    var canChooseDrawer: Bool { drawers.count > 1 }

    /// Badge « Testnet » : tant qu'on n'est pas sur mainnet, de l'argent réel envoyé ici serait perdu.
    var showsTestnetBadge: Bool { network == .testnet }

    // MARK: Actions

    /// Premier affichage : ne recharge pas si les adresses sont déjà là.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    /// Charge (ou recharge après une erreur) les tiroirs et leurs adresses.
    func load() async {
        phase = .loading
        do {
            let options = try await dataSource.fetchReceiveOptions()
            network = options.network
            drawers = options.drawers.map(Self.format)
            if selectedDrawerID == nil || !drawers.contains(where: { $0.id == selectedDrawerID }) {
                selectedDrawerID = drawers.first { $0.id == initialDrawerID }?.id ?? drawers.first?.id
            }
            phase = drawers.isEmpty ? .failed : .loaded
        } catch is CancellationError {
            // Chargement interrompu (écran quitté) : rien à faire.
        } catch {
            phase = .failed
        }
    }

    func showPicker() {
        guard canChooseDrawer else { return }
        isPickerPresented = true
    }

    func select(drawerID: String) {
        if drawerID != selectedDrawerID {
            selectedDrawerID = drawerID
            resetCopied()
        }
        isPickerPresented = false
    }

    /// Copie l'adresse **complète** du tiroir choisi, puis affiche « Copied! » quelques secondes.
    func copyAddress() {
        guard let drawer = selectedDrawer else { return }
        clipboard.copy(drawer.address)
        isCopied = true
        copyCount += 1
        copiedResetTask?.cancel()
        let duration = copiedDuration
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isCopied = false
        }
    }

    func takePaymentInPerson() {
        // TODO(jalon 4) : shop mode (D2), si le périmètre V1 le retient (DESIGN_NOTES §12, question 2).
    }

    private func resetCopied() {
        copiedResetTask?.cancel()
        isCopied = false
    }

    // MARK: Partage

    /// Message de « Share my address » pour le tiroir choisi.
    var shareText: String? {
        selectedDrawer.flatMap { drawer in
            network.map { Self.shareText(address: drawer.address, drawerTitle: drawer.icon == .main ? nil : drawer.title, network: $0) }
        }
    }

    /// Texte validé par Barth le 2026-10-01 : l'adresse **complète**, les actifs acceptés, et sur testnet l'avertissement
    /// sur le réseau. `drawerTitle` : wallet d'une carte (`nil` pour Main).
    static func shareText(address: String, drawerTitle: String?, network: StellarNetwork) -> String {
        let intro = if let drawerTitle {
            String(localized: "Send me money on \(drawerTitle) (\(network.displayName)):")
        } else {
            String(localized: "Send me money on \(network.displayName):")
        }
        var lines = [intro, address, "", String(localized: "Accepted: XLM and USDC.")]
        if network != .mainnet {
            lines.append(String(localized: "⚠️ \(network.displayName) only. Money sent from another network will be lost."))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Formatage

    private static func format(_ drawer: ReceiveDrawer) -> DrawerContent {
        let address = drawer.address
        let shortAddress = address.count > 16 ? "\(address.prefix(8))…\(address.suffix(6))" : address
        switch drawer.kind {
        case .main:
            return DrawerContent(
                id: drawer.id,
                icon: .main,
                title: String(localized: "Main account"),
                spendRule: String(localized: "Any of your cards can spend it"),
                address: address,
                shortAddress: shortAddress
            )
        case let .card(name, color):
            return DrawerContent(
                id: drawer.id,
                icon: .card(color),
                title: String(localized: "\(name)'s wallet"),
                spendRule: String(localized: "Only this card can spend it"),
                address: address,
                shortAddress: shortAddress
            )
        }
    }
}
