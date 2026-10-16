import SwiftUI

/// N2 · « From Base · via ROZO » (tranche 2, D4 ; construit sans maquette avec le design system, décisions de Barth du
/// 2026-10-16) : montant et devis, puis l'adresse de dépôt de ROZO, la durée de validité de la commande et son suivi. Le
/// texte « ROZO holds your money… » est obligatoire, sur les deux états ; Circle CCTP est présenté comme la voie sans
/// intermédiaire. Quantités seulement, jamais de dollars. L'app n'envoie rien sur Base.
struct RozoTransferView: View {
    @Bindable var model: RozoTransferModel
    let explorerURL: (String) -> URL
    let onBack: () -> Void
    let onDone: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.chimpScreenInsets) private var screenInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copied: String?

    private var isSmallScreen: Bool { screenInsets.top < 30 }
    private var clipboard: AddressClipboard { SystemAddressClipboard() }

    var body: some View {
        VStack(spacing: 0) {
            ChimpHeader(title: "From \(model.config.sourceChainName)", subtitle: "Via ROZO, a middleman", onBack: onBack)
            switch model.phase {
            case .entry, .creating:
                entry
            case .order(let order):
                orderContent(order)
            case .failed(let issue):
                failure(issue)
            }
        }
        .background(Color(.chimpBackground))
        .sensoryFeedback(.error, trigger: model.rejectedKeyCount)
        .task(id: model.order?.id) { await model.track() }
    }

    /// Texte obligatoire (décision de Barth du 2026-10-16).
    private var trustNotice: some View {
        ChimpNoticeBanner(
            text: "ROZO holds your money during the transfer. If something goes wrong, refunds go through ROZO's support.",
            marker: .error
        )
    }

    // MARK: Montant

    private var entry: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: ChimpSpacing.m) {
                    trustNotice
                    sendCard
                    getCard
                    quoteDetails
                    Text("No middleman: Circle CCTP moves USDC from Ethereum straight to your account.")
                        .chimpFont(.caption)
                        .foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ChimpButton("Get a deposit address", isLoading: model.phase == .creating) {
                        Task { await model.createOrder() }
                    }
                    .disabled(!model.canCreateOrder || model.phase == .creating)
                }
                .padding(.horizontal, ChimpSpacing.xxl)
                .padding(.top, ChimpSpacing.ml)
                .padding(.bottom, ChimpSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            if !dynamicTypeSize.isAccessibilitySize {
                ChimpKeypad(mode: .amount, isCompact: isSmallScreen) { key in
                    ChimpSoundPlayer.shared.play(.tap)
                    model.press(key)
                }
                .padding(.horizontal, ChimpSpacing.lg)
                .padding(.bottom, screenInsets.hasHomeIndicator ? ChimpSpacing.bottomBar.bottom : ChimpSpacing.xl)
            }
        }
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("You'd send").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.s) {
                ChimpTabularText.text(model.amount.displayText(locale: locale), style: .displayL, dynamicTypeSize: dynamicTypeSize)
                    .chimpFont(.displayL)
                    .foregroundStyle(model.amount.isEmpty ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(verbatim: "USDC").chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("You'd send"))
            Text("on \(model.config.sourceNetworkName) · \(amountText(model.config.minimumAmount)) to \(amountText(model.config.maximumAmount)) on testnet")
                .chimpFont(.captionStrong)
                .foregroundStyle(.chimpTextSecondary)
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
    }

    private var getCard: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
            Text("Into Main you'd get").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
            Group {
                switch model.quoteState {
                case .quoted(let quote):
                    Text(verbatim: amountText(quote.destinationAmount)).chimpFont(.displayL)
                case .loading:
                    ProgressView()
                default:
                    Text(verbatim: "—").chimpFont(.displayL).foregroundStyle(.chimpTextSecondary)
                }
            }
            .foregroundStyle(.chimpTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
        }
        .padding(.horizontal, ChimpSpacing.l)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var quoteDetails: some View {
        switch model.quoteState {
        case .quoted(let quote):
            Text("ROZO's fee: \(amountText(quote.fee)) · price from ROZO, testnet")
                .chimpFont(.mono)
                .foregroundStyle(.chimpTextSecondary)
        case .failed(let issue):
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                ChimpFieldMessage(text: message(for: issue), kind: .error)
                if issue == .unavailable {
                    ChimpPillButton("Retry") { Task { await model.refreshQuote() } }
                }
                if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
            }
        case .idle:
            Text("Type an amount to see what arrives.").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
        case .loading:
            EmptyView()
        }
    }

    // MARK: Commande

    private func orderContent(_ order: RozoOrder) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.l) {
                trustNotice
                switch order.status {
                case .unpaid:
                    instructions(order)
                case .payinCompleted, .payoutStarted:
                    ChimpNoticeBanner(text: "ROZO got your USDC. Paying your Main now…", marker: .info) { ProgressView() }
                case .completed where model.isArrivalVerified:
                    arrived(order)
                case .completed where model.arrivalCheck == .notFound:
                    ChimpySays(text: "ROZO says it paid, but I can't find the payment on Stellar. Write to ROZO's support with the order number below.", pose: .stop)
                case .completed:
                    ChimpNoticeBanner(text: "ROZO says it paid. Checking on Stellar…", marker: .info) { ProgressView() }
                case .bounced:
                    ChimpySays(text: "ROZO sent this order back: nothing arrived. Write to ROZO's support with the order number below.", pose: .stop)
                case .expired:
                    ChimpySays(text: "This order expired. If you sent USDC after it expired, write to ROZO's support with the order number below.", pose: .stop)
                case .other(let raw):
                    ChimpNoticeBanner(text: "ROZO says: \(raw)", marker: .info)
                }
                if model.isTrackingStale {
                    Text("Can't reach ROZO right now. Still checking…").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                }
                orderNumber(order)
                if order.status == .completed, model.isArrivalVerified || model.arrivalCheck == .notFound {
                    ChimpButton("Done", action: onDone)
                } else if order.status == .bounced || order.status == .expired {
                    ChimpButton("Start over", kind: .secondary) { model.startOver() }
                }
            }
            .padding(.horizontal, ChimpSpacing.xxl)
            .padding(.vertical, ChimpSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Envoyer **exactement** ce montant, sur ce réseau, à cette adresse, avant l'heure dite.
    private func instructions(_ order: RozoOrder) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                Text("Send exactly").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: ChimpSpacing.m) {
                    Text(verbatim: amountText(order.sourceAmount))
                        .chimpFont(.displayL)
                        .foregroundStyle(.chimpTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                    copyPill(id: "amount", shown: RozoClient.amountText(order.sourceAmount), value: RozoClient.amountText(order.sourceAmount))
                }
                Text("USDC on \(model.config.sourceNetworkName), from your own wallet").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
            }
            .padding(.horizontal, ChimpSpacing.l)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface))

            ChimpDetailList(items: [
                ChimpDetailItem(id: "deposit", label: "To ROZO's address", value: order.depositAddress, isMonospaced: true),
                ChimpDetailItem(id: "into", label: "ROZO pays your Main", value: model.recipient, isMonospaced: true),
            ])
            copyPill(id: "deposit", shown: shortEVM(order.depositAddress), value: order.depositAddress)

            countdown(order)
            Text("Only USDC on \(model.config.sourceNetworkName), and only this amount: anything else can't be matched to your order.")
                .chimpFont(.caption)
                .foregroundStyle(.chimpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChimpNoticeBanner(text: "Waiting for your USDC…", marker: .info) { ProgressView() }
        }
    }

    private func countdown(_ order: RozoOrder) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let remaining = RozoTransferModel.remaining(until: order.expiresAt, now: context.date) {
                if remaining > 0 {
                    Text("Valid for \(RozoTransferModel.countdown(remaining))")
                        .chimpFont(.rowTitle)
                        .foregroundStyle(.chimpTextPrimary)
                        .monospacedDigit()
                } else {
                    Text("This order has expired. Don't send anything to it.")
                        .chimpFont(.rowTitle)
                        .foregroundStyle(.chimpNegative)
                }
            }
        }
    }

    private func arrived(_ order: RozoOrder) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ChimpNoticeBanner(text: "Arrived via ROZO in Main: \(amountText(order.destinationAmount)) · checked on Stellar", marker: .success)
            if let hash = order.destinationTxHash {
                ChimpPillButton("See ROZO's payment on Stellar") { openURL(explorerURL(hash)) }
            }
        }
    }

    private func orderNumber(_ order: RozoOrder) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
            Text("ROZO order").chimpFont(.label).textCase(.uppercase).foregroundStyle(.chimpTextSecondary)
            Text(verbatim: order.id).chimpFont(.mono).foregroundStyle(.chimpTextPrimary).textSelection(.enabled)
            Text("Keep it if you need ROZO's support (hi@rozo.ai).").chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
        }
    }

    // MARK: Erreur

    private func failure(_ issue: RozoTransferModel.Issue) -> some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.l) {
            trustNotice
            ChimpySays(text: message(for: issue), pose: issue == .mismatch ? .stop : .crawl)
            ChimpButton("Try again") { model.startOver() }
            if let details = model.technicalDetails { ChimpTechnicalDetails(details: details) }
            Spacer()
        }
        .padding(.horizontal, ChimpSpacing.xxl)
        .padding(.top, ChimpSpacing.l)
    }

    private func message(for issue: RozoTransferModel.Issue) -> LocalizedStringKey {
        switch issue {
        case .tooLow: "That's below ROZO's testnet minimum of \(amountText(model.config.minimumAmount))."
        case .tooHigh: "ROZO's testnet takes \(amountText(model.config.maximumAmount)) at most."
        case .addressRefused: "ROZO doesn't accept this address."
        case .mismatch: "ROZO's order didn't match what you asked for, so I'm not showing it. Nothing was sent."
        case .unavailable: "ROZO isn't answering right now."
        }
    }

    // MARK: Outils

    private func amountText(_ value: Decimal) -> String {
        SendAsset.usdc.displayedWithCode(value, locale: locale)
    }

    private func shortEVM(_ address: String) -> String {
        address.count > 12 ? "\(address.prefix(6))…\(address.suffix(4))" : address
    }

    private func copyPill(id: String, shown: String, value: String) -> some View {
        ChimpAddressPill(address: shown, isCopied: copied == id) {
            clipboard.copy(value)
            copied = id
            Task {
                try? await Task.sleep(for: ChimpMotion.Copied.display)
                if copied == id { copied = nil }
            }
        }
    }
}
