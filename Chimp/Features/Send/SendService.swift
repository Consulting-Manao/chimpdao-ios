import Foundation

/// Un tiroir d'où l'argent peut partir : Main (le compte partagé) ou le wallet d'une carte (sa Pocket).
struct SendDrawer: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Chimp account : n'importe quelle carte du compte peut signer (ARCHITECTURE §3.7, ordre 2).
        case main
        /// Pocket d'une carte : seule cette carte peut signer (ordre 1). Nom et couleur sont des données locales.
        case card(name: String, color: ChimpCardColor)
    }

    /// « main », ou le numéro de la carte (`token_id` de son NFT, d'après DESIGN_NOTES §1.1).
    let id: String
    let kind: Kind
    /// Adresse du contrat (`C…`) : sert à refuser un envoi vers soi-même (il faut passer par Move).
    let address: String
    /// Solde disponible par actif (hors épargne Grow), dans l'unité de l'actif.
    var balances: [SendAsset: Decimal]
    /// Un PIN peut être demandé pour signer depuis ce tiroir. Wallet d'une carte : cette carte a un PIN actif
    /// (Infineon ; une DUOX n'en a jamais). Main : au moins une carte du compte en a un ; le PIN ne sert
    /// que si la carte tapée en a un. Connu localement depuis la dernière lecture des cartes.
    var usesPin: Bool

    func balance(of asset: SendAsset) -> Decimal {
        balances[asset] ?? 0
    }

    /// Nom affiché (glossaire, DESIGN_NOTES §1.2) : « Main account », « Jungle's wallet ».
    var title: String {
        switch kind {
        case .main: String(localized: "Main account")
        case .card(let name, _): String(localized: "\(name)'s wallet")
        }
    }

    var icon: ChimpDrawerIcon {
        switch kind {
        case .main: .main
        case .card(_, let color): .card(color)
        }
    }
}

/// Destinataire déjà payé depuis ce téléphone (C1 « Recent »). Donnée locale, jamais on-chain.
struct SendContact: Equatable, Identifiable {
    let id: String
    let name: String
    let color: ChimpCardColor
    /// Adresse complète payée la dernière fois (G, M ou C).
    let address: String
}

/// Ce que le parcours Envoyer a besoin de connaître avant de commencer.
struct SendContext: Equatable {
    var network: StellarNetwork
    /// Main d'abord, puis les wallets des cartes.
    var drawers: [SendDrawer]
    var recents: [SendContact]
    /// Prix en dollars des actifs à prix variable (XLM), pour l'équivalent « ≈ $ ». Source à confirmer
    /// (DESIGN_NOTES §12, question 8) : absent = pas d'équivalent affiché.
    var usdPrices: [SendAsset: Decimal]
}

/// Ce qui sera signé, figé au passage à la vérification (C4). Affiché tel quel, sans rien recalculer.
struct SendDraft: Equatable {
    let recipient: StellarRecipient
    /// Nom du destinataire s'il vient des récents.
    let recipientName: String?
    let drawer: SendDrawer
    let asset: SendAsset
    /// Montant exact, indépendant de la langue du téléphone.
    let amount: Decimal
    let network: StellarNetwork
    /// Move (E1) : le tiroir d'arrivée, l'un des siens (Main ou le wallet d'une carte). `recipient` est alors son
    /// adresse. `nil` pour un envoi.
    var destination: SendDrawer? = nil

    var isMove: Bool { destination != nil }
}

/// Envoi préparé **avant** la session NFC (règle 9) : solde relu, cartes qui peuvent signer, et l'autorisation que la
/// carte signera (`PreparedPayment`, ordre 1 ou 2). Le service factice n'a que le brouillon.
struct PreparedSend: Equatable {
    let draft: SendDraft
    /// Ce que la carte signera (vrai service) ; `nil` dans le service factice.
    let payment: PreparedPayment?

    init(draft: SendDraft, payment: PreparedPayment? = nil) {
        self.draft = draft
        self.payment = payment
    }

    static func == (lhs: PreparedSend, rhs: PreparedSend) -> Bool {
        lhs.draft == rhs.draft && lhs.payment?.digest == rhs.payment?.digest
    }
}

