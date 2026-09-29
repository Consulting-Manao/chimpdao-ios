import CoreNFC
import Foundation

/// Lecture d'une carte par Core NFC : une feuille NFC, une carte, puis fermeture.
struct NFCChipReader: ChipReader {
    func readKey() async throws -> ChipKeyInfo {
        try await NFCTagSession.run(
            alertMessage: String(localized: "Hold your card near the top of your iPhone."),
            successMessage: String(localized: "Card read.")
        ) { transport in
            try await ChipDetector.readKey(transport)
        }
    }
}

/// Une session `NFCTagReaderSession` (ISO 14443) qui attend une seule carte, la connecte,
/// exécute une opération APDU pendant que la feuille est ouverte, puis ferme la feuille.
/// Inspiré de `ios-app-tupui/Chimp/NFC/NFCHelper.swift`, avec deux différences voulues :
/// - la DUOX peut être présentée par iOS comme `.miFare` (famille DESFire) plutôt que `.iso7816`
///   (ARCHITECTURE §4.3 piège 1) : les deux sont acceptées ;
/// - aucune erreur n'est avalée (règle 7) : annulation, délai de 60 s et erreurs radio remontent à l'appelant.
/// La limite de 60 s est celle d'iOS : la session se ferme d'elle-même et on le signale par `.timeout`.
final class NFCTagSession: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    /// Attente de la connexion à une carte ; reprise une seule fois.
    private var connection: CheckedContinuation<any APDUTransport, Error>?
    /// Raison de la fermeture de la session par iOS, si elle arrive pendant l'opération.
    private var invalidation: ChipError?

    static func run<T>(
        alertMessage: String,
        successMessage: String,
        operation: (any APDUTransport) async throws -> T
    ) async throws -> T {
        guard NFCTagReaderSession.readingAvailable else { throw ChipError.nfcUnavailable }
        let runner = NFCTagSession()
        let transport = try await runner.connect(alertMessage: alertMessage)
        do {
            let result = try await operation(transport)
            runner.finish(message: successMessage)
            return result
        } catch {
            // Si iOS a fermé la session pendant l'opération (60 s, annulation), c'est la vraie cause :
            // l'erreur radio qui a suivi n'en est que la conséquence.
            var cause = runner.invalidation ?? error
            // Exception : un PIN tout juste défini. Le PUK n'existe qu'une fois, il ne doit jamais disparaître derrière
            // la cause d'iOS : on garde l'erreur qui le porte, avec la cause d'iOS à l'intérieur.
            if let pinSet = error as? PINSetButSigningFailed {
                cause = PINSetButSigningFailed(puk: pinSet.puk, underlying: runner.invalidation ?? pinSet.underlying)
            }
            runner.fail(message: (cause as? LocalizedError)?.errorDescription ?? cause.localizedDescription)
            throw cause
        }
    }

    private func connect(alertMessage: String) async throws -> any APDUTransport {
        try await withCheckedThrowingContinuation { continuation in
            connection = continuation
            // File principale : les rappels du délégué arrivent sur le thread principal (acteur principal).
            guard let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main) else {
                resumeConnection(throwing: ChipError.nfcUnavailable)
                return
            }
            session.alertMessage = alertMessage
            self.session = session
            session.begin()
        }
    }

    private func finish(message: String) {
        session?.alertMessage = message
        session?.invalidate()
        session = nil
    }

    private func fail(message: String) {
        session?.invalidate(errorMessage: message)
        session = nil
    }

    private func resumeConnection(with transport: any APDUTransport) {
        connection?.resume(returning: transport)
        connection = nil
    }

    private func resumeConnection(throwing error: Error) {
        connection?.resume(throwing: error)
        connection = nil
    }

    // MARK: NFCTagReaderSessionDelegate

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        MainActor.assumeIsolated {
            let reason = Self.chipError(forInvalidation: error)
            // Fermeture demandée par nous (fin normale) : rien à signaler.
            guard self.session != nil else { return }
            invalidation = reason
            self.session = nil
            resumeConnection(throwing: reason)
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        MainActor.assumeIsolated {
            guard tags.count == 1, let tag = tags.first else {
                resumeConnection(throwing: ChipError.multipleTags)
                fail(message: ChipError.multipleTags.errorDescription ?? "")
                return
            }
            let transport: any APDUTransport
            switch tag {
            case .iso7816(let isoTag):
                transport = ISO7816Transport(tag: isoTag)
            case .miFare(let miFareTag) where miFareTag.mifareFamily == .desfire:
                transport = MiFareISO7816Transport(tag: miFareTag)
            case .miFare(let miFareTag):
                reject(ChipError.unsupportedTag("MIFARE family \(miFareTag.mifareFamily.rawValue)"))
                return
            case .feliCa:
                reject(ChipError.unsupportedTag("FeliCa"))
                return
            case .iso15693:
                reject(ChipError.unsupportedTag("ISO 15693"))
                return
            @unknown default:
                reject(ChipError.unsupportedTag("unknown tag type"))
                return
            }
            Task { @MainActor in
                do {
                    try await session.connect(to: tag)
                    resumeConnection(with: transport)
                } catch {
                    let failure = ChipError.transport(error.localizedDescription)
                    resumeConnection(throwing: failure)
                    fail(message: failure.errorDescription ?? "")
                }
            }
        }
    }

    private func reject(_ error: ChipError) {
        resumeConnection(throwing: error)
        fail(message: error.errorDescription ?? "")
    }

    private static func chipError(forInvalidation error: Error) -> ChipError {
        guard let readerError = error as? NFCReaderError else {
            return .sessionFailed(error.localizedDescription)
        }
        switch readerError.code {
        case .readerSessionInvalidationErrorUserCanceled: return .cancelled
        case .readerSessionInvalidationErrorSessionTimeout: return .timeout
        case .readerTransceiveErrorTagConnectionLost, .readerTransceiveErrorTagNotConnected:
            return .transport(readerError.localizedDescription)
        default: return .sessionFailed(readerError.localizedDescription)
        }
    }
}

/// Carte présentée par iOS comme ISO 7816 (cas de l'Infineon : son AID figure dans l'Info.plist).
private struct ISO7816Transport: APDUTransport {
    let tag: any NFCISO7816Tag

    func send(_ apdu: Data) async throws -> APDUResponse {
        guard let command = NFCISO7816APDU(data: apdu) else {
            throw ChipError.malformedResponse("invalid APDU \(apdu.hexString)")
        }
        do {
            let (data, sw1, sw2) = try await tag.sendCommand(apdu: command)
            return APDUResponse(data: data, sw1: sw1, sw2: sw2)
        } catch {
            throw ChipError.transport(error.localizedDescription)
        }
    }
}

/// Carte présentée par iOS comme MIFARE DESFire (cas possible de la DUOX) : mêmes APDU, autre appel.
private struct MiFareISO7816Transport: APDUTransport {
    let tag: any NFCMiFareTag

    func send(_ apdu: Data) async throws -> APDUResponse {
        guard let command = NFCISO7816APDU(data: apdu) else {
            throw ChipError.malformedResponse("invalid APDU \(apdu.hexString)")
        }
        do {
            let (data, sw1, sw2) = try await tag.sendMiFareISO7816Command(command)
            return APDUResponse(data: data, sw1: sw1, sw2: sw2)
        } catch {
            throw ChipError.transport(error.localizedDescription)
        }
    }
}
