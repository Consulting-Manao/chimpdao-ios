import Foundation
import stellarsdk

/// Ce qu'un contrat fait signer à une adresse, **déclaré** par le protocole : `AuthShape` de
/// `reference/terminal/src/chain/auth-tree.ts`.
///
/// Une simulation « recording » découvre d'habitude les autorisations d'un appel, mais elle échoue pour une Pocket
/// (CAP-85, ARCHITECTURE §3.3) : pour une Pocket, l'arbre doit être connu d'avance. Il l'est, parce que le contrat du
/// protocole le dit et qu'il ne change pas d'un appel à l'autre : un `deposit` de vault prend le montant déposé au
/// déposant et rien d'autre, un retrait ne prend rien.
///
/// Sur iPhone, la même forme sert aussi au Main account : l'arbre rendu par la simulation doit être exactement l'arbre
/// déclaré, sinon rien n'est signé (DESIGN_NOTES §13, 2026-10-14).
protocol AuthShape {
    /// L'adresse dont `call` exige l'autorisation ; `nil` quand cette forme ne connaît pas l'appel.
    func signer(of call: ContractCall) -> String?
    /// Ce que l'appelé prend à `from` pendant `call` : les sous-appels que `from` signe sous lui.
    /// Vide sauf si `from` est le signataire de `call`.
    func pulls(of call: ContractCall, from: String) throws -> [ContractCall]
}

/// N'importe quel jeton SEP-41 (`TOKEN_SHAPE`) : le premier argument signe, et un jeton ne prend rien à personne.
/// Compris sans être déclaré, parce que chaque « prise » d'un protocole est l'un de ces appels.
struct TokenShape: AuthShape {
    static let methods: Set<String> = ["transfer", "approve", "burn", "transfer_from", "burn_from"]

    func signer(of call: ContractCall) -> String? {
        Self.methods.contains(call.function) ? call.addressArgument(0) : nil
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] { [] }

    /// Un `transfer` SEP-41 sous forme d'appel (`transferCall`) : la prise que fait chaque protocole.
    static func transfer(token: String, from: String, to: String, units: Int128) throws -> ContractCall {
        ContractCall(
            contract: token, function: "transfer",
            arguments: [try ContractArgument.address(from), try ContractArgument.address(to), ContractArgument.i128(units)]
        )
    }
}

/// La première forme qui connaît l'appel répond pour lui (`composeShapes`).
struct ComposedShape: AuthShape {
    let shapes: [any AuthShape]

    init(_ shapes: any AuthShape...) {
        self.shapes = shapes
    }

    private func owner(of call: ContractCall) -> (any AuthShape)? {
        shapes.first { $0.signer(of: call) != nil }
    }

    func signer(of call: ContractCall) -> String? {
        owner(of: call)?.signer(of: call)
    }

    func pulls(of call: ContractCall, from: String) throws -> [ContractCall] {
        guard let owner = owner(of: call), owner.signer(of: call) == from else { return [] }
        return try owner.pulls(of: call, from: from)
    }
}

/// Qui autorise un appel d'intégration (`EarnContext` du terminal) : le Main account (`AccountAuth`, n'importe quelle
/// carte du compte) ou le wallet d'une carte (`ChipAuth`, seulement cette carte).
enum CallAuthorizer: Equatable, Hashable {
    case account(String)
    case pocket(String)

    var address: String {
        switch self {
        case .account(let address), .pocket(let address): address
        }
    }

    var isPocket: Bool {
        if case .pocket = self { return true }
        return false
    }
}

/// Un arbre d'autorisation déclaré, et qui le signe (`DeclaredInvocation`).
struct DeclaredInvocation {
    let authorizer: CallAuthorizer
    let invocation: SorobanAuthorizedInvocationXDR
}

/// `declaredInvocations` et `invocationOf` de `auth-tree.ts` : tous les arbres qu'une transaction exige, à partir de ce
/// qu'on sait appeler.
enum DeclaredInvocations {
    enum DeclarationError: Error, Equatable, LocalizedError {
        /// Un appel sans autorisateur (`A call needs an authorizer`).
        case noAuthorizer
        /// Un appel simple n'a qu'un autorisateur (`A single call has one authorizer`).
        case singleCallHasOneAuthorizer
        /// Aucune forme ne dit ce que `signer` signe dans cet appel : on refuse plutôt que d'inventer un arbre.
        case undeclared(signer: String, function: String, contract: String)
        /// Un cosignataire qui ne signe aucune jambe du lot.
        case cosignsNothing(String)

        var errorDescription: String? {
            switch self {
            case .noAuthorizer: "A call needs an authorizer"
            case .singleCallHasOneAuthorizer: "A single call has one authorizer"
            case .undeclared(let signer, let function, let contract):
                "Cannot say what \(signer.prefix(8))… signs for in \(function) on \(contract.prefix(8))… — this protocol has not declared it"
            case .cosignsNothing(let address): "\(address.prefix(8))… cosigns nothing in this batch"
            }
        }
    }

    /// `invocationOf` : `call` tel que `from` l'autorise, puis ce qu'il prend à `from`, récursivement.
    static func invocation(of call: ContractCall, from: String, shape: any AuthShape) throws -> SorobanAuthorizedInvocationXDR {
        try call.invocation(subInvocations: try shape.pulls(of: call, from: from).map {
            try invocation(of: $0, from: from, shape: shape)
        })
    }

    /// `declaredInvocations` : un appel simple est autorisé par son signataire, ses prises dessous. Un lot du router
    /// (`root` = `batch(caller, calls)`, `legs` = les appels) : l'appelant autorise le lot avec **chaque** jambe en
    /// sous-appel (le router exige l'appelant pour chacune), et chaque cosignataire autorise les jambes qui le nomment,
    /// chacune dans son propre arbre. `TokenShape` est toujours ajouté derrière la forme du protocole.
    ///
    /// Refuse plutôt que de deviner : un appel qu'aucune forme ne revendique serait un arbre inventé.
    static func build(
        root: ContractCall,
        legs: [ContractCall]? = nil,
        authorizers: [CallAuthorizer],
        shape: any AuthShape
    ) throws -> [DeclaredInvocation] {
        let shape = ComposedShape(shape, TokenShape())
        guard let caller = authorizers.first else { throw DeclarationError.noAuthorizer }
        let cosigners = authorizers.dropFirst()

        guard let legs else {
            guard cosigners.isEmpty else { throw DeclarationError.singleCallHasOneAuthorizer }
            guard shape.signer(of: root) == caller.address else {
                throw DeclarationError.undeclared(signer: caller.address, function: root.function, contract: root.contract)
            }
            return [DeclaredInvocation(authorizer: caller, invocation: try invocation(of: root, from: caller.address, shape: shape))]
        }

        var out = [DeclaredInvocation(
            authorizer: caller,
            invocation: try root.invocation(subInvocations: try legs.map { try invocation(of: $0, from: caller.address, shape: shape) })
        )]
        for cosigner in cosigners {
            let own = legs.filter { shape.signer(of: $0) == cosigner.address }
            guard !own.isEmpty else { throw DeclarationError.cosignsNothing(cosigner.address) }
            for leg in own {
                out.append(DeclaredInvocation(authorizer: cosigner, invocation: try invocation(of: leg, from: cosigner.address, shape: shape)))
            }
        }
        return out
    }
}
