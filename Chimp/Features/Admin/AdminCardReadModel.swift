#if CHIMP_ADMIN
import Foundation
import Observation

/// Mode admin, étape A : lire une carte (type de puce, courbe, clé publique, PIN), sans rien signer ni envoyer.
/// Compilé uniquement en Debug et Testing (drapeau `CHIMP_ADMIN`), jamais en Release.
@Observable
final class AdminCardReadModel {
    enum State: Equatable {
        case idle
        case reading
        case read(ChipKeyInfo)
        /// La carte n'a pas de clé n°1 : elle est refusée, on n'en génère jamais (règle 6).
        case noKey(statusWord: UInt16)
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

    init(nfcAvailable: Bool, nfcReader: ChipReader = NFCChipReader()) {
        self.nfcReader = nfcReader
        readerChoice = nfcAvailable ? .nfc : .mock(.infineon)
    }

    var isReading: Bool { state == .reading }

    func read() async {
        guard !isReading else { return }
        state = .reading
        do {
            state = .read(try await reader.readKey())
        } catch ChipError.noKey(let statusWord) {
            state = .noKey(statusWord: statusWord)
        } catch ChipError.cancelled {
            state = .cancelled
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private var reader: ChipReader {
        switch readerChoice {
        case .nfc: nfcReader
        case .mock(let scenario): MockChipReader(scenario: scenario)
        }
    }
}
#endif
