import CoreNFC
import Foundation
import Observation

/// La carte à retirer, telle que la page de la carte (B3) la connaît.
struct RemovalTarget: Equatable {
    let key: ChipPublicKey
    let chip: ChipKind
    let name: String
    let color: ChimpCardColor
    /// « 0007 ».
    let number: String
    /// Ce qu'il y a sur son wallet, déjà formaté (« $62.50 »).
    let walletAmount: String
    let walletIsEmpty: Bool
    /// Ce qu'il y a sur Main, déjà formaté (G7 « SAFE · Main · $1,320.00 »).
    let mainAmount: String
}

/// Un problème avant ou pendant le tap, avec les détails techniques pour le support.
struct RemoveCardProblem: Equatable {
    enum Kind: Equatable {
        /// Erreur NFC (messages d'A2).
        case card(OnboardingProblem.Kind)
        /// Retirer (G6) : une autre carte a été tapée ; seule la carte retirée signe son départ.
        case notTheCard
        /// Carte perdue (G7) : c'est la carte perdue elle-même qui a été tapée.
        case isTheLostCard
        /// Une carte qui n'est pas du compte.
        case notAMember
        /// Stellar injoignable avant le tap (simulation).
        case network
        /// Un paiement signé attend encore son issue : rien d'autre ne part tant qu'il n'est pas tranché.
        case pendingPayment
    }

    let kind: Kind
    let technicalDetails: String
}

/// ViewModel de G6 (retirer une carte) et G7 (carte perdue) : `account.remove_card(clé)` en **ordre 2** (« simuler, puis
/// signer »), portage de `removeCard` (`chain/provisioning.ts`) et `startRemoveCard` (`useCardCeremonies.ts`) pour la
/// partie Stellar. G6 : la carte retirée signe elle-même (terminal). G7 : une **autre** carte du compte signe (le contrat
/// accepte n'importe laquelle ; absent du terminal, DESIGN_NOTES §13). Dernière carte (G5) : refusée avant tout tap.
/// Ne fait aucune crypto : `RemoveCardService` (chaîne) et `ChipSigner` (carte).
@Observable
final class RemoveCardModel {
    enum Mode: Equatable {
        /// G6 · Remove a card.
        case remove
        /// G7 · I lost a card.
        case lost

        var signer: CardMembershipClient.RemovalSigner { self == .remove ? .theCardItself : .anotherCard }
    }

    enum Screen: Equatable {
        /// Revue (G6 ou G7) ; le PIN puis le tap sont des feuilles posées dessus.
        case review
        /// Envoi et confirmation.
        case removing
        /// C'est fait.
        case done
    }

    enum Step: Int, CaseIterable, Comparable {
        case removing
        case confirming

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Phase: Equatable {
        case running(Step)
        case failed(Step, CreationProblem)
    }

    enum RemoveCardError: Error, Equatable, LocalizedError {
        case signatureExpired
        case notConfirmedOnChain

        var errorDescription: String? {
            switch self {
            case .signatureExpired: "The card's signature has expired. A new tap is needed."
            case .notConfirmedOnChain: "Sent, but the account still lists the card."
            }
        }
    }

    static let pinLength = 4

    let mode: Mode
    let account: String
    let target: RemovalTarget

    private(set) var screen = Screen.review
    private(set) var phase = Phase.running(.removing)
    /// G5 : le compte n'a qu'une carte, elle ne peut pas partir.
    var isShowingLastCard = false

    var pin = ""
    var pinState = ChimpPinState.entering
    var isShowingPINSheet = false
    var isShowingTapSheet = false
    private(set) var isBusy = false
    private(set) var problem: RemoveCardProblem?
    /// Nom local de la carte qui a signé (G7).
    private(set) var signerName: String?

    private let session: AppSession
    private let signer: ChipSigner
    private let service: RemoveCardService
    private var prepared: CardMembershipClient.PreparedRemoveCard?
    private var signature: CardSignatures?
    private var isRunning = false

