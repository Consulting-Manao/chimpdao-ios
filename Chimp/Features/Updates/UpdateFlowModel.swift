import CoreNFC
import Foundation
import Observation

/// Un problème avant ou pendant le tap, avec les détails techniques pour le support.
struct UpdateProblem: Equatable {
    enum Kind: Equatable {
        /// Erreur NFC (messages d'A2).
        case card(OnboardingProblem.Kind)
        /// Une carte qui ne peut pas signer cette mise à jour.
        case cardNotAccepted
        /// Stellar injoignable avant le tap.
        case network
        /// Un paiement signé attend encore son issue : rien d'autre ne se signe tant qu'il n'est pas tranché.
        case pendingPayment
        /// Refus avant tout tap (`UpdateError`) : suit la flotte, version absente ou archivée, factory inconnu.
        case refused(UpdateError)
    }

    let kind: Kind
    let technicalDetails: String
}

/// Une mise à jour du code (Réglages › Updates) : vérification (ce qui sera signé, règle 8), PIN, tap, envoi, relecture.
/// Portage de la cérémonie du terminal (`runUpdate`, `checkUpdate`) : rien n'est demandé si c'est déjà à jour. Ne fait
/// aucune crypto : `UpdatesService` (chaîne) et `ChipSigner` (carte).
@Observable
final class UpdateFlowModel {
    enum Screen: Equatable {
        /// Vérification ; le PIN puis le tap sont des feuilles posées dessus.
        case review
        /// Envoi et relecture.
        case updating
        /// C'est fait (ou c'était déjà fait : rien n'a été signé).
        case done(UpdateOutcome)
    }

    enum Phase: Equatable {
        case running
        /// Pas abouti : `canCheckAgain` relit la chaîne (arrivée malgré l'erreur ?), sinon un nouveau tap.
        case failed(message: String, details: String)
    }

    static let pinLength = 4

    let row: UpdatesModel.Row
    let target: UpdateTarget

    private(set) var screen = Screen.review
    private(set) var phase = Phase.running
    var pin = ""
    var pinState = ChimpPinState.entering
    var isShowingPINSheet = false
    var isShowingTapSheet = false
    private(set) var isBusy = false
    /// La signature se prépare encore (réseau, avant la session NFC) : « Getting ready… ».
    private(set) var isGettingReady = false
    private(set) var scanAttempts = 0
    private(set) var problem: UpdateProblem?
    /// La route et le factory, connus après la préparation (montrés en entier sur la vérification).
    private(set) var prepared: PreparedUpdate?
    /// Nom local de la carte qui a signé.
    private(set) var signerName: String?

    private let session: AppSession
    private let signer: ChipSigner
    private let service: UpdatesService
    private var signature: CardSignatures?
    private var isRunning = false

    init(row: UpdatesModel.Row, target: UpdateTarget, session: AppSession, signer: ChipSigner, service: UpdatesService) {
        self.row = row
        self.target = target
        self.session = session
        self.signer = signer
        self.service = service
    }

    // MARK: Vérification

    /// Le factory dont le compte recevra ses mises à jour : celui de `Config/`, montré **en entier** (CLIENT-INTEGRATION
    /// §6.6, « the one trust point »).
    var factory: String { session.config.contracts.factory }

    /// Les cartes qui peuvent signer : toutes celles du compte pour le Main account, la seule carte pour son wallet.
    var acceptedKeys: [ChipPublicKey] {
        let cards = session.wallet.account?.cards ?? []
        let keys: [String] = switch row.subject {
        case .account: cards.map(\.publicKey)
        case .card(let key, _, _, _, _): [key]
        }
        return keys.compactMap { try? ChipPublicKey(Data(hex: $0) ?? Data()) }
    }

    /// Un PIN à demander avant le tap ? Le wallet d'une carte : si c'est une Infineon. Le Main account : si l'une de ses
    /// cartes en a un (le PIN n'est envoyé qu'à une carte qui en a un actif), comme un envoi depuis Main.
    var usesPIN: Bool {
        switch row.subject {
        case .account:
            let cards = session.wallet.account?.cards ?? []
            return cards.isEmpty || cards.contains { $0.chip != ChipKind.duox.rawValue }
        case .card(_, _, _, _, let chip):
            return chip != .duox
        }
    }

