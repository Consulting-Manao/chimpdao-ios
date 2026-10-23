#if CHIMP_ADMIN
import Foundation
import Observation

/// Une carte du lot « Prepare cards » (Meridian, demande de Barth du 2026-10-20), telle que notée dans le journal.
struct PreparedCard: Codable, Equatable, Identifiable {
    enum Status: Codable, Equatable {
        /// Enregistrée sur testnet par ce lot (hash connu).
        case prepared
        /// Déjà enregistrée sur la chaîne avant ce tap : rien n'a été écrit.
        case alreadyReady
        /// `mint` envoyé, issue pas encore notée (app coupée pendant l'envoi) : relue sur la chaîne au prochain tap.
        case pending
        /// Échec ; la carte peut être retapée, elle garde son numéro.
        case failed(String)
    }

    var id: String { publicKey }
    /// Numéro imprimé sur la carte (#001, #002…, sans limite).
    var number: Int
    /// Clé publique de la puce, en hexadécimal (130 caractères).
    let publicKey: String
    /// Adresse du wallet de la carte (Pocket), connue avant même l'enregistrement.
    var wallet: String
    var transactionHash: String?
    var status: Status
    var date: Date
    /// Argent de test envoyé au wallet de la carte après l'enregistrement (`nil` : pas encore essayé).
    var funding: Funding? = nil
    /// Note de l'équipe (« Pamphile's demo card ») : seulement dans Chimp Admin et le CSV, jamais sur la chaîne ni
    /// chez l'utilisateur (aucun contrat ne garde de nom par carte, vérifié le 2026-10-20).
    var note: String? = nil
    /// Argent de départ choisi à l'étape 3, en XLM (`nil` : « None », ou journal d'avant ce choix).
    var startingXLM: Int? = nil

    enum Funding: Codable, Equatable {
        case funded(hash: String)
        case failed(String)
        /// « None » choisi à l'étape 3 : rien n'est envoyé.
        case declined
    }

    var isFunded: Bool {
        if case .funded = funding { return true }
        return false
    }

    /// XLM envoyés (ou à envoyer) ; 50 pour les journaux d'avant le choix du montant.
    var fundingXLM: Int { startingXLM ?? PrepareCardsModel.defaultStartingXLM }

    var fundingText: String {
        switch funding {
        case .funded: "\(fundingXLM) XLM"
        case .failed(let reason): "failed: \(reason)"
        case .declined: "none"
        case nil: ""
        }
    }

    var fundingHash: String {
        if case .funded(let hash) = funding { return hash }
        return ""
    }

    var numberText: String { Self.numberText(number) }

    static func numberText(_ number: Int) -> String { String(format: "#%03d", number) }

    /// Une carte prête ne doit plus jamais être enregistrée.
    var isDone: Bool { status == .prepared || status == .alreadyReady }

    /// Une carte enregistrée attend encore son argent de test (pas essayé, ou raté ; jamais si « None »).
    var needsFunding: Bool {
        guard isDone else { return false }
        switch funding {
        case .funded, .declined: return false
        case .failed, nil: return true
        }
    }

    var statusText: String {
        switch status {
        case .prepared: "prepared"
        case .alreadyReady: "already ready"
        case .pending: "pending"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}

/// Le journal du lot, gardé sur le téléphone (des numéros, des clés publiques, des adresses et des notes : rien de secret).
protocol PreparedCardsStore: AnyObject {
    func load() -> [PreparedCard]
    func save(_ cards: [PreparedCard]) throws
}

/// `Application Support/ChimpDAO/prepared-cards-testnet.json`, protégé tant que l'iPhone est verrouillé.
final class FilePreparedCardsStore: PreparedCardsStore {
    private let url: URL

    init() throws {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "ChimpDAO")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "prepared-cards-testnet.json")
    }