    init(mode: Mode, account: String, target: RemovalTarget, session: AppSession, signer: ChipSigner, service: RemoveCardService) {
        self.mode = mode
        self.account = account
        self.target = target
        self.session = session
        self.signer = signer
        self.service = service
    }

    // MARK: Revue

    /// Prénom du compte (« From Léo's account »).
    var accountOwnerName: String? { session.wallet.firstName }

    /// Un PIN à demander avant le tap ? G6 : la carte retirée, si c'est une Infineon. G7 : au moins une autre carte du
    /// compte en a un (le PIN n'est envoyé qu'à une carte qui en a un actif), comme un envoi depuis Main.
    var usesPIN: Bool {
        switch mode {
        case .remove:
            return target.chip == .infineon2Go
        case .lost:
            let others = session.wallet.account?.cards.filter { $0.publicKey != target.key.hex } ?? []
            return others.isEmpty || others.contains { $0.chip != ChipKind.duox.rawValue }
        }
    }

    /// « Looks good » (G6) ou « Remove the {carte} card » (G7) : dernière carte ? (G5) Sinon le PIN d'abord s'il en faut un
    /// (« PIN puis tap »), puis la feuille du tap. Rien n'est lu ni signé tant que la revue n'est pas acceptée (règle 8).
    func start() async {
        guard !isBusy else { return }
        problem = nil
        if session.wallet.pendingSend != nil {
            problem = RemoveCardProblem(kind: .pendingPayment, technicalDetails: "pendingSend")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let members = try await service.members(of: account)
            if members.contains(target.key), members.count <= 1 {
                isShowingLastCard = true
                return
            }
        } catch {
            problem = RemoveCardProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        if usesPIN, pin.count != Self.pinLength {
            pin = ""
            isShowingPINSheet = true
        } else {
            isShowingTapSheet = true
        }
    }

    func pinEntered(_ value: String) {
        guard value.count == Self.pinLength else { return }
        pin = value
        isShowingPINSheet = false
        isShowingTapSheet = true
    }

    func cancelSigning() {
        guard !isBusy else { return }
        pin = ""
        pinState = .entering
        isShowingPINSheet = false
        isShowingTapSheet = false
    }

    // MARK: Tap

    /// `remove_card` préparé (réseau, avant la session NFC ; refait s'il arrive à expiration), puis le tap : la clé de la
    /// carte est comparée **avant** tout PIN ; une carte qui n'a pas le droit de signer ne reçoit rien d'autre.
    func scan() async {
        guard !isBusy else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            if let current = prepared, try await !service.needsRefresh(current) {
                // Encore valable.
            } else {
                prepared = try await service.prepareRemoveCard(account: account, card: target.key, signer: mode.signer)
            }
        } catch CardMembershipClient.MembershipError.lastCard {
            isShowingTapSheet = false
            isShowingLastCard = true
            return
        } catch CardMembershipClient.MembershipError.notInAccount {
            // Déjà retirée (ailleurs, ou un essai précédent) : la relecture le confirme, le téléphone l'oublie.
            isShowingTapSheet = false
            screen = .removing
            await run()
            return
        } catch {
            problem = RemoveCardProblem(kind: .network, technicalDetails: OnboardingModel.details(error))
            return
        }
        guard let prepared else { return }
        do {
            let signed = try await signer.sign(digests: [prepared.digest], acceptedKeys: prepared.acceptedKeys, pin: pin.isEmpty ? nil : pin)
            signature = signed
            signerName = session.wallet.account?.cards.first { $0.publicKey == signed.card.publicKey.hex }?.name
            pin = ""
            pinState = .entering
            isShowingTapSheet = false
            screen = .removing
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
            // Rien n'a été envoyé à cette carte après la lecture de sa clé (ni PIN, ni signature).
            let kind: RemoveCardProblem.Kind = switch mode {
            case .remove: .notTheCard
            case .lost: tapped == target.key ? .isTheLostCard : .notAMember
            }
            problem = RemoveCardProblem(kind: kind, technicalDetails: tapped.hex)
        } catch let error as ChipError {
            problem = RemoveCardProblem(kind: .card(AccountSetupModel.problemKind(for: error)), technicalDetails: OnboardingModel.details(error))
        } catch {
            problem = RemoveCardProblem(kind: .card(.readFailed), technicalDetails: OnboardingModel.details(error))
        }
    }

