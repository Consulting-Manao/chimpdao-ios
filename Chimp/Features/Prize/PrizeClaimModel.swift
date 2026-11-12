import Foundation
import Observation

/// ViewModel de « Somebody likes you! » (carte partenaire, D5) : le cadeau, la vérification, le PIN, **un** tap (deux
/// signatures enchaînées), puis les mêmes états d'envoi qu'Envoyer, Swap et le vault.
///
/// Mêmes garanties que le vault (`VaultFlowModel`, dont la machine à états est reprise, réduite) : une seule préparation et
/// une seule signature à la fois, rien n'interrompt la signature ni l'envoi (`isSigningLocked`), l'issue incertaine est
/// gardée sur le téléphone **dès le retour de la carte** et revérifiée (« Check again »), « Nothing was moved » seulement
/// quand c'est certain. Ordre « PIN puis tap » toujours (demande de Barth : « vérification, PIN et tap »). Ne fait aucun
/// calcul crypto et ne connaît que le protocole `PrizeService`.
@Observable
final class PrizeClaimModel {
    /// Préparation ratée (avant la carte) : rien n'a été signé.
    enum PreparationIssue: Equatable {
        /// Le coffre a changé depuis la vérification : la vérification montre le nouveau montant, à confirmer.
        case amountChanged
        /// Le coffre est vide : déjà ouvert (peut-être depuis un autre téléphone).
        case alreadyOpened
        /// Le wallet de la carte ne détient plus le NFT de la carte.
        case notOwner
        /// La carte n'est plus dans le compte.
        case unknownCard
        case other
    }

    // MARK: État

    private(set) var gift: PrizeGift?
    /// L'écran « Check it over », poussé par-dessus « Somebody likes you! ».
    var isReviewPresented = false
    private(set) var stage: PrizeStage = .idle
    /// PIN tapé : gardé en mémoire le temps de la signature seulement, jamais enregistré ni journalisé.
    var pin = ""
    var pinState: ChimpPinState = .entering
    private var prepared: PreparedPrizeClaim?
    private var preparation: Task<PreparedPrizeClaim, Error>?
    private(set) var signed: CardSignatures?
    private(set) var preparationIssue: PreparationIssue?
    private(set) var tapProblem: TapProblem?
    private(set) var isGettingReady = false
    private(set) var technicalDetails: String?

    private(set) var pending: PendingSend?
    private(set) var resumedPending = false
    /// Une autre opération attend son issue (un envoi, un swap, le vault) : rien ne se signe avant.
    private(set) var blockedByPendingPayment = false
    private(set) var pendingSaveFailed = false
    private(set) var failureReason: SendFailureReason?
    private var waitTask: Task<Void, Never>?
    let pinLength = 4

    private let service: PrizeService
    private var hasLoaded = false
    var onExit: (() -> Void)?

    /// `gift` : `nil` pour reprendre un retrait en attente (« Check again »).
    init(service: PrizeService, gift: PrizeGift?) {
        self.service = service
        self.gift = gift
    }