    /// « Update » : relit la chaîne (déjà fait ailleurs : rien à signer), prépare l'autorisation (réseau avant la session
    /// NFC, règle 9), puis le PIN s'il en faut un, puis le tap.
    func start() async {
        guard !isBusy else { return }
        problem = nil
        if session.wallet.pendingSend != nil {
            problem = UpdateProblem(kind: .pendingPayment, technicalDetails: "pendingSend")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            if try await service.check(target) == .current {
                screen = .done(.alreadyCurrent)
                return
            }
            prepared = try await service.prepare(target, acceptedKeys: acceptedKeys)
        } catch let error as UpdateError {
            problem = UpdateProblem(kind: .refused(error), technicalDetails: OnboardingModel.details(error))
            return
        } catch {
            problem = UpdateProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        if usesPIN, pin.count != Self.pinLength {
            pin = ""
            isShowingPINSheet = true
        } else {
            autoScan()
        }
    }

    func pinEntered(_ value: String) {
        guard value.count == Self.pinLength else { return }
        pin = value
        isShowingPINSheet = false
        autoScan()
    }

    private func autoScan() {
        isShowingTapSheet = true
        let attempts = scanAttempts
        AutoScan.start(when: { [weak self] in self?.isShowingTapSheet == true && self?.scanAttempts == attempts }) { [weak self] in
            await self?.scan()
        }
    }

    func cancelSigning() {
        guard !isBusy else { return }
        pin = ""
        pinState = .entering
        isShowingPINSheet = false
        isShowingTapSheet = false
    }

    // MARK: Tap

    /// L'autorisation (refaite si elle arrive à expiration), puis le tap : la clé de la carte est comparée **avant** tout
    /// PIN ; une carte qui n'a pas le droit de signer ne reçoit rien d'autre.
    func scan() async {
        guard !isBusy else { return }
        scanAttempts += 1
        isBusy = true
        problem = nil
        isGettingReady = true
        defer {
            isBusy = false
            isGettingReady = false
        }
        do {
            if let current = prepared, try await !service.needsRefresh(current) {
                // Encore valable.
            } else {
                prepared = try await service.prepare(target, acceptedKeys: acceptedKeys)
            }
        } catch let error as UpdateError {
            problem = UpdateProblem(kind: .refused(error), technicalDetails: OnboardingModel.details(error))
            return
        } catch {
            problem = UpdateProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        guard let prepared else { return }
        isGettingReady = false
        do {
            let signed = try await signer.sign(digests: [prepared.call.digest], acceptedKeys: prepared.call.acceptedKeys, pin: pin.isEmpty ? nil : pin)
            signature = signed
            signerName = session.wallet.account?.cards.first { $0.publicKey == signed.card.publicKey.hex }?.name
            pin = ""
            pinState = .entering
            isShowingTapSheet = false
            screen = .updating
            await run()
        } catch ChipError.cancelled {
            return
        } catch ChipError.wrongPIN(let retriesLeft) {
            pinFailed(.wrong(triesLeft: retriesLeft))
        } catch ChipError.pinLocked {
            pinFailed(.blocked)
        } catch ChipError.pinRequired {
            pinFailed(.entering)
        } catch ChipError.cardNotAccepted(let tapped) {
            problem = UpdateProblem(kind: .cardNotAccepted, technicalDetails: tapped.hex)
        } catch let error as ChipError {
            problem = UpdateProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = UpdateProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    private func pinFailed(_ state: ChimpPinState) {
        pin = ""
        pinState = state
        isShowingTapSheet = false
        isShowingPINSheet = true
    }

    // MARK: Envoi et relecture

    /// Envoi de l'autorisation signée, puis relecture du contrat (dans `UpdatesService.send`).
    func run() async {
        guard !isRunning, let prepared, let signature else { return }
        isRunning = true
        defer { isRunning = false }
        phase = .running
        do {
            let outcome = try await service.send(prepared, signed: signature)
            screen = .done(outcome)
        } catch {
            phase = .failed(message: Self.message(for: error), details: OnboardingModel.details(error))
        }
    }

    /// « Check again » : relit la chaîne. Arrivée malgré l'erreur : c'est fait. Sinon, retour à la vérification pour un
    /// nouveau tap (l'autorisation déjà signée n'est jamais renvoyée deux fois).
    func checkAgain() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            if try await service.check(target) == .current {
                screen = .done(.updated(transactionHash: nil))
            } else {
                prepared = nil
                signature = nil
                phase = .running
                screen = .review
            }
        } catch {
            phase = .failed(message: String(localized: "I couldn't reach Stellar to check."), details: OnboardingModel.details(error))
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case UpdateError.unverified: String(localized: "Sent, but your account doesn't run the new version yet. It can take a few seconds.")
        case let error as UpdateError: error.localizedDescription
        case StellarError.notConfirmed, StellarError.sendUnanswered:
            String(localized: "Stellar didn't answer in time. It may still go through.")
        default: String(localized: "The update didn't go through. Nothing changed.")
        }
    }

    /// Le retour est bloqué pendant la signature et l'envoi.
    var blocksLeaving: Bool { isBusy || isRunning || (screen == .updating && !isFailed) }

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

extension UpdateFlowModel {
    /// La vraie carte (Core NFC) et le réseau de la session. Sur un appareil sans NFC (simulateur), les builds Debug et
    /// Testing prennent une carte factice, sur le même service (pour la démonstration du catalogue).
    static func live(row: UpdatesModel.Row, target: UpdateTarget, session: AppSession, service: UpdatesService) -> UpdateFlowModel {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable {
            return UpdateFlowModel(row: row, target: target, session: session, signer: MockChipSigner(), service: service)
        }
        #endif
        return UpdateFlowModel(row: row, target: target, session: session, signer: NFCChipSigner(), service: service)
    }
}