    private func pinFailed(_ state: ChimpPinState) {
        pin = ""
        pinState = state
        isShowingTapSheet = false
        isShowingPINSheet = true
    }

    // MARK: Envoi et confirmation

    /// `remove_card` (s'il le faut : la carte est encore listée), puis relecture (`has_card` faux), puis le téléphone
    /// l'oublie. Relancé par « Try again » / « Check again » : rien n'est envoyé deux fois.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        var step = Step.removing
        do {
            phase = .running(.removing)
            if try await service.hasCard(account: account, publicKey: target.key) {
                guard let prepared, let signature else { throw RemoveCardError.signatureExpired }
                if try await service.needsRefresh(prepared) { throw RemoveCardError.signatureExpired }
                _ = try await service.submitRemoveCard(prepared, signed: signature)
            }
            step = .confirming
            phase = .running(.confirming)
            guard try await !service.hasCard(account: account, publicKey: target.key) else {
                throw RemoveCardError.notConfirmedOnChain
            }
        } catch CardMembershipClient.MembershipError.lastCard {
            screen = .review
            isShowingLastCard = true
            return
        } catch {
            phase = .failed(step, Self.problem(for: error))
            return
        }
        do {
            try session.removeCard(target.key.hex, account: account)
            screen = .done
        } catch {
            phase = .failed(.confirming, CreationProblem(kind: .saveFailed, technicalDetails: OnboardingModel.details(error)))
        }
    }

    static func problem(for error: Error) -> CreationProblem {
        let details = OnboardingModel.details(error)
        switch error {
        case RemoveCardError.signatureExpired: return CreationProblem(kind: .signatureExpired, technicalDetails: details)
        case RemoveCardError.notConfirmedOnChain: return CreationProblem(kind: .notConfirmed, technicalDetails: details)
        default: return CreationProblem.from(error)
        }
    }

    /// Échec qui demande un nouveau tap (signature expirée ou refusée) : retour à la revue, nouvelle préparation.
    func newTapAfterFailure() {
        guard case .failed(_, let problem) = phase, problem.needsNewTap else { return }
        prepared = nil
        signature = nil
        screen = .review
    }

    func retry() {
        guard case .failed(_, let problem) = phase, !problem.needsNewTap else { return }
        Task { await run() }
    }

    /// Le retour est bloqué pendant la signature et l'envoi.
    var blocksLeaving: Bool { isBusy || isRunning || (screen == .removing && !isFailed) }

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

extension RemoveCardModel {
    /// La vraie carte (Core NFC) et le réseau de la session. Sur un appareil sans NFC (simulateur), les builds Debug et Testing prennent
    /// une carte et une chaîne factices, sur une copie en mémoire de la session (rien n'est écrit dans le vrai fichier).
    static func live(mode: Mode, account: String, target: RemovalTarget, members: [ChipPublicKey], session: AppSession) -> RemoveCardModel {
        #if DESIGN_CATALOG
        if !NFCTagReaderSession.readingAvailable {
            let scratch = AppSession(store: InMemoryLocalWalletStore(session.wallet), config: session.config)
            return RemoveCardModel(
                mode: mode, account: account, target: target, session: scratch,
                signer: MockChipSigner(), service: MockRemoveCardService(members: members)
            )
        }
        #endif
        return RemoveCardModel(
            mode: mode, account: account, target: target, session: session,
            signer: NFCChipSigner(), service: ChainRemoveCardService(config: session.config)
        )
    }
}
