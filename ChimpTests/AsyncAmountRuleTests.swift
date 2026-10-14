import Foundation
import Testing
@testable import ChimpDAO

/// Règle de l'app (2026-10-14, validée par Barth) : **aucun montant 128 bits nu en paramètre d'une fonction ou d'une
/// closure `async`**, dans tout `Chimp/`. Swift 6.3.3 (Xcode 26.6), en Debug, corrompt la moitié haute d'un `Int128`
/// passé à une fonction `async` après d'autres paramètres (DESIGN_NOTES §13) ; un montant passe par `TokenAmount`.
///
/// Deux vérifications :
/// 1. le code source : un `Int128` / `UInt128` dans les paramètres d'une fonction ou d'une closure `async` est refusé,
///    et toute structure de l'app qui porte un montant 128 bits et traverse une fonction `async` doit être vérifiée à
///    l'exécution (liste `verifiedStructures`) ;
/// 2. l'exécution (tests en Debug) : `TokenAmount` et ces structures arrivent intacts après sept autres paramètres.
struct AsyncAmountRuleTests {
    /// Structures qui portent un montant 128 bits et traversent une fonction `async`, vérifiées par `runtimeProbes()`.
    static let verifiedStructures: Set<String> = ["SwapRequest", "SwapDraft", "PreparedSwap", "SignedSwap", "YieldPosition"]

    // MARK: Lecture du code source

    struct Violation: CustomStringConvertible {
        let file: String
        let line: Int
        let detail: String
        var description: String { "\(file):\(line) \(detail)" }
    }

