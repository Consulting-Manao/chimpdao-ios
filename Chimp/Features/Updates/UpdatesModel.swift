import Foundation
import Observation

/// Réglages › Updates : chaque contrat du compte et où il en est (`UpdatesList.tsx` du terminal), lus sur la chaîne.
/// Le Main account d'abord, puis le wallet de chaque carte. Ne fait aucune crypto : `UpdatesService`.
@Observable
final class UpdatesModel {
    struct Row: Identifiable, Equatable {
        enum Subject: Equatable {
            case account
            case card(key: String, name: String, color: ChimpCardColor, number: String, chip: ChipKind?)
        }

        let subject: Subject
        let address: String
        /// `nil` : pas encore lu, ou contrat absent (archivé, jamais déployé).
        var status: UpdateStatus?

        var id: String { address }

        var isAccount: Bool { subject == .account }

        /// La mise à jour à faire, seulement pour une ligne « Update ready » : la cible est toujours la tête de la flotte.
        var target: UpdateTarget? {
            guard case .available(_, let to) = status else { return nil }
            return UpdateTarget(kind: isAccount ? .account : .pocket, address: address, wasmHash: to)
        }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(details: String)
    }

    private(set) var rows: [Row] = []
    private(set) var phase = Phase.idle

    let session: AppSession
    let service: UpdatesService

    init(session: AppSession, service: UpdatesService) {
        self.session = session
        self.service = service
    }

    /// Lignes qui proposent une mise à jour.
    var readyCount: Int { rows.filter { $0.target != nil }.count }

    /// La valeur de la ligne « Updates » des Réglages : « 1 ready », « Up to date », ou rien tant que ce n'est pas lu.
    var summary: String? {
        guard phase == .loaded else { return nil }
        return readyCount == 0 ? String(localized: "Up to date") : String(localized: "\(readyCount) ready")
    }

    /// Les contrats à juger : le Main account, puis le wallet de chaque carte que le Wallet a lu (noms et couleurs du
    /// téléphone, comme partout).
    static func subjects(account: String?, cards: [CardBalance], saved: [SavedCard]) -> [Row] {
        var rows: [Row] = []
        if let account { rows.append(Row(subject: .account, address: account)) }
        for card in cards {
            guard let pocket = card.pocket else { continue }
            let mine = saved.first { $0.publicKey == card.id }
            rows.append(Row(
                subject: .card(
                    key: card.id, name: mine?.name ?? card.name,
                    color: mine?.color.flatMap(ChimpCardColor.init(rawValue:)) ?? card.color, number: card.number, chip: card.chip
                ),
                address: pocket
            ))
        }
        return rows
    }

    /// Relit la flotte et le code de chaque contrat. Le compte contre la cible `account`, chaque wallet contre `pocket`.
    func refresh(cards: [CardBalance]) async {
        let subjects = Self.subjects(account: session.wallet.account?.address, cards: cards, saved: session.wallet.account?.cards ?? [])
        guard !subjects.isEmpty else {
            rows = []
            phase = .loaded
            return
        }
        if rows.map(\.address) != subjects.map(\.address) { rows = subjects }
        phase = .loading
        do {
            let (fleet, executables) = try await service.read(addresses: subjects.map(\.address))
            rows = subjects.map { row in
                var row = row
                row.status = executables[row.address].map {
                    ContractUpdates.status(target: fleet.target(row.isAccount ? .account : .pocket), current: $0)
                }
                return row
            }
            phase = .loaded
        } catch {
            phase = .failed(details: OnboardingModel.details(error))
        }
    }
}