    func load() -> [PreparedCard] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([PreparedCard].self, from: $0) } ?? []
    }

    func save(_ cards: [PreparedCard]) throws {
        try JSONEncoder().encode(cards).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

final class MemoryPreparedCardsStore: PreparedCardsStore {
    private(set) var cards: [PreparedCard]
    init(_ cards: [PreparedCard] = []) { self.cards = cards }
    func load() -> [PreparedCard] { cards }
    func save(_ cards: [PreparedCard]) throws { self.cards = cards }
}

/// « Prepare cards » (Chimp Admin, testnet) : un assistant pas à pas, une carte Infineon après l'autre (refonte demandée
/// par Barth le 2026-10-20).
///
/// 1. **Tap the card** : une Infineon vierge (slot 1 vide, `6A88`, revérifié sur la carte) reçoit sa clé dans ce même tap
///    (exception de Pamphile du 2026-09-29, mode admin, slot 1 vide) ; une carte qui a déjà une clé est simplement lue.
///    Puis son état est lu sur testnet (réseau avant la session NFC suivante). Déjà prête → sa fiche ; PIN déjà défini ou
///    DUOX → refusée, rien n'est écrit.
/// 2. **Which card is it?** : le numéro imprimé (le suivant proposé, jamais un numéro déjà pris) et une note facultative.
/// 3. **Starting money** : None, 50 XLM (par défaut) ou un autre montant (1 à 1000 XLM).
/// 4. **Tap the card again to finish** : la carte signe son enregistrement (`nfc-nft.mint`, attestation, sans PIN), envoyé et
///    payé par la clé admin ; puis, sans tap, l'argent de départ part de la clé admin (rechargée par friendbot) vers le
///    wallet de la carte. Un échec ne fait réessayer que ce qui a échoué.
/// 5. **Card #038 is ready!**
///
/// Jamais de PIN : c'est l'utilisateur qui le choisira à la création de son compte. Une carte déjà enregistrée sur la
/// chaîne n'est jamais réécrite ; le journal est écrit **avant** l'envoi, et une carte en attente est relue sur la chaîne
/// avant tout nouvel envoi : une reprise n'enregistre jamais deux fois la même carte.
@Observable
final class PrepareCardsModel {
    /// Ce que l'assistant sait d'une carte entre le tap 1 et la fin.
    struct Draft: Equatable {
        let card: ChipKeyInfo
        /// Ligne du journal (numéro, note, montant choisis ; statut).
        var entry: PreparedCard
        /// `nil` : la carte est déjà enregistrée sur la chaîne (rien à signer).
        var plan: EnrolmentPlan?
    }

    /// Avancement de l'étape 4.
    enum Finishing: Equatable {
        /// En attente du tap qui signe l'enregistrement.
        case waitingForTap
        case signing
        case registering
        /// L'enregistrement a échoué (rien de sûr sur la chaîne) : retaper, après relecture de la chaîne.
        case registerFailed(String)
        case sendingMoney
        /// Carte enregistrée, l'argent n'est pas parti : seulement l'argent à renvoyer.
        case moneyFailed(String)
    }

    enum Step: Equatable {
        /// Accueil : compteur, « Prepare a card ».
        case home
        /// Étape 1 : la carte n'est pas encore lue (session NFC fermée par l'utilisateur, ou pas encore ouverte).
        case tapCard
        /// Étape 1 : lecture (et génération de la clé si la carte est vierge).
        case reading
        /// Étape 1 : lecture de son état sur testnet.
        case checking
        /// Étape 1 : rien n'a pu être lu (message) ; on peut retaper.
        case readFailed(String)
        /// Étape 1 : PIN déjà défini, DUOX… Rien n'est écrit.
        case cannotPrepare(String)
        /// Étape 1 : carte déjà prête (sa fiche).
        case alreadyReady(PreparedCard)
        /// Étape 2 : numéro et note.
        case identify(Draft)
        /// Étape 3 : argent de départ.
        case startingMoney(Draft)
        /// Étape 4.
        case finishing(Draft, Finishing)
        /// Étape 5.
        case ready(PreparedCard)
    }

    private(set) var step: Step = .home
    private(set) var cards: [PreparedCard]
    /// Numéro proposé à la prochaine carte nouvelle.
    private(set) var nextNumber: Int
    /// Dernier montant choisi à l'étape 3 (`nil` : « None »), proposé à la carte suivante.
    private(set) var lastStartingXLM: Int? = PrepareCardsModel.defaultStartingXLM
    private(set) var saveError: String?
    /// « Send the test money » de la fiche en cours.
    private(set) var isSendingMoney = false
    /// Soldes XLM des wallets lus pour la liste et les fiches (adresse → solde ; absent : pas encore lu).
    private(set) var balances: [String: BalanceRead] = [:]

    enum BalanceRead: Equatable {
        case loading
        case xlm(Decimal)
        case failed
    }

    private let reader: ChipReader
    private let generator: ChipKeyGenerator
    private let signer: ChipSigner
    private let makeService: () throws -> CardEnrolmentService
    private let store: PreparedCardsStore
    /// Argent de départ, depuis la clé admin (`nil` : aucun envoi possible).
    private let funder: TestnetFunding?
    /// Solde XLM d'un wallet de carte (lecture seule).
    private let readXLM: (String) async throws -> Decimal
    private let now: () -> Date

    /// 50 XLM de testnet par carte par défaut (décision de Barth du 2026-10-20) : de quoi faire un envoi tout de suite.
    static let defaultStartingXLM = 50
    /// « Another amount » : de 1 à 1000 XLM.
    static let startingXLMRange = 1...1000

    init(
        reader: ChipReader, generator: ChipKeyGenerator, signer: ChipSigner,
        makeService: @escaping () throws -> CardEnrolmentService, store: PreparedCardsStore, funder: TestnetFunding?,
        readXLM: @escaping (String) async throws -> Decimal,
        now: @escaping () -> Date = { .now }
    ) {
        self.reader = reader
        self.generator = generator
        self.signer = signer
        self.makeService = makeService
        self.store = store
        self.funder = funder
        self.readXLM = readXLM
        self.now = now
        let saved = store.load()
        cards = saved
        nextNumber = (saved.map(\.number).max() ?? 0) + 1
    }

    var isBusy: Bool {
        switch step {
        case .reading, .checking: true
        case .alreadyReady: isSendingMoney
        case .finishing(_, let finishing): finishing == .signing || finishing == .registering || finishing == .sendingMoney
        default: false
        }
    }

    var readyCount: Int { cards.filter(\.isDone).count }

    /// Le numéro est déjà pris par une autre carte (`nil` : libre).
    func cardUsing(_ number: Int, otherThan publicKey: String) -> PreparedCard? {
        cards.first { $0.number == number && $0.publicKey != publicKey }
    }

    // MARK: Accueil

    /// « Prepare a card », « Prepare another card », « Next card » : étape 1, puis la lecture.
    func startCard() async {
        guard !isBusy else { return }
        step = .tapCard
        await scan()
    }

    /// Retour à l'accueil (« Cancel ») : rien n'est écrit. Une clé déjà créée reste sur la carte, qui sera reconnue.
    func backHome() {
        guard !isBusy else { return }
        step = .home
    }

    // MARK: Étape 1

    /// Lit la carte posée (et génère sa clé si elle est vierge), puis lit son état sur testnet.
    func scan() async {
        guard !isBusy else { return }
        step = .reading
        let card: ChipKeyInfo
        do {
            card = try await readOrGenerate()
        } catch ChipError.cancelled {
            step = .tapCard
            return
        } catch {
            step = .readFailed(Self.message(error))
            return
        }
        guard card.kind == .infineon2Go else {
            step = .cannotPrepare("This is a \(card.kind.displayName) card. Only Infineon cards are prepared here.")
            return
        }
        let key = card.publicKey.hex
        if let known = known(key), known.isDone {
            // Déjà enregistrée : jamais réenregistrée.
            showSheet(known)
            return
        }
        step = .checking
        do {
            switch try await makeService().inspect(card) {
            case let .alreadyEnrolled(_, pocket):
                if var entry = known(key) {
                    // Envoi d'une reprise : il était bien parti. Rien à signer ; l'argent reste à envoyer (fiche).
                    entry.wallet = pocket
                    entry.status = .alreadyReady
                    entry.date = now()
                    record(entry)
                    showSheet(entry)
                } else {
                    // Enregistrée ailleurs (le terminal) : on note seulement son numéro.
                    step = .identify(Draft(card: card, entry: newEntry(key: key, wallet: pocket, status: .alreadyReady), plan: nil))
                }
            case .ready(let plan):
                if card.pinActive {
                    // On ne connaît pas son PIN, et on n'en définit jamais.
                    step = .cannotPrepare("This card already has a PIN. A card is prepared without a PIN, so its owner can choose one.")
                    return
                }
                var entry = known(key) ?? newEntry(key: key, wallet: plan.predictedPocket, status: .pending)
                entry.wallet = plan.predictedPocket
                step = .identify(Draft(card: card, entry: entry, plan: plan))
            }
        } catch {
            step = .readFailed(Self.message(error))
        }
    }

    // MARK: Étape 2

    /// « This number is already card #012 » ; `nil` : accepté.
    func numberProblem(_ number: Int?, for draft: Draft) -> String? {
        guard let number, number > 0 else { return "Type the number printed on the card." }
        if let other = cardUsing(number, otherThan: draft.entry.publicKey) {
            return "\(other.numberText) is already used by another card (wallet \(other.wallet.prefix(6))…)."
        }
        return nil
    }

    /// Numéro et note confirmés. Une carte déjà enregistrée va à sa fiche ; les autres à l'étape 3.
    func confirmIdentity(number: Int?, note: String) {
        guard case .identify(var draft) = step, numberProblem(number, for: draft) == nil, let number else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.entry.number = number
        draft.entry.note = trimmed.isEmpty ? nil : trimmed
        if draft.plan == nil {
            draft.entry.date = now()
            record(draft.entry)
            showSheet(draft.entry)
        } else {
            step = .startingMoney(draft)
        }
    }

    // MARK: Étape 3

    /// « Another amount » hors de 1 à 1000 XLM ; `nil` : accepté.
    func amountProblem(_ xlm: Int?) -> String? {
        guard let xlm, Self.startingXLMRange.contains(xlm) else {
            return "Choose between \(Self.startingXLMRange.lowerBound) and \(Self.startingXLMRange.upperBound) XLM."
        }
        return nil
    }

    /// `nil` : « None ».
    func chooseStartingMoney(_ xlm: Int?) {
        guard case .startingMoney(var draft) = step else { return }
        if xlm != nil, amountProblem(xlm) != nil { return }
        lastStartingXLM = xlm
        draft.entry.startingXLM = xlm
        draft.entry.funding = xlm == nil ? .declined : nil
        step = .finishing(draft, .waitingForTap)
    }

    /// Retour de l'étape 3 à l'étape 2.
    func backToIdentity() {
        guard case .startingMoney(let draft) = step else { return }
        step = .identify(draft)
    }

    // MARK: Étape 4

    /// La carte signe son enregistrement (sans PIN), le journal note « en attente », puis l'admin envoie `mint` ; puis
    /// l'argent de départ.
    func signAndRegister() async {
        guard case .finishing(let draft, .waitingForTap) = step, let plan = draft.plan else { return }
        step = .finishing(draft, .signing)
        let signed: ChipSignedDigest
        do {
            signed = try await signer.sign(digest: plan.digest, expectedKey: plan.card.publicKey, pin: nil)
        } catch ChipError.cancelled {
            step = .finishing(draft, .waitingForTap)
            return
        } catch {
            step = .finishing(draft, .registerFailed(Self.message(error)))
            return
        }
        // Noté avant l'envoi : une app coupée maintenant laisse une carte « en attente », relue sur la chaîne au prochain tap.
        var pending = draft.entry
        pending.status = .pending
        pending.date = now()
        record(pending)
        guard saveError == nil else {
            step = .finishing(draft, .registerFailed("The journal couldn't be saved, so nothing was sent. \(saveError ?? "")"))
            return
        }
        step = .finishing(Draft(card: draft.card, entry: pending, plan: plan), .registering)
        do {
            let result = try await makeService().enrol(plan, signed: signed)
            var done = pending
            done.wallet = result.pocket
            done.transactionHash = result.transactionHash
            done.status = .prepared
            done.date = now()
            record(done)
            await sendMoney(Draft(card: draft.card, entry: done, plan: nil))
        } catch {
            // Peut-être parti : le prochain essai relit la chaîne avant tout envoi.
            var failed = pending
            failed.status = .failed("not confirmed: \(Self.message(error))")
            record(failed)
            step = .finishing(Draft(card: draft.card, entry: failed, plan: plan), .registerFailed(Self.message(error)))
        }
    }

    /// « Tap the card again » après un enregistrement raté : la chaîne est relue d'abord. Déjà enregistrée → seulement
    /// l'argent ; sinon un nouveau plan (nonce relu) et le tap.
    func retryRegistration() async {
        guard case .finishing(let draft, .registerFailed) = step else { return }
        step = .finishing(draft, .registering)
        do {
            switch try await makeService().inspect(draft.card) {
            case let .alreadyEnrolled(_, pocket):
                var done = draft.entry
                done.wallet = pocket
                done.status = .alreadyReady
                done.date = now()
                record(done)
                await sendMoney(Draft(card: draft.card, entry: done, plan: nil))
            case .ready(let plan):
                step = .finishing(Draft(card: draft.card, entry: draft.entry, plan: plan), .waitingForTap)
                await signAndRegister()
            }
        } catch {
            step = .finishing(draft, .registerFailed(Self.message(error)))
        }
    }

    /// « Send the test money again » (étape 4) : seulement l'argent, sans tap.
    func retryMoney() async {
        guard case .finishing(let draft, .moneyFailed) = step else { return }
        await sendMoney(draft)
    }

    // MARK: Fiche d'une carte déjà prête

    /// « Send the test money » depuis la fiche : seulement l'argent (50 XLM si aucun montant n'avait été choisi).
    func sendMoneyFromSheet() async {
        guard case .alreadyReady(let entry) = step, entry.needsFunding, let funder, !isSendingMoney else { return }
        isSendingMoney = true
        defer { isSendingMoney = false }
        var funded = entry
        do {
            let hash = try await funder.fund(entry.wallet, units: Self.units(entry.fundingXLM))
            funded.funding = .funded(hash: hash ?? "")
        } catch {
            funded.funding = .failed(Self.message(error))
        }
        record(funded)
        showSheet(funded)
    }

    // MARK: « Check a card »

    /// Fiche d'une carte tapée, en langage simple (onglet Cards de Chimp Admin, 2026-10-22).
    struct CardCheck: Equatable {
        enum Readiness: Equatable {
            /// Enregistrée : prête à donner.
            case ready
            /// A une clé, mais pas encore enregistrée.
            case notPrepared
            /// Vierge : pas encore de clé.
            case blank
            /// A un PIN : quelqu'un l'utilise déjà, ou elle a été réglée ailleurs.
            case hasPIN
            /// Pas une carte Infineon (DUOX…).
            case otherChip(String)
        }

        let readiness: Readiness
        /// Sa ligne de la liste, si cette carte y est.
        var entry: PreparedCard?
        /// Wallet de la carte (connu dès qu'elle a une clé).
        let wallet: String?
        /// Résultat du dernier « Send test money ».
        var sent: SendResult?

        enum SendResult: Equatable {
            case sent(xlm: Int)
            case failed(String)
        }

        var canReceiveMoney: Bool { readiness == .ready && wallet != nil }
    }

    enum CheckState: Equatable {
        case idle
        case reading
        case checking
        case result(CardCheck)
        case failed(String)
    }

    private(set) var check: CheckState = .idle
    private(set) var isSendingCheckMoney = false

    var isChecking: Bool { check == .reading || check == .checking || isSendingCheckMoney }

    /// « Check a card » : lit la carte **sans jamais créer de clé**, retrouve sa ligne dans la liste, lit son état sur
    /// testnet et le solde de son wallet. Rien n'est écrit, ni sur la carte ni sur la chaîne.
    func checkCard() async {
        guard !isChecking, !isBusy else { return }
        check = .reading
        let card: ChipKeyInfo
        do {
            card = try await reader.readKey()
        } catch ChipError.cancelled {
            check = .idle
            return
        } catch ChipError.noKey {
            check = .result(CardCheck(readiness: .blank, entry: nil, wallet: nil))
            return
        } catch {
            check = .failed(Self.message(error))
            return
        }
        guard card.kind == .infineon2Go else {
            check = .result(CardCheck(readiness: .otherChip(card.kind.displayName), entry: nil, wallet: nil))
            return
        }
        let entry = known(card.publicKey.hex)
        check = .checking
        do {
            let result: CardCheck
            switch try await makeService().inspect(card) {
            case let .alreadyEnrolled(_, pocket):
                result = CardCheck(readiness: .ready, entry: entry, wallet: pocket)
            case .ready(let plan):
                result = CardCheck(readiness: card.pinActive ? .hasPIN : .notPrepared, entry: entry, wallet: plan.predictedPocket)
            }
            check = .result(result)
            if result.readiness == .ready, let wallet = result.wallet {
                await loadBalance(of: wallet, force: true)
            }
        } catch {
            check = .failed(Self.message(error))
        }
    }

    /// « Send test money » depuis la fiche : 50 XLM de l'admin vers le wallet d'une carte prête. Notée dans la liste
    /// si la carte y est et n'avait pas encore reçu son argent de départ.
    func sendTestMoneyToCheckedCard() async {
        guard case .result(var result) = check, result.canReceiveMoney, let wallet = result.wallet, let funder,
              !isSendingCheckMoney else { return }
        isSendingCheckMoney = true
        defer { isSendingCheckMoney = false }
        let xlm = Self.defaultStartingXLM
        do {
            let hash = try await funder.fund(wallet, units: Self.units(xlm))
            result.sent = .sent(xlm: xlm)
            if var entry = result.entry, !entry.isFunded {
                entry.startingXLM = xlm
                entry.funding = .funded(hash: hash ?? "")
                record(entry)
                result.entry = entry
            }
        } catch {
            result.sent = .failed(Self.message(error))
        }
        check = .result(result)
        await loadBalance(of: wallet, force: true)
    }

    /// Retour à « Check a card » (une autre carte).
    func resetCheck() {
        guard !isChecking else { return }
        check = .idle
    }

    // MARK: Soldes

    /// Lit le solde XLM d'un wallet (une fois ; `force` pour relire).
    func loadBalance(of wallet: String, force: Bool = false) async {
        if !force, let read = balances[wallet], read != .failed { return }
        balances[wallet] = .loading
        do {
            balances[wallet] = .xlm(try await readXLM(wallet))
        } catch {
            balances[wallet] = .failed
        }
    }

    /// Tous les soldes de la liste, une carte après l'autre.
    func loadAllBalances() async {
        for card in cards.sorted(by: { $0.number < $1.number }) {
            await loadBalance(of: card.wallet)
        }
    }

    // MARK: Journal

    /// CSV du journal, du plus petit numéro au plus grand.
    var csv: String {
        let header = "number,note,public_key,wallet_address,transaction_hash,status,test_money,test_money_hash,date"
        let formatter = ISO8601DateFormatter()
        let rows = cards.sorted { $0.number < $1.number }.map { card in
            [card.numberText, card.note ?? "", card.publicKey, card.wallet, card.transactionHash ?? "", card.statusText,
             card.fundingText, card.fundingHash, formatter.string(from: card.date)]
                .map { Self.csvField($0) }.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func units(_ xlm: Int) -> UInt64 { UInt64(xlm) * 10_000_000 }

    // MARK: Interne

    private func known(_ key: String) -> PreparedCard? { cards.first { $0.publicKey == key } }

    private func newEntry(key: String, wallet: String, status: PreparedCard.Status) -> PreparedCard {
        PreparedCard(number: nextNumber, publicKey: key, wallet: wallet, transactionHash: nil, status: status, date: now())
    }

    private func showSheet(_ entry: PreparedCard) {
        step = .alreadyReady(entry)
    }

    /// Après l'enregistrement, dans le même parcours : l'argent de départ vers le wallet de la carte, depuis la clé admin
    /// (rechargée par friendbot si elle descend sous 2000 XLM). Noté dans le journal. « None » ou déjà parti : rien.
    private func sendMoney(_ draft: Draft) async {
        guard let funder, draft.entry.needsFunding else {
            step = .ready(draft.entry)
            return
        }
        step = .finishing(draft, .sendingMoney)
        var entry = draft.entry
        do {
            let hash = try await funder.fund(entry.wallet, units: Self.units(entry.fundingXLM))
            entry.funding = .funded(hash: hash ?? "")
            record(entry)
            step = .ready(entry)
        } catch {
            entry.funding = .failed(Self.message(error))
            record(entry)
            step = .finishing(Draft(card: draft.card, entry: entry, plan: nil), .moneyFailed(Self.message(error)))
        }
    }

    /// Ajoute ou remplace la ligne de cette carte, puis avance le numéro suivant au-delà du plus grand.
    private func record(_ entry: PreparedCard) {
        if let index = cards.firstIndex(where: { $0.publicKey == entry.publicKey }) {
            cards[index] = entry
        } else {
            cards.append(entry)
        }
        nextNumber = (cards.map(\.number).max() ?? 0) + 1
        do {
            try store.save(cards)
            saveError = nil
        } catch {
            saveError = Self.message(error)
        }
    }

    /// Une Infineon vierge reçoit sa clé (slot 1 vide revérifié sur la carte) ; sinon, la carte est simplement lue.
    private func readOrGenerate() async throws -> ChipKeyInfo {
        do {
            return try await generator.generateKeyOnEmptySlot()
        } catch ChipError.keyAlreadyPresent {
            return try await reader.readKey()
        } catch ChipError.keyGenerationUnsupported {
            // DUOX (clé d'usine) : lue, puis refusée plus haut (Infineon seulement).
            return try await reader.readKey()
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
#endif