/// Ce qu'apprend une première lecture de la carte (ordre « tap puis PIN ») : quelle carte, et si elle a un PIN
/// (SELECT, octet « PIN actif », + GET KEY INFO, comparée aux cartes qui peuvent signer).
struct CardCheck: Equatable {
    /// Nom et couleur locaux de la carte tapée.
    let cardName: String
    let cardColor: ChimpCardColor
    let usesPin: Bool
    /// Clé de la carte lue : le second tap n'accepte **que** cette carte (le PIN saisi est le sien). `nil` : service factice.
    var publicKey: ChipPublicKey? = nil
}

/// Premier tap de l'ordre « tap puis PIN » : la carte lue, et sa signature si elle n'a pas de PIN (un seul tap).
struct CardRead: Equatable {
    let check: CardCheck
    let signed: SignedSend?
}

/// Une carte du compte, connue sur ce téléphone (nom et couleur locaux) : sert à dire quelle carte a été tapée (C7).
struct KnownCard: Equatable {
    let name: String
    let color: ChimpCardColor
}

/// Envoi signé par la carte, prêt à partir (frais par le serveur de frais, envoi : `SendService.submit`).
struct SignedSend: Equatable {
    let prepared: PreparedSend
    /// Nom local de la carte qui a signé (« Signed by Banana »).
    let cardName: String
    /// Carte et signature (vrai service) ; `nil` dans le service factice.
    let card: CardSignatures?

    init(prepared: PreparedSend, cardName: String, card: CardSignatures? = nil) {
        self.prepared = prepared
        self.cardName = cardName
        self.card = card
    }
}

/// Paiement confirmé sur la chaîne (C9, reçu).
struct SendReceipt: Equatable {
    let summary: SendSummary
    let transactionHash: String
    let sentAt: Date
    /// Page de la transaction dans l'explorateur (Stellar Expert).
    let explorerURL: URL?

    /// La ligne que ce téléphone écrit dans son historique pour cet envoi (`recordPayment`) : « See the receipt » (C9)
    /// ouvre le même reçu imprimé que cette ligne dans l'Activity (I1.1d).
    var activityRecord: ActivityRecord {
        .payment(
            hash: transactionHash, from: summary.fromAddress, to: summary.recipientAddress, assetCode: summary.asset.code,
            amount: summary.amount, at: sentAt
        )
    }
}

/// Ce qui a été signé, tel qu'on le réaffiche après coup (envoi en cours, C9, reçu, issue incertaine), y compris
/// après un redémarrage de l'app (depuis un `PendingSend`).
struct SendSummary: Equatable {
    /// Adresse exacte payée (G, M ou C).
    let recipientAddress: String
    let recipientName: String?
    let drawerTitle: String
    /// Adresse du tiroir de départ (Main account ou wallet d'une carte).
    let fromAddress: String
    let asset: SendAsset
    let amount: Decimal
    let network: StellarNetwork

    init(
        recipientAddress: String, recipientName: String?, drawerTitle: String, fromAddress: String, asset: SendAsset, amount: Decimal,
        network: StellarNetwork
    ) {
        self.recipientAddress = recipientAddress
        self.recipientName = recipientName
        self.drawerTitle = drawerTitle
        self.fromAddress = fromAddress
        self.asset = asset
        self.amount = amount
        self.network = network
    }

    init(_ draft: SendDraft) {
        self.init(
            recipientAddress: draft.recipient.address, recipientName: draft.recipientName, drawerTitle: draft.drawer.title,
            fromAddress: draft.drawer.address, asset: draft.asset, amount: draft.amount, network: draft.network
        )
    }

    init(_ pending: PendingSend, network: StellarNetwork) {
        self.init(
            recipientAddress: pending.recipient, recipientName: pending.recipientName, drawerTitle: pending.drawerTitle,
            fromAddress: pending.trace.from, asset: SendAsset(rawValue: pending.asset) ?? .xlm, amount: pending.amount, network: network
        )
    }

    /// Nom du destinataire, ou son adresse raccourcie (« GBLW…EZ6M »).
    var recipientLabel: String {
        recipientName ?? StellarAddressParser.short(recipientAddress)
    }

    /// Memo ID plié dans une adresse M, pour le reçu.
    var memoID: UInt64? {
        if case .success(let recipient) = StellarAddressParser.parse(recipientAddress) { return recipient.memoID }
        return nil
    }
}

