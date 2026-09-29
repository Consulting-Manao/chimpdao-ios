#if CHIMP_ADMIN
import Foundation
import Observation

/// Mode admin, étape B : clé admin (trousseau) et enregistrement (mint) de la carte lue sur testnet.
/// Compilé uniquement en Debug et Testing (drapeau `CHIMP_ADMIN`), jamais en Release.
@Observable
final class AdminKeyModel {
    /// Adresse publique (G…) de la clé enregistrée. La clé secrète n'est jamais gardée ici.
    private(set) var publicKey: String?
    private(set) var errorMessage: String?

    private let store: AdminKeyStore
    let expectedAdmin: String

    init(store: AdminKeyStore, expectedAdmin: String = ChimpNetworkConfig.testnet.contracts.admin) {
        self.store = store
        self.expectedAdmin = expectedAdmin
        do {
            publicKey = try store.publicKey()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
    }

    var hasKey: Bool { publicKey != nil }
    /// La clé saisie n'est pas l'admin connu des contrats : `mint` échouera (avertissement, pas de blocage).
    var isUnexpectedAdmin: Bool { publicKey.map { $0 != expectedAdmin } ?? false }

    /// Enregistre la clé. Le texte saisi n'est ni gardé ni journalisé : l'appelant vide son champ ensuite.
    func save(_ secretSeed: String) {
        do {
            publicKey = try store.save(secretSeed: secretSeed)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save the key."
        }
    }

    func erase() {
        do {
            try store.erase()
            publicKey = nil
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't erase the key."
        }
    }
}

@Observable
final class AdminEnrolModel {
    enum State: Equatable {
        case idle
        case checking
        case alreadyEnrolled(tokenID: UInt32, pocket: String)
        /// Prête : on montre ce que la carte va signer avant le tap 2 (règle 8).
        case ready(EnrolmentPlan)
        case signing(EnrolmentPlan)
        case submitting(EnrolmentPlan)
        case enrolled(EnrolmentResult)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let makeService: () throws -> CardEnrolmentService
    private let signer: ChipSigner

    init(makeService: @escaping () throws -> CardEnrolmentService, signer: ChipSigner) {
        self.makeService = makeService
        self.signer = signer
    }

    var isBusy: Bool {
        switch state {
        case .checking, .signing, .submitting: true
        default: false
        }
    }

    func reset() { state = .idle }

    /// Après le tap 1 : état de la carte sur testnet et préparation du digest (réseau avant NFC, règle 9).
    func check(_ card: ChipKeyInfo) async {
        guard !isBusy else { return }
        state = .checking
        do {
            switch try await makeService().inspect(card) {
            case .alreadyEnrolled(let tokenID, let pocket): state = .alreadyEnrolled(tokenID: tokenID, pocket: pocket)
            case .ready(let plan): state = .ready(plan)
            }
        } catch {
            state = .failed(Self.message(error))
        }
    }

    /// Tap 2 : la carte signe le digest (même carte vérifiée par sa clé), puis la transaction part, signée par l'admin.
    func enrol(pin: String?) async {
        guard case .ready(let plan) = state else { return }
        state = .signing(plan)
        do {
            let signed = try await signer.sign(digest: plan.digest, expectedKey: plan.card.publicKey, pin: pin)
            state = .submitting(plan)
            state = .enrolled(try await makeService().enrol(plan, signed: signed))
        } catch ChipError.cancelled {
            // Rien n'a été signé ni envoyé : on revient à l'écran de vérification.
            state = .ready(plan)
        } catch {
            state = .failed(Self.message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
#endif
