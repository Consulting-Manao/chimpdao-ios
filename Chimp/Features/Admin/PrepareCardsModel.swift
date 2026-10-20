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
    /// Numéro du lot (#001 à #195).
    let number: Int
    /// Clé publique de la puce, en hexadécimal (130 caractères).
    let publicKey: String
    /// Adresse du wallet de la carte (Pocket), connue avant même l'enregistrement.
    var wallet: String
    var transactionHash: String?
    var status: Status
    var date: Date

    var numberText: String { Self.numberText(number) }

    static func numberText(_ number: Int) -> String { String(format: "#%03d", number) }

    /// Une carte prête ne doit plus jamais être enregistrée.
    var isDone: Bool { status == .prepared || status == .alreadyReady }

    var statusText: String {
        switch status {
        case .prepared: "prepared"
        case .alreadyReady: "already ready"
        case .pending: "pending"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}

/// Le journal du lot, gardé sur le téléphone (des numéros, des clés publiques et des adresses : rien de secret).
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

/// « Prepare cards » (Chimp Admin, testnet) : préparer un lot de cartes Infineon à la suite, sans revenir en arrière.
///
/// Pour chaque carte, deux taps :
/// 1. **lecture** : une Infineon vierge (slot 1 vide, `6A88`, revérifié sur la carte) reçoit sa clé dans la même session
///    (exception de Pamphile du 2026-09-29, mode admin, slot 1 vide) ; une carte qui a déjà une clé est simplement lue ;
/// 2. **signature** : après la lecture de l'état sur testnet (réseau avant la session NFC), la carte signe son
///    enregistrement (`nfc-nft.mint`, attestation), envoyé et payé par la clé admin.
///
/// Jamais de PIN : c'est l'utilisateur qui le choisira à la création de son compte (une carte qui en a déjà un est mise de
/// côté). Une carte déjà enregistrée sur la chaîne n'est jamais réécrite ; le journal est écrit **avant** l'envoi, et
/// une carte en attente est relue sur la chaîne au tap suivant : une reprise n'enregistre jamais deux fois la même carte.
@Observable
final class PrepareCardsModel {
    enum Step: Equatable {
        case idle
        /// Tap 1 en cours (lecture ou génération de la clé).
        case reading
        /// Lecture de l'état sur testnet.
        case checking(String)
        /// Prête : la carte doit signer son enregistrement (tap 2). Ce qu'elle signe est affiché (règle 8).
        case readyToSign(PreparedCard, EnrolmentPlan)
        case signing(PreparedCard)
        case submitting(PreparedCard)
        /// Dernière carte traitée (prête, déjà prête, ou mise de côté).
        case done(PreparedCard)
        /// Rien n'a été écrit pour cette carte (lecture, refus) : message.
        case problem(String)
    }

    private(set) var step: Step = .idle
    private(set) var cards: [PreparedCard]
    /// Numéro donné à la prochaine carte nouvelle ; modifiable (saisi) avant le tap.
    var nextNumber: Int
    private(set) var saveError: String?

    private let reader: ChipReader
    private let generator: ChipKeyGenerator
    private let signer: ChipSigner
    private let makeService: () throws -> CardEnrolmentService
    private let store: PreparedCardsStore
    private let now: () -> Date

    init(
        reader: ChipReader, generator: ChipKeyGenerator, signer: ChipSigner,
        makeService: @escaping () throws -> CardEnrolmentService, store: PreparedCardsStore, now: @escaping () -> Date = { .now }
    ) {
        self.reader = reader
        self.generator = generator
        self.signer = signer
        self.makeService = makeService
        self.store = store
        self.now = now
        let saved = store.load()
        cards = saved
        nextNumber = (saved.map(\.number).max() ?? 0) + 1
    }

    var isBusy: Bool {
        switch step {
        case .reading, .checking, .signing, .submitting: true
        default: false
        }
    }

    var preparedCount: Int { cards.filter(\.isDone).count }
    var failedCount: Int { cards.filter { if case .failed = $0.status { true } else { false } }.count }

    /// Le numéro demandé est déjà pris par une autre carte.
    func numberIsTaken(_ number: Int, by publicKey: String? = nil) -> Bool {
        cards.contains { $0.number == number && $0.publicKey != publicKey }
    }

    // MARK: Tap 1

    /// Lit la carte posée (et génère sa clé si elle est vierge), puis lit son état sur testnet.
    func scan() async {
        guard !isBusy else { return }
        step = .reading
        let card: ChipKeyInfo
        do {
            card = try await readOrGenerate()
        } catch ChipError.cancelled {
            step = .idle
            return
        } catch {
            step = .problem(Self.message(error))
            return
        }
        guard card.kind == .infineon2Go else {
            step = .problem("This is not an Infineon card (\(card.kind.displayName)). Only Infineon cards are prepared.")
            return
        }
        let key = card.publicKey.hex
        if let known = cards.first(where: { $0.publicKey == key }), known.isDone {
            step = .done(known)
            return
        }
        let number = cards.first { $0.publicKey == key }?.number ?? nextNumber
        guard !numberIsTaken(number, by: key) else {
            step = .problem("\(PreparedCard.numberText(number)) is already used by another card. Change the next number.")
            return
        }
        step = .checking(PreparedCard.numberText(number))
        do {
            switch try await makeService().inspect(card) {
            case let .alreadyEnrolled(_, pocket):
                // Déjà enregistrée (avant ce lot, ou envoi d'une reprise) : rien à écrire.
                finish(PreparedCard(number: number, publicKey: key, wallet: pocket, transactionHash: known(key)?.transactionHash,
                                    status: .alreadyReady, date: now()))
            case .ready(let plan):
                if card.pinActive {
                    // On ne connaît pas son PIN, et on n'en définit jamais : mise de côté.
                    finish(PreparedCard(number: number, publicKey: key, wallet: plan.predictedPocket, transactionHash: nil,
                                        status: .failed("the card already has a PIN"), date: now()))
                    return
                }
                step = .readyToSign(
                    PreparedCard(number: number, publicKey: key, wallet: plan.predictedPocket, transactionHash: nil, status: .pending, date: now()),
                    plan
                )
            }
        } catch {
            step = .problem(Self.message(error))
        }
    }

    // MARK: Tap 2

    /// La carte signe son enregistrement (sans PIN), le journal note « en attente », puis l'admin envoie `mint`.
    func signAndRegister() async {
        guard case let .readyToSign(entry, plan) = step else { return }
        step = .signing(entry)
        let signed: ChipSignedDigest
        do {
            signed = try await signer.sign(digest: plan.digest, expectedKey: plan.card.publicKey, pin: nil)
        } catch ChipError.cancelled {
            step = .readyToSign(entry, plan)
            return
        } catch {
            record(failed(entry, Self.message(error)))
            step = .problem(Self.message(error))
            return
        }
        // Noté avant l'envoi : une app coupée maintenant laisse une carte « en attente », relue sur la chaîne au prochain tap.
        record(entry)
        guard saveError == nil else {
            step = .problem("The journal couldn't be saved, so nothing was sent. \(saveError ?? "")")
            return
        }
        step = .submitting(entry)
        do {
            let result = try await makeService().enrol(plan, signed: signed)
            var done = entry
            done.wallet = result.pocket
            done.transactionHash = result.transactionHash
            done.status = .prepared
            done.date = now()
            finish(done)
        } catch {
            // Peut-être parti : on garde « en attente » ; le prochain tap relira la chaîne avant tout envoi.
            var pending = entry
            pending.status = .failed("not confirmed: \(Self.message(error)) (tap the card again to check)")
            record(pending)
            step = .problem(Self.message(error))
        }
    }

    /// « Skip this card » : on passe à la suivante sans rien écrire.
    func skip() {
        guard !isBusy else { return }
        step = .idle
    }

    // MARK: Journal

    /// CSV du journal : numéro, clé publique, wallet, hash, statut, date (ISO 8601), du plus petit numéro au plus grand.
    var csv: String {
        let header = "number,public_key,wallet_address,transaction_hash,status,date"
        let formatter = ISO8601DateFormatter()
        let rows = cards.sorted { $0.number < $1.number }.map { card in
            [card.numberText, card.publicKey, card.wallet, card.transactionHash ?? "", card.statusText, formatter.string(from: card.date)]
                .map(Self.csvField).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func known(_ key: String) -> PreparedCard? { cards.first { $0.publicKey == key } }

    private func failed(_ entry: PreparedCard, _ reason: String) -> PreparedCard {
        var copy = entry
        copy.status = .failed(reason)
        copy.date = now()
        return copy
    }

    private func finish(_ entry: PreparedCard) {
        record(entry)
        step = .done(entry)
    }

    /// Ajoute ou remplace la ligne de cette carte, puis avance le numéro suivant au-delà du plus grand.
    private func record(_ entry: PreparedCard) {
        if let index = cards.firstIndex(where: { $0.publicKey == entry.publicKey }) {
            cards[index] = entry
        } else {
            cards.append(entry)
        }
        nextNumber = max(nextNumber, entry.number + 1)
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