/// Service d'envoi. `ChainSendService` (testnet, `Core/`) dans l'app, `MockSendService` dans le catalogue et les tests.
protocol SendService {
    /// Le réseau de l'envoi (celui de la session) : liens de paiement scannés, résumés. Jamais choisi par l'écran.
    var config: ChimpNetworkConfig { get }
    /// Soldes, tiroirs et destinataires récents.
    func fetchContext() async throws -> SendContext
    /// Appels réseau à faire avant la session NFC (limite Apple de 60 s, règle 9) : rien n'est signé.
    func prepare(_ draft: SendDraft) async throws -> PreparedSend
    /// Juste avant le tap qui signe (réseau, avant la session NFC) : refait la préparation si l'autorisation n'a plus
    /// 20 ledgers devant elle (`EXPIRATION_MARGIN_LEDGERS`). Sinon, la renvoie telle quelle.
    func refreshedIfNeeded(_ prepared: PreparedSend) async throws -> PreparedSend
    /// Premier tap de l'ordre « tap puis PIN » : quelle carte, avec ou sans PIN ; sans PIN, elle signe dans le même tap.
    /// Une carte qui ne peut pas signer est refusée (`ChipError.cardNotAccepted`), sans rien lui envoyer d'autre.
    func readCard(for prepared: PreparedSend) async throws -> CardRead
    /// Session NFC de signature : clé de la carte vérifiée, puis VERIFY PIN si la carte en a un, puis SIGN.
    /// `onlyCard` : seulement cette carte (second tap de l'ordre « tap puis PIN »). Le PIN n'est jamais gardé.
    func sign(_ prepared: PreparedSend, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSend
    /// Carte du compte connue sur ce téléphone, `nil` si ce n'est pas une carte du compte.
    func knownCard(_ key: ChipPublicKey) -> KnownCard?
    /// Après le tap : frais par le serveur de frais, envoi, attente de la confirmation. Toute erreur est un
    /// `PaymentFailure` : l'autorisation signée a pu sortir du téléphone, l'issue se vérifie avec `check`.
    /// La trace que l'envoi suivra, connue **avant** l'envoi : gardée sur le téléphone dès le retour de la carte (revue
    /// de sécurité F7), pour qu'une app tuée pendant l'envoi ne permette jamais une nouvelle signature.
    func trace(for signed: SignedSend) throws -> PaymentTrace
    func submit(_ signed: SignedSend, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SendReceipt
    /// « Check again » (question 16) : envoyé, peut encore passer, attendre, rien n'est parti, ou impossible à dire.
    func check(_ trace: PaymentTrace) async throws -> PaymentCheck
    /// Paiement à l'issue incertaine gardé sur le téléphone (Envoyer rouvre son état au lieu d'un nouvel envoi).
    var pendingSend: PendingSend? { get }
    func setPendingSend(_ pending: PendingSend?) throws
    /// Page d'une transaction dans l'explorateur.
    func explorerURL(transactionHash: String) -> URL?
}

/// Données et signature factices (noms de la maquette), avec des scénarios pour tester chaque état.
///
/// Les adresses sont **fausses mais au format valide** (somme de contrôle correcte), calculées hors de l'app
/// (`sha256` d'un libellé, encodé en adresse Stellar) : elles n'appartiennent à personne.
/// Les adresses des tiroirs sont celles de `MockReceiveDataSource`.
final class MockSendService: SendService {
    /// Le service factice vit sur le testnet (adresses et liens de la maquette).
    let config = ChimpNetworkConfig.testnet
    enum DataScenario: String, CaseIterable, Identifiable {
        /// Maquette : Main + Jungle + Banana, trois destinataires récents.
        case standard
        /// Tous les soldes à zéro.
        case emptyBalances
        /// Main seul, sans carte à choisir.
        case mainOnly
        /// Aucun destinataire récent.
        case noRecents
        /// Chargement qui ne se termine pas.
        case loadingForever
        /// Erreur réseau au chargement des soldes.
        case networkError
        /// Soldes XLM à 7 décimales (capture de Barth du 2026-10-01 : « 999,6196784 »).
        case longDecimals

        var id: String { rawValue }
    }

    /// Puces des cartes du compte factice.
    enum CardSetup: String, CaseIterable, Identifiable {
        /// Deux Infineon avec PIN.
        case allWithPin
        /// Deux DUOX : jamais de PIN.
        case noPin
        /// Jungle = Infineon avec PIN, Banana = DUOX sans PIN. Depuis Main, c'est Jungle qui est tapée.
        case mixed

        var id: String { rawValue }
    }

    static let mayaAddress = "GCQF355RQFN77CHM5DHEGK75FWVF26PUES6J6EMQ4U7BAD3E7ORDGXPO"
    static let tomAddress = "GBTWPJNLC3BYIDPCXYYO5F4G5C245OMGXFHQPLHAATQXHL37DY7ZFNMB"
    /// Compte d'un exchange fictif, et la même adresse avec le memo ID 1234567890 plié dedans (SEP-23).
    static let exchangeAddress = "GB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL452DN"
    static let exchangeMuxedAddress = "MB53FJ3TWAR2IFCHTD4Y2MWYMMOZ7PDCW4DU5OXPZMULLJQQ4PL44AAAAAAETFQC2J5EQ"

    /// Issue de l'envoi après le tap.
    enum ResultScenario: String, CaseIterable, Identifiable {
        /// Confirmé du premier coup (C9).
        case sent
        /// Envoyé, pas confirmé dans le délai ; « Check again » le trouve confirmé.
        case notConfirmedThenSent
        /// Refusé après la signature : attendre l'expiration de l'autorisation (compte à rebours de 15 s ici), puis
        /// « Nothing was sent ».
        case rejectedThenNothingSent
        /// Le RPC ne peut pas trancher.
        case undetermined
        /// Revue F3 : le premier envoi est retenu (le serveur de frais garde l'autorisation signée et dit « échec ») ;
        /// l'autorisation reste valable (« Not sent », compte à rebours) ; un renvoi passe.
        case withheld

        var id: String { rawValue }
    }

    /// Carte posée au premier tap qui signe (catalogue : voir C7 sans deuxième carte).
    enum TapScenario: String, CaseIterable, Identifiable {
        /// La bonne carte.
        case rightCard
        /// Une autre carte du compte (Banana), une fois ; le tap suivant est le bon.
        case otherCard
        /// Une carte qui n'est pas du compte, une fois.
        case unknownCard

        var id: String { rawValue }
    }

    let dataScenario: DataScenario
    let cardSetup: CardSetup
    var resultScenario: ResultScenario
    var tapScenario: TapScenario = .rightCard
    /// Attente factice de l'expiration de l'autorisation.
    var authorizationWait: Duration = .seconds(15)
    /// Paiement à l'issue incertaine (tests : réglable pour simuler un Envoyer rouvert).
    var pendingSend: PendingSend?
    /// Erreur de la prochaine signature (tests : PIN faux, carte refusée…), consommée une fois.
    var nextSignError: Error?
    /// Erreur de la prochaine préparation (tests : réseau en panne pendant la saisie du PIN), consommée une fois.
    var nextPrepareError: Error?
    /// Délai simulé du réseau.
    var delay: Duration
    /// Délai simulé d'une session NFC (le temps de poser la carte et de la lire).
    var nfcDelay: Duration

    /// Nombre d'appels, pour vérifier dans les tests qu'un envoi n'est jamais préparé ou signé deux fois.
    private(set) var prepareCount = 0
    private(set) var readCount = 0
    private(set) var signCount = 0
    private(set) var submitCount = 0
    /// Chaque autorisation signée envoyée, dans l'ordre (tests de la revue F3).
    private(set) var submitted: [SignedSend] = []
    private(set) var checkCount = 0
    private(set) var refreshCount = 0
    /// PIN reçu par la dernière signature (tests uniquement : le vrai service ne le garde jamais).
    private(set) var lastPin: String?

    init(
        dataScenario: DataScenario = .standard,
        cardSetup: CardSetup = .allWithPin,
        resultScenario: ResultScenario = .sent,
        delay: Duration = .milliseconds(600),
        nfcDelay: Duration = .milliseconds(1500)
    ) {
        self.dataScenario = dataScenario
        self.cardSetup = cardSetup
        self.resultScenario = resultScenario
        self.delay = delay
        self.nfcDelay = nfcDelay
    }

    func fetchContext() async throws -> SendContext {
        if dataScenario == .loadingForever {
            try await Task.sleep(for: .seconds(3600))
        }
        try await Task.sleep(for: delay)
        if dataScenario == .networkError {
            throw URLError(.notConnectedToInternet)
        }
        return context
    }

    func prepare(_ draft: SendDraft) async throws -> PreparedSend {
        prepareCount += 1
        try await Task.sleep(for: delay)
        if let error = nextPrepareError {
            nextPrepareError = nil
            throw error
        }
        return PreparedSend(draft: draft)
    }

    func refreshedIfNeeded(_ prepared: PreparedSend) async throws -> PreparedSend {
        refreshCount += 1
        return prepared
    }

    /// Erreur du prochain premier tap (tests : carte refusée…), consommée une fois.
    var nextReadError: Error?
    /// Tests : la carte lue au premier tap a-t-elle un PIN (sinon : selon `cardSetup`), et sa clé.
    var readCardUsesPin: Bool?
    var readCardKey: ChipPublicKey?
    /// `onlyCard` reçu par la dernière signature (tests).
    private(set) var lastOnlyCard: ChipPublicKey?
    /// Cartes « du compte » connues du téléphone factice (C7) : la clé secp256k1 de test est Banana.
    var knownCards: [ChipPublicKey: KnownCard] = [MockChipReader.secp256k1Key: KnownCard(name: "Banana", color: .banana)]

    /// Erreur de carte du scénario de tap, une seule fois.
    private func tapScenarioError() -> Error? {
        let scenario = tapScenario
        tapScenario = .rightCard
        switch scenario {
        case .rightCard: return nil
        case .otherCard: return ChipError.cardNotAccepted(tapped: MockChipReader.secp256k1Key)
        case .unknownCard: return ChipError.cardNotAccepted(tapped: MockChipReader.p256Key)
        }
    }

    func readCard(for prepared: PreparedSend) async throws -> CardRead {
        readCount += 1
        try await Task.sleep(for: nfcDelay)
        if let error = tapScenarioError() { throw error }
        if let error = nextReadError {
            nextReadError = nil
            throw error
        }
        var check = tappedCard(for: prepared.draft.drawer)
        if readCardUsesPin != nil || readCardKey != nil {
            check = CardCheck(
                cardName: check.cardName, cardColor: check.cardColor,
                usesPin: readCardUsesPin ?? check.usesPin, publicKey: readCardKey
            )
        }
        guard !check.usesPin else { return CardRead(check: check, signed: nil) }
        // Carte sans PIN : elle signe dans le même tap.
        signCount += 1
        lastPin = nil
        return CardRead(check: check, signed: SignedSend(prepared: prepared, cardName: check.cardName))
    }

    func sign(_ prepared: PreparedSend, pin: String?, onlyCard: ChipPublicKey?) async throws -> SignedSend {
        signCount += 1
        lastPin = pin
        lastOnlyCard = onlyCard
        try await Task.sleep(for: nfcDelay)
        if let error = tapScenarioError() { throw error }
        if let error = nextSignError {
            nextSignError = nil
            throw error
        }
        return SignedSend(prepared: prepared, cardName: tappedCard(for: prepared.draft.drawer).cardName)
    }

    /// Hash factice, visiblement faux.
    static let fakeHash = String(repeating: "ab", count: 32)

    func trace(for signed: SignedSend) throws -> PaymentTrace {
        let draft = signed.prepared.draft
        return PaymentTrace(
            token: "mock", from: draft.drawer.address, destination: draft.recipient.address, units: 0, nonce: 1,
            preparedAtLedger: 1, expirationLedger: 121
        )
    }

    func submit(_ signed: SignedSend, onProgress: @escaping (PaymentProgress) -> Void) async throws -> SendReceipt {
        submitCount += 1
        submitted.append(signed)
        let draft = signed.prepared.draft
        for step: PaymentProgress in [.checking, .sending, .confirming] {
            onProgress(step)
            try await Task.sleep(for: delay)
        }
        var trace = try trace(for: signed)
        switch resultScenario {
        case .sent:
            return SendReceipt(summary: SendSummary(draft), transactionHash: Self.fakeHash, sentAt: .now, explorerURL: nil)
        case .notConfirmedThenSent, .undetermined:
            trace.transactionHash = Self.fakeHash
            throw PaymentFailure(trace: trace, underlying: StellarError.notConfirmed(hash: Self.fakeHash))
        case .rejectedThenNothingSent:
            throw PaymentFailure(trace: trace, underlying: StellarError.submitFailed("txBadAuth (mock)"))
        case .withheld where submitCount == 1:
            throw PaymentFailure(trace: trace, underlying: StellarError.submitFailed("fee server didn't answer (mock)"))
        case .withheld:
            return SendReceipt(summary: SendSummary(draft), transactionHash: Self.fakeHash, sentAt: .now, explorerURL: nil)
        }
    }

    private var waitingUntil: Date?

    func check(_ trace: PaymentTrace) async throws -> PaymentCheck {
        checkCount += 1
        try await Task.sleep(for: delay)
        switch resultScenario {
        case .sent:
            return .sent(hash: Self.fakeHash)
        case .notConfirmedThenSent:
            // Première vérification (juste après l'envoi) : toujours pas confirmé ; la suivante le trouve.
            return checkCount == 1 ? .pending : .sent(hash: Self.fakeHash)
        case .undetermined:
            return .undetermined("mock: Stellar RPC no longer keeps these ledgers")
        case .rejectedThenNothingSent, .withheld:
            let end = waitingUntil ?? .now.addingTimeInterval(TimeInterval(authorizationWait.components.seconds))
            waitingUntil = end
            return end > .now ? .waiting(untilLedger: 121, estimatedEnd: end) : .nothingSent
        }
    }

    func setPendingSend(_ pending: PendingSend?) throws {
        pendingSend = pending
    }

    func explorerURL(transactionHash: String) -> URL? {
        ChimpNetworkConfig.testnet.explorerURL(transactionHash: transactionHash)
    }

    func knownCard(_ key: ChipPublicKey) -> KnownCard? {
        knownCards[key]
    }

    /// Carte posée sur le téléphone : celle du tiroir, ou Jungle pour un envoi depuis Main.
    private func tappedCard(for drawer: SendDrawer) -> CardCheck {
        switch drawer.kind {
        case let .card(name, color):
            CardCheck(cardName: name, cardColor: color, usesPin: drawer.usesPin)
        case .main:
            CardCheck(cardName: "Jungle", cardColor: .jungle, usesPin: cardSetup != .noPin)
        }
    }

    /// Mêmes totaux en dollars que le Wallet factice (XLM à 0,25 $) : Main 820 $, Jungle 62,50 $, Banana 102,50 $.
    private var context: SendContext {
        let jungleUsesPin = cardSetup != .noPin
        let bananaUsesPin = cardSetup == .allWithPin
        var main = SendDrawer(
            id: "main", kind: .main, address: MockReceiveDataSource.mainAddress,
            balances: [.usdc: 720, .xlm: 400], usesPin: jungleUsesPin || bananaUsesPin
        )
        var jungle = SendDrawer(
            id: "0421", kind: .card(name: "Jungle", color: .jungle), address: MockReceiveDataSource.jungleAddress,
            balances: [.usdc: Decimal(string: "62.5")!], usesPin: jungleUsesPin
        )
        var banana = SendDrawer(
            id: "0688", kind: .card(name: "Banana", color: .banana), address: MockReceiveDataSource.bananaAddress,
            balances: [.usdc: Decimal(string: "72.5")!, .xlm: 120], usesPin: bananaUsesPin
        )
        var recents = [
            SendContact(id: "maya", name: "Maya", color: .pink, address: Self.mayaAddress),
            SendContact(id: "tom", name: "Tom", color: .jungle, address: Self.tomAddress),
            SendContact(id: "exchange", name: "Coconut Exchange", color: .leaf, address: Self.exchangeMuxedAddress),
        ]
        switch dataScenario {
        case .emptyBalances:
            main.balances = [:]
            jungle.balances = [:]
            banana.balances = [:]
        case .noRecents:
            recents = []
        case .longDecimals:
            main.balances[.xlm] = Decimal(string: "999.6196784")!
            banana.balances[.xlm] = Decimal(string: "0.0000042")!
        default:
            break
        }
        let drawers = dataScenario == .mainOnly ? [main] : [main, jungle, banana]
        return SendContext(network: .testnet, drawers: drawers, recents: recents, usdPrices: [.xlm: Decimal(string: "0.25")!])
    }
}