    /// Le dossier `Chimp/` du dépôt, à côté de `ChimpTests/`.
    static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Chimp")
    }

    static func sources() throws -> [(name: String, text: String)] {
        let root = sourceRoot
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            out.append((url.path.replacingOccurrences(of: root.deletingLastPathComponent().path + "/", with: ""), try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    /// Le code sans commentaires ni chaînes (remplacées par `""`), pour ne pas lire un `Int128` dans un texte.
    static func stripped(_ source: String) -> String {
        let chars = Array(source)
        var out: [Character] = []
        var i = 0
        func starts(_ s: String, at index: Int) -> Bool {
            let pattern = Array(s)
            return index + pattern.count <= chars.count && Array(chars[index..<index + pattern.count]) == pattern
        }
        while i < chars.count {
            if starts("//", at: i) {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if starts("/*", at: i) {
                i += 2
                while i < chars.count, !starts("*/", at: i) { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                i += 2
            } else if starts("\"\"\"", at: i) {
                i += 3
                while i < chars.count, !starts("\"\"\"", at: i) { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                i += 3
                out.append(contentsOf: "\"\"")
            } else if chars[i] == "\"" {
                i += 1
                while i < chars.count, chars[i] != "\"", chars[i] != "\n" { i += chars[i] == "\\" ? 2 : 1 }
                i += 1
                out.append(contentsOf: "\"\"")
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return String(out)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        Range(range, in: text).map { String(text[$0]) } ?? ""
    }

    /// Le contenu entre `{` et sa `}`, à partir de l'index qui suit `{`.
    private static func body(_ chars: [Character], from start: Int) -> (text: String, end: Int) {
        var depth = 1, j = start
        while j < chars.count, depth > 0 {
            if chars[j] == "{" { depth += 1 } else if chars[j] == "}" { depth -= 1 }
            j += 1
        }
        return (String(chars[start..<max(start, j - 1)]), j)
    }

    /// Les structures qui portent un montant 128 bits (propriété stockée `Int128` / `UInt128`, ou une structure qui en
    /// porte une), toutes sources confondues.
    static func structuresCarrying128(_ sources: [String]) -> Set<String> {
        var stored: [String: [String]] = [:]
        for source in sources {
            let chars = Array(source)
            for match in matches(#"\bstruct\s+(\w+)[^{]*\{"#, in: source) {
                let name = substring(source, match.range(at: 1))
                guard let range = Range(match.range, in: source) else { continue }
                var flat = body(chars, from: source.distance(from: source.startIndex, to: range.upperBound)).text
                // Corps imbriqués (propriétés calculées, fonctions, types) vidés : seules les propriétés du niveau 0 restent.
                while let nested = flat.range(of: #"\{[^{}]*\}"#, options: .regularExpression) { flat.replaceSubrange(nested, with: "§") }
                for property in matches(#"\b(?:let|var)\s+\w+\s*:\s*([A-Za-z0-9_.]+)\??(?=\s*(\S?))"#, in: flat) {
                    if substring(flat, property.range(at: 2)) == "§" { continue } // propriété calculée
                    stored[name, default: []].append(substring(flat, property.range(at: 1)))
                }
            }
        }
        var carrying: Set<String> = []
        var changed = true
        while changed {
            changed = false
            for (name, types) in stored where !carrying.contains(name) {
                if types.contains(where: { $0 == "Int128" || $0 == "UInt128" || carrying.contains($0) }) {
                    carrying.insert(name)
                    changed = true
                }
            }
        }
        return carrying
    }

    /// Les paramètres de chaque fonction, initialiseur ou type de closure `async` : la liste entre parenthèses qui précède
    /// immédiatement le mot `async`.
    static func asyncParameterLists(_ source: String) -> [(line: Int, parameters: String)] {
        let chars = Array(source)
        var out: [(Int, String)] = []
        for match in matches(#"\)\s*async\b"#, in: source) {
            guard let range = Range(match.range, in: source) else { continue }
            let close = source.distance(from: source.startIndex, to: range.lowerBound)
            var depth = 0, k = close
            while k >= 0 {
                if chars[k] == ")" { depth += 1 } else if chars[k] == "(" { depth -= 1; if depth == 0 { break } }
                k -= 1
            }
            guard k >= 0 else { continue }
            out.append((chars[..<k].filter { $0 == "\n" }.count + 1, String(chars[(k + 1)..<close])))
        }
        return out
    }

    static func violations(in files: [(name: String, text: String)], verified: Set<String>) -> [Violation] {
        let cleaned = files.map { ($0.name, stripped($0.text)) }
        let carrying = structuresCarrying128(cleaned.map(\.1))
        var out: [Violation] = []
        for (name, text) in cleaned {
            for (line, parameters) in asyncParameterLists(text) {
                if parameters.range(of: #"\bU?Int128\b"#, options: .regularExpression) != nil {
                    out.append(Violation(file: name, line: line, detail: "128-bit amount in an async parameter: use TokenAmount"))
                }
                for type in carrying.subtracting(verified)
                where parameters.range(of: #":\s*(?:inout\s+)?(?:any\s+)?\#(type)\b"#, options: .regularExpression) != nil {
                    out.append(Violation(file: name, line: line, detail: "\(type) carries a 128-bit amount through an async call: verify it in runtimeProbes() or use TokenAmount"))
                }
            }
        }
        return out
    }

    @Test("Le scanner voit un Int128 en paramètre async (fonction, protocole, closure) et ignore commentaires, chaînes, synchrone")
    func scannerSelfTest() {
        let bad = """
        struct Small { let units: Int128 }
        protocol P { func a(_ x: Int, _ amount: Int128) async throws -> Int }
        func b(amount: UInt128) async {}
        let c: (Int128) async -> Void = { _ in }
        func d(_ value: Small) async {}
        """
        let found = Self.violations(in: [("Bad.swift", bad)], verified: [])
        #expect(found.map(\.line) == [2, 3, 4, 5])

        let fine = """
        // func a(_ amount: Int128) async
        let text = "func b(_ amount: Int128) async"
        func c(_ amount: Int128) -> Int128 { amount }
        func d(_ amount: TokenAmount) async -> Int128 { amount.units }
        struct Big { let a: String; let b: String; let units: Int128; var double: Int128 { units * 2 } }
        func e(_ value: Big) async {}
        """
        #expect(Self.violations(in: [("Fine.swift", fine)], verified: ["Big"]).isEmpty)
        #expect(Self.structuresCarrying128([Self.stripped(fine)]) == ["Big"], "Une propriété calculée ne compte pas")
    }

    @Test("Code de l'app : aucun montant 128 bits nu en paramètre async ; structures à montant vérifiées à l'exécution")
    func appSources() throws {
        let files = try Self.sources()
        try #require(files.count > 100, "Sources de Chimp/ introuvables depuis \(Self.sourceRoot.path)")
        let found = Self.violations(in: files, verified: Self.verifiedStructures)
        #expect(found.isEmpty, "\(found.map(\.description).joined(separator: "\n"))")
        // La liste ne garde que des structures qui existent et portent vraiment un montant.
        let carrying = Self.structuresCarrying128(files.map { Self.stripped($0.text) })
        let unknown = Self.verifiedStructures.subtracting(carrying)
        #expect(unknown.isEmpty, "Ne portent pas de montant 128 bits (ou introuvables) : \(unknown.sorted())")
    }

    // MARK: Exécution (Debug)

    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ amount: TokenAmount) async -> TokenAmount { _ = a + b + c + d + e + f + g; return amount }
    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ request: SwapRequest) async -> SwapRequest { _ = a + b + c + d + e + f + g; return request }
    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ draft: SwapDraft) async -> SwapDraft { _ = a + b + c + d + e + f + g; return draft }
    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ position: YieldPosition) async -> YieldPosition { _ = a + b + c + d + e + f + g; return position }
    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ prepared: PreparedSwap) async -> PreparedSwap { _ = a + b + c + d + e + f + g; return prepared }
    @inline(never) static func probe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ signed: SignedSwap) async -> SignedSwap { _ = a + b + c + d + e + f + g; return signed }
    @inline(never) static func bareProbe(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int, _ f: Int, _ g: Int, _ amount: Int128) async -> Int128 { _ = a + b + c + d + e + f + g; return amount }

    @Test("À l'exécution : TokenAmount et les structures à montant arrivent intactes après sept paramètres")
    @MainActor
    func runtimeProbes() async throws {
        for units: Int128 in [100_000_000, -1, Int128.max, Int128.min, 1 << 70] {
            #expect(await Self.probe(1, 2, 3, 4, 5, 6, 7, TokenAmount(units)).units == units)
        }
        let asset = IntegrationAsset(code: "XLM", contract: "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC")
        let request = SwapRequest(assetIn: asset, assetOut: asset, amountIn: 100_000_000)
        #expect(await Self.probe(1, 2, 3, 4, 5, 6, 7, request) == request)
        let position = YieldPosition(protocolID: "p", venueID: "v", holder: "h", shares: 1 << 66, value: 100_000_000)
        #expect(await Self.probe(1, 2, 3, 4, 5, 6, 7, position) == position)

        let model = SwapFlowModel(service: MockSwapService(delay: .zero), quoteDebounce: .zero)
        await model.loadIfNeeded()
        model.setAmount(400)
        await model.refreshQuote()
        model.continueToReview()
        let draft = try #require(model.draft)
        let received = await Self.probe(1, 2, 3, 4, 5, 6, 7, draft)
        #expect(received == draft)
        #expect(received.minimumOutUnits == draft.minimumOutUnits)

        let prepared = PreparedSwap(draft: draft, firstHopVenue: "pool", contract: "router")
        let preparedBack = await Self.probe(1, 2, 3, 4, 5, 6, 7, prepared)
        #expect(preparedBack.draft.minimumOutUnits == draft.minimumOutUnits)
        #expect(preparedBack.draft.quote.expectedOutUnits == draft.quote.expectedOutUnits)
        let signed = SignedSwap(prepared: prepared, cardName: "Banana")
        let signedBack = await Self.probe(1, 2, 3, 4, 5, 6, 7, signed)
        #expect(signedBack.prepared.draft.quote.expectedOutUnits == draft.quote.expectedOutUnits)
    }

    @Test("Témoin du défaut : un Int128 nu passé après sept paramètres (toléré s'il est corrompu)")
    func compilerDefectWitness() async {
        let got = await Self.bareProbe(1, 2, 3, 4, 5, 6, 7, 100_000_000)
        withKnownIssue("Swift 6.3.3 (Debug) corrompt un Int128 nu passé à une fonction async", isIntermittent: true) {
            #expect(got == 100_000_000)
        }
    }
}
