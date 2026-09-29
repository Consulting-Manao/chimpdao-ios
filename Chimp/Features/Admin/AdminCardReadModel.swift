#if CHIMP_ADMIN
import Foundation
import Observation

/// Mode admin : lire une carte (type de puce, courbe, clé publique, PIN) et, pour une Infineon vierge
/// (slot 1 vide, `6A88`), générer sa clé. Rien n'est envoyé au réseau.
/// Compilé uniquement en Debug et Testing (drapeau `CHIMP_ADMIN`), jamais en Release.
@Observable
final class AdminCardReadModel {
    enum State: Equatable {
        case idle
        case reading
        case read(ChipKeyInfo)
        /// La carte n'a pas de clé n°1.
        case noKey(statusWord: UInt16)
        case generating
        case generated(ChipKeyInfo)
        case cancelled
        case failed(String)
    }

    /// Lecteur utilisé : la vraie carte (NFC) ou un scénario factice (simulateur).
    enum ReaderChoice: Hashable {
        case nfc
        case mock(MockChipReader.Scenario)
    }

    private(set) var state: State = .idle
    var readerChoice: ReaderChoice

    private let nfcReader: ChipReader
    private let nfcGenerator: ChipKeyGenerator
    private let mockDelay: Duration

    init(
        nfcAvailable: Bool,
        nfcReader: ChipReader = NFCChipReader(),
        nfcGenerator: ChipKeyGenerator = NFCChipKeyGenerator(),
        mockDelay: Duration = .milliseconds(700)
    ) {
        self.nfcReader = nfcReader
        self.nfcGenerator = nfcGenerator
        self.mockDelay = mockDelay
        readerChoice = nfcAvailable ? .nfc : .mock(.infineon)
    }

    var isBusy: Bool { state == .reading || state == .generating }

    /// Carte qui peut être enregistrée : lue avec une clé, ou dont la clé vient d'être générée.
    var cardForEnrolment: ChipKeyInfo? {
        switch state {
        case .read(let info), .generated(let info): info
        default: nil
        }
    }

    /// La génération n'est proposée qu'après une lecture qui a trouvé le slot 1 vide (`6A88`) ;
    /// les autres statuts « pas de clé » du bridge (`6A82`, `6985`) ne l'autorisent pas.
    var canGenerateKey: Bool { state == .noKey(statusWord: Infineon2Go.emptyKeySlotStatusWord) }

    func read() async {
        guard !isBusy else { return }
        state = .reading
        do {
            state = .read(try await reader.readKey())
        } catch ChipError.noKey(let statusWord) {
            state = .noKey(statusWord: statusWord)
        } catch {
            state = Self.failureState(error)
        }
    }

    /// Génère la clé n°1. À n'appeler qu'après la confirmation explicite de l'utilisateur (« irréversible »).
    /// La vraie garde est dans la session NFC (le slot 1 est revérifié sur la carte présente) ;
    /// celle-ci évite seulement de proposer l'action hors du bon état.
    func generateKey() async {
        guard canGenerateKey else { return }
        state = .generating
        do {
            state = .generated(try await generator.generateKeyOnEmptySlot())
        } catch {
            state = Self.failureState(error)
        }
    }

    private static func failureState(_ error: Error) -> State {
        if case ChipError.cancelled = error { return .cancelled }
        return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    private var reader: ChipReader {
        switch readerChoice {
        case .nfc: nfcReader
        case .mock(let scenario): MockChipReader(scenario: scenario, delay: mockDelay)
        }
    }

    private var generator: ChipKeyGenerator {
        switch readerChoice {
        case .nfc: nfcGenerator
        case .mock(let scenario): MockChipKeyGenerator(scenario: scenario, delay: mockDelay)
        }
    }
}
#endif
