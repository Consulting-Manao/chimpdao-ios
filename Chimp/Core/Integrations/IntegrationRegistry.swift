import Foundation

/// Le registre des adaptateurs : `STRATEGY_PROTOCOLS`, `protocolById` et `discoverHost` du terminal
/// (`registry/protocols.ts`), plus le choix de la meilleure route entre protocoles d'échange (D2).
///
/// Écart avec le terminal : `discoverHost` avale l'erreur d'un protocole (« a summary is a summary ») ; ici chaque panne
/// est rendue avec le résultat, pour que l'écran puisse dire « protocole indisponible » au lieu de montrer une liste
/// incomplète comme si elle était entière (règle 7).
struct IntegrationRegistry {
    let swapAdapters: [any SwapAdapter]
    let yieldAdapters: [any YieldAdapter]

    /// Un protocole qui n'a pas répondu.
    struct Failure {
        let protocolID: String
        let error: Error
    }

    /// Les devis de chaque protocole et le meilleur d'entre eux.
    struct QuoteComparison {
        /// Le devis qui rend la plus grande quantité ; à égalité, le premier protocole enregistré.
        let best: SwapQuote?
        /// Tous les devis obtenus, dans l'ordre d'enregistrement.
        let quotes: [SwapQuote]
        /// Les protocoles sans route ne sont pas des pannes : ils n'apparaissent ni ici ni dans `quotes`.
        let failures: [Failure]
    }

    struct PositionDiscovery {
        let positions: [YieldPosition]
        let failures: [Failure]
    }

    func swapAdapter(id: String) -> (any SwapAdapter)? {
        swapAdapters.first { $0.id == id }
    }

    func yieldAdapter(id: String) -> (any YieldAdapter)? {
        yieldAdapters.first { $0.id == id }
    }

    /// Demande un devis à chaque protocole d'échange et garde le meilleur (« meilleure route retenue », D2). Un devis à 0
    /// ou d'une autre demande est ignoré. Les protocoles sont interrogés l'un après l'autre (deux aujourd'hui).
    func bestQuote(_ request: SwapRequest) async -> QuoteComparison {
        var quotes: [SwapQuote] = []
        var failures: [Failure] = []
        for adapter in swapAdapters {
            do {
                if let quote = try await adapter.quote(request), quote.request == request, quote.amountOut > 0 {
                    quotes.append(quote)
                }
            } catch {
                failures.append(Failure(protocolID: adapter.id, error: error))
            }
        }
        let best = quotes.reduce(nil) { (best: SwapQuote?, quote) in
            guard let best else { return quote }
            return quote.amountOut > best.amountOut ? quote : best
        }
        return QuoteComparison(best: best, quotes: quotes, failures: failures)
    }

    /// Les positions de `holder` chez chaque protocole de rendement, avec les protocoles qui n'ont pas répondu.
    func positions(holder: String) async -> PositionDiscovery {
        var positions: [YieldPosition] = []
        var failures: [Failure] = []
        for adapter in yieldAdapters {
            do {
                positions += try await adapter.discover(holder: holder)
            } catch {
                failures.append(Failure(protocolID: adapter.id, error: error))
            }
        }
        return PositionDiscovery(positions: positions, failures: failures)
    }
}
