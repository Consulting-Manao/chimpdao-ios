import Foundation

/// Mises à jour du code des contrats (« Updates »), partie **sans réseau** : portage fidèle de
/// `reference/terminal/src/chain/updates.ts` (et du type `Executable` de `read.ts`). Voir aussi
/// `reference/chimp-contracts/docs/CLIENT-INTEGRATION.md` §6.
///
/// Deux faits seulement décident : le code qu'un contrat fait tourner maintenant, et ce que la « flotte » du factory dit
/// être à jour. Le wallet d'une carte (Pocket) est jugé contre la cible `pocket`, le Main account contre la cible
/// `account`. Qu'on demande d'abord à son détenteur (`Manual`) ou non (`Managed`) ne se décide pas ici : une Pocket qui
/// suit la flotte se lit simplement `managed`.
enum ContractComponent: Equatable, Sendable {
    case pocket
    case account
}

/// Une cible de la flotte. `history` : du plus ancien au plus récent, la tête **en dernier**, comme `fleet()` la rend.
/// C'est elle qui reconnaît un contrat en retard de deux versions (`available`) et un hash jamais publié (`custom`).
///
/// `legacy` : cible lue sans historique (factory antérieur à `fleet()`, ou tête du compte prise dans `Config/`). Avec un
/// seul hash, il n'y a pas d'ordre : toute différence avec la tête est proposée.
struct FleetTarget: Equatable, Sendable {
    var head: String?
    var history: [String]
    var legacy: Bool
}

/// La flotte telle que l'app la juge.
struct Fleet: Equatable, Sendable {
    /// Compteur du factory ; `nil` pour une lecture `legacy`, qui n'en a pas.
    var epoch: UInt32?
    var pocket: FleetTarget
    var account: FleetTarget

    func target(_ component: ContractComponent) -> FleetTarget {
        switch component {
        case .pocket: pocket
        case .account: account
        }
    }
}

/// D'où vient le code d'un contrat en ce moment (`Executable` de `read.ts`).
enum ContractExecutable: Equatable, Sendable {
    /// Une référence à l'entrée d'un autre contrat (Protocol 28, `ExternalRef`) : une Pocket qui suit la flotte.
    case fleet(owner: String, tag: String)
    /// Un hash à lui : une Pocket figée par sa puce, un Main account, ou tout contrat ordinaire.
    case wasm(hash: String)
    /// Un Stellar Asset Contract, sans wasm.
    case asset
}

/// L'état d'un contrat face à sa cible.
enum UpdateStatus: Equatable, Sendable {
    /// Fait tourner la tête.
    case upToDate(hash: String)
    /// Fait tourner une version plus ancienne publiée par la flotte ; `to` est la tête.
    case available(from: String, to: String)
    /// Suit la flotte : la prochaine publication le fait avancer tout seul.
    case managed
    /// Code jamais publié par la flotte (ou pas de wasm du tout). Jamais proposé.
    case custom(hash: String?)
    /// Rien à comparer : aucune tête publiée, ou code inconnu.
    case unknown

    /// Propose-t-on une mise à jour ? Seulement `available` (`wantsUpdate`).
    var wantsUpdate: Bool {
        if case .available = self { true } else { false }
    }
}

enum ContractUpdates {
    /// Les hash se comparent en hexadécimal minuscule, sans « 0x » (`normHash`).
    static func normHash(_ hash: String) -> String {
        let lower = hash.lowercased()
        return lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
    }

    /// Juge le code actuel d'un contrat contre la cible de son composant (`updateStatus`). Dans l'ordre :
    /// 1. une référence à la flotte la suit : `managed` ;
    /// 2. aucune tête publiée : `unknown` ;
    /// 3. fait tourner la tête : `upToDate` ;
    /// 4. cible `legacy` (une tête seule) : tout autre hash est `available` ;
    /// 5. sinon, publié plus tôt (dans l'historique) : `available` ; jamais publié : `custom`, jamais proposé.
    ///    Une mise à jour ne pointe donc jamais que vers la tête : jamais de retour en arrière.
    static func status(target: FleetTarget, current: ContractExecutable) -> UpdateStatus {
        let hash: String
        switch current {
        case .fleet: return .managed
        case .asset: return .custom(hash: nil)
        case .wasm(let wasm): hash = normHash(wasm)
        }
        guard let rawHead = target.head else { return .unknown }
        let head = normHash(rawHead)
        if hash == head { return .upToDate(hash: hash) }
        if target.legacy { return .available(from: hash, to: head) }
        if target.history.contains(where: { normHash($0) == hash }) { return .available(from: hash, to: head) }
        return .custom(hash: hash)
    }

    /// Un **nouveau** compte peut-il naître sur ce wasm (`birthRecognised`) ? Seulement si la flotte le reconnaît : la
    /// tête ou une version qu'elle a remplacée. Aucune tête publiée : la flotte n'a pas d'avis, le choix de l'app tient.
    static func birthRecognised(target: FleetTarget, hash: String) -> Bool {
        guard let head = target.head else { return true }
        let h = normHash(hash)
        return normHash(head) == h || target.history.contains { normHash($0) == h }
    }

    /// Même flotte, pour une décision de mise à jour (`sameFleet`) : une revalidation peut sauter son travail.
    static func sameFleet(_ a: Fleet, _ b: Fleet) -> Bool {
        a.epoch == b.epoch && a.pocket == b.pocket && a.account == b.account
    }
}