    // MARK: Chargement

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let waiting = service.pendingSend else { return }
        pending = waiting
        guard waiting.prize != nil else {
            blockedByPendingPayment = true
            return
        }
        resumedPending = true
        resumedGift = Self.gift(from: waiting)
        await check()
    }

    // MARK: « Somebody likes you! » → vérification

    /// « Open it » : la vérification (ce qui arrive, où, qui signe), avant toute session NFC (règle 8).
    func open() {
        guard gift != nil, stage == .idle else { return }
        preparationIssue = nil
        isReviewPresented = true
    }

    // MARK: Vérification → PIN → tap

    var isSigningLocked: Bool {
        switch stage {
        case .preparing, .scanning, .sending, .checking, .finished: true
        case .idle, .enteringPin, .waitingForTap, .wrongCard: false
        }
    }

    var isSigningSheetPresented: Bool {
        switch stage {
        case .enteringPin, .waitingForTap, .scanning: true
        default: false
        }
    }

    var showsStatus: Bool {
        switch stage {
        case .sending, .checking, .finished: true
        default: false
        }
    }

    var signingSteps: [SigningStep] {
        gift?.usesPin == true ? [.pin, .tapToSign] : [.tapToSign]
    }

    var currentSigningStep: SigningStep? {
        switch stage {
        case .enteringPin: .pin
        case .waitingForTap(let step), .scanning(let step): step
        default: nil
        }
    }

    /// « Tap your card » : prépare le retrait (réseau, avant toute session NFC), puis le PIN ou le tap. Le PIN se tape
    /// pendant la préparation.
    func confirmReview() {
        guard stage == .idle, let gift, !blockedByPendingPayment else { return }
        preparationIssue = nil
        technicalDetails = nil
        let task = Task { try await service.prepare(gift) }
        preparation = task
        if signingSteps.first == .pin {
            beginSigning()
        } else {
            stage = .preparing
        }
        Task {
            do {
                let ready = try await task.value
                guard preparation == task else { return }
                prepared = ready
                preparation = nil
                if stage == .preparing { beginSigning() }
            } catch {
                guard preparation == task else { return }
                preparation = nil
                resetSigning()
                prepareFailed(error)
            }
        }
    }

    /// Rien n'a été signé : la vérification dit pourquoi. Le coffre a changé : le nouveau montant, à confirmer.
    private func prepareFailed(_ error: Error) {
        technicalDetails = SendFlowModel.details(error)
        switch error {
        case let changed as PrizeAmountChanged where changed.amount > 0:
            if let gift { self.gift = gift.withAmount(changed.amount) }
            preparationIssue = .amountChanged
        case is PrizeAmountChanged, PrizeContract.PrizeError.nothingReserved:
            preparationIssue = .alreadyOpened
        case PrizeContract.PrizeError.notCardOwner:
            preparationIssue = .notOwner
        case PrizeServiceError.unknownCard:
            preparationIssue = .unknownCard
        default:
            preparationIssue = .other
        }
    }

    private func beginSigning() {
        pin = ""
        pinState = .entering
        tapProblem = nil
        if signingSteps.first == .pin {
            stage = .enteringPin
        } else {
            autoScan()
        }
    }

    func pinEntered(_ value: String) {
        guard stage == .enteringPin, value.count == pinLength else { return }
        pin = value
        tapProblem = nil
        autoScan()
    }

    /// La fenêtre NFC d'iOS s'ouvre sans « Scan my card » (après le PIN, « Tap your card » ou « Try again »).
    private func autoScan() {
        stage = .waitingForTap(.tapToSign)
        startScan(after: AutoScan.pause)
    }

    func scanCard() {
        startScan(after: .zero)
    }

    private func startScan(after pause: Duration) {
        guard case .waitingForTap(let step) = stage, prepared != nil || preparation != nil, let gift else { return }
        stage = .scanning(step)
        isGettingReady = true
        tapProblem = nil
        Task {
            if pause > .zero { try? await Task.sleep(for: pause) }
            guard let current = await readyPrepared() else {
                isGettingReady = false
                return
            }
            do {
                let fresh = try await service.refreshedIfNeeded(current, gift: gift)
                prepared = fresh
                isGettingReady = false
                let signatures = try await service.sign(fresh, pin: gift.usesPin && !pin.isEmpty ? pin : nil)
                pin = ""
                signed = signatures
                await send(fresh, signatures)
            } catch {
                isGettingReady = false
                handleTapError(error)
            }
        }
    }

    /// Échec **avant** que quoi que ce soit parte : mêmes cas qu'Envoyer, plus le coffre qui a changé pendant la
    /// préparation refaite juste avant le tap (retour à la vérification).
    private func handleTapError(_ error: Error) {
        switch error {
        case ChipError.cancelled:
            stage = .waitingForTap(.tapToSign)
        case ChipError.wrongPIN(let retriesLeft):
            pin = ""
            pinState = .wrong(triesLeft: retriesLeft)
            stage = .enteringPin
        case ChipError.pinLocked:
            pin = ""
            pinState = .blocked
            stage = .enteringPin
        case ChipError.pinRequired:
            pin = ""
            pinState = .entering
            stage = .enteringPin
        case ChipError.cardNotAccepted(let tapped):
            technicalDetails = SendFlowModel.details(error)
            stage = .wrongCard(wrongCard(tapped: tapped))
        case is PrizeAmountChanged, PrizeContract.PrizeError.nothingReserved, PrizeContract.PrizeError.notCardOwner,
             PrizeServiceError.unknownCard:
            resetSigning()
            prepareFailed(error)
        default:
            tapProblem = SendFlowModel.tapProblem(for: error)
            technicalDetails = SendFlowModel.details(error)
            stage = .waitingForTap(.tapToSign)
        }
    }

    private func wrongCard(tapped: ChipPublicKey) -> WrongCard {
        let known = service.knownCard(tapped)
        let needed = gift.map { KnownCard(name: $0.cardName, color: $0.cardColor) }
        return WrongCard(reason: known == nil ? .notYours : .otherWallet, tapped: known, needed: needed)
    }

    func retryAfterWrongCard() {
        guard case .wrongCard = stage else { return }
        autoScan()
    }

    func cancelSigning() {
        switch stage {
        case .enteringPin, .waitingForTap, .wrongCard:
            resetSigning()
        default:
            break
        }
    }

    private func readyPrepared() async -> PreparedPrizeClaim? {
        if let prepared { return prepared }
        return try? await preparation?.value
    }

    private func resetSigning() {
        preparation?.cancel()
        preparation = nil
        pin = ""
        pinState = .entering
        prepared = nil
        tapProblem = nil
        isGettingReady = false
        stage = .idle
    }

    // MARK: Envoi et issue

    private func waiting(_ trace: PaymentTrace, gift: PrizeGift) -> PendingSend {
        PendingSend(
            trace: trace, recipient: gift.wallet, recipientName: gift.walletTitle, drawerTitle: gift.walletTitle,
            asset: gift.asset.rawValue, amount: gift.amount, signedAt: .now,
            prize: PendingPrize(cardKey: gift.cardKey.hex, cardName: gift.cardName)
        )
    }

    private func send(_ prepared: PreparedPrizeClaim, _ signatures: CardSignatures) async {
        guard let gift else { return }
        stage = .sending(.checking)
        // Gardée dès le retour de la carte, avant l'envoi (effacée par `finish`) : une app tuée pendant l'envoi ne
        // permet jamais une nouvelle signature.
        keepPending(waiting(prepared.trace, gift: gift))
        do {
            let receipt = try await service.submit(prepared, gift: gift, signed: signatures) { [weak self] progress in
                self?.stage = .sending(progress)
            }
            finish(with: .sent(receipt))
        } catch {
            technicalDetails = SendFlowModel.details(error)
            failureReason = SendFailureReason(error)
            guard let failure = error as? PaymentFailure else {
                stage = .finished(.undetermined)
                return
            }
            keepPending(waiting(failure.trace, gift: gift))
            await check()
        }
    }

    private func keepPending(_ waiting: PendingSend) {
        pending = waiting
        do {
            try service.setPendingSend(waiting)
        } catch {
            pendingSaveFailed = true
        }
    }

    func checkAgain() {
        switch stage {
        case .finished(.notConfirmed), .finished(.undetermined):
            Task { await check() }
        default:
            break
        }
    }

    private func check() async {
        guard let pending, pending.prize != nil else { return }
        waitTask?.cancel()
        stage = .checking
        do {
            switch try await service.check(pending.trace) {
            case .sent(let hash):
                finish(with: .sent(PrizeReceipt(
                    gift: shownGift ?? Self.gift(from: pending), transactionHash: hash, sentAt: pending.signedAt,
                    explorerURL: service.explorerURL(transactionHash: hash)
                )))
            case .pending:
                stage = .finished(.notConfirmed)
            case .waiting(_, let end):
                stage = .finished(.waiting(until: end))
                scheduleCheck(at: end)
            case .nothingSent:
                finish(with: .nothingSent)
            case .undetermined(let reason):
                technicalDetails = [technicalDetails, reason].compactMap { $0 }.joined(separator: "\n")
                stage = .finished(.undetermined)
            }
        } catch {
            technicalDetails = SendFlowModel.details(error)
            stage = .finished(.undetermined)
        }
    }

    /// Un retrait repris depuis le téléphone : ce qu'il faut pour le réafficher (la carte, le wallet, le montant).
    static func gift(from pending: PendingSend) -> PrizeGift {
        let key = (try? ChipPublicKey(Data(hex: pending.prize?.cardKey ?? "") ?? Data())) ?? MockChipReader.secp256k1Key
        return PrizeGift(
            cardKey: key, cardName: pending.prize?.cardName ?? String(localized: "Card"), cardColor: .jungle, cardNumber: nil,
            wallet: pending.trace.from, amount: pending.amount, usesPin: true, curve: .secp256k1
        )
    }

    /// Le cadeau d'une opération reprise depuis le téléphone (pour l'affichage seulement, jamais pour signer).
    private var resumedGift: PrizeGift?

    /// Ce que l'écran d'état montre : le cadeau en cours, ou celui de l'opération reprise (gardé après son issue).
    var shownGift: PrizeGift? {
        gift ?? resumedGift
    }

    private func scheduleCheck(at end: Date) {
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            let delay = max(0, end.timeIntervalSinceNow) + 1
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            waitTask = nil
            await check()
        }
    }

    private func finish(with outcome: PrizeOutcome) {
        waitTask?.cancel()
        pending = nil
        try? service.setPendingSend(nil)
        stage = .finished(outcome)
    }

    var explorerURL: URL? {
        if case .finished(.sent(let receipt)) = stage { return receipt.explorerURL }
        return pending?.trace.transactionHash.flatMap(service.explorerURL(transactionHash:))
    }

    /// Comme le vault (revue de sécurité F3, partie 2) : tant que l'autorisation signée n'a pas expiré, « Try again » la
    /// renvoie telle quelle, sans nouvelle signature (même nonce : une seule exécution possible).
    var canResend: Bool {
        guard case .finished(.waiting) = stage else { return false }
        return signed != nil && prepared != nil
    }

    func resend() {
        guard canResend, let signed, let prepared else { return }
        waitTask?.cancel()
        technicalDetails = nil
        failureReason = nil
        Task { await send(prepared, signed) }
    }

    /// « Nothing was moved » (certain) : une nouvelle vérification, puis une nouvelle signature.
    var canTryAgain: Bool {
        stage == .finished(.nothingSent) && gift != nil && !resumedPending
    }

    func tryAgain() {
        guard canTryAgain else { return }
        prepared = nil
        signed = nil
        technicalDetails = nil
        failureReason = nil
        stage = .idle
    }

    func finish() {
        waitTask?.cancel()
        preparation?.cancel()
        onExit?()
    }
}

/// Issue d'un retrait, une fois la carte passée (mêmes cas qu'Envoyer).
enum PrizeOutcome: Equatable {
    case sent(PrizeReceipt)
    case notConfirmed
    case waiting(until: Date)
    case nothingSent
    case undetermined
}

/// Où en est la signature.
enum PrizeStage: Equatable {
    case idle
    case preparing
    case enteringPin
    case waitingForTap(SigningStep)
    case scanning(SigningStep)
    case sending(PaymentProgress)
    case wrongCard(WrongCard)
    case checking
    case finished(PrizeOutcome)

    var sound: ChimpSound? {
        switch self {
        case .sending: .confirmation
        case .finished(.sent): .money
        case .wrongCard: .hurt
        case .finished(.nothingSent), .finished(.waiting): .error
        default: nil
        }
    }
}

extension PrizeGift {
    /// Le même cadeau, avec le montant relu sur la chaîne.
    func withAmount(_ amount: Decimal) -> PrizeGift {
        PrizeGift(
            cardKey: cardKey, cardName: cardName, cardColor: cardColor, cardNumber: cardNumber, wallet: wallet,
            amount: amount, usesPin: usesPin, curve: curve
        )
    }
}
