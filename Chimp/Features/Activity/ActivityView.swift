import SwiftUI

/// Onglet Activity (I1, maquette « tickets de caisse » du 2026-09-30) : un ticket par journée, les plus récentes d'abord,
/// filtres par tiroir, paiement en attente en haut ; toucher une ligne ouvre son reçu.
///
/// États absents de la maquette (textes proposés, DESIGN_NOTES §12) : chargement (ticket squelette), vide, erreur réseau
/// (sans rien : message + « Try again » ; avec des lignes gardées : bandeau + « Retry »), lecture en cours.
struct ActivityView: View {
    @Bindable var model: ActivityViewModel
    /// Paiement en attente touché : la coque ouvre l'écran d'état d'Envoyer.
    var onPending: () -> Void = {}
    /// « Pay again » ou « Send back » du reçu : la coque ouvre Envoyer prérempli.
    var onSendPrefilled: (SendPrefill) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ChimpTabHeader(title: "Activity") { chips }
            ScrollView {
                ActivityContent(model: model, onPending: onPending)
                    .padding(.horizontal, 26)
                    .padding(.top, ChimpSpacing.lg)
                    .padding(.bottom, ChimpSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                ChimpSoundPlayer.shared.play(.branch)
                await model.refresh()
            }
        }
        .background(Color(.chimpBackground))
        .task { await model.refresh() }
        .activityReceiptSheet(model: model, onSendPrefilled: onSendPrefilled)
    }

    // MARK: Filtres

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ChimpSpacing.s) {
                ChimpFilterChip(title: String(localized: "All drawers"), isSelected: model.filter == .all) { model.filter = .all }
                ForEach(model.drawers) { drawer in
                    ChimpFilterChip(title: drawer.name, isSelected: model.filter == .drawer(drawer.address)) {
                        model.filter = .drawer(drawer.address)
                    }
                    .accessibilityLabel(Text(drawer.title))
                }
            }
            .padding(.horizontal, ChimpSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

}

/// Reçu d'une ligne touchée (I1.1d), partagé par l'onglet Activity et l'historique d'un tiroir (B2, B3).
private struct ActivityReceiptSheetModifier: ViewModifier {
    @Bindable var model: ActivityViewModel
    let onSendPrefilled: (SendPrefill) -> Void
    /// Envoi choisi dans le reçu : Envoyer s'ouvre une fois la feuille refermée.
    @State private var chosenSend: SendPrefill?

    func body(content: Content) -> some View {
        content
            .chimpSheet(isPresented: isReceiptPresented, height: ChimpSize.cardTapSheetHeight, fitsContent: true, onDismiss: {
                if let prefill = chosenSend {
                    chosenSend = nil
                    onSendPrefilled(prefill)
                }
            }) {
                if let record = model.selectedRecord, let receipt = model.receipt(for: record) {
                    ActivityReceiptSheet(receipt: receipt, model: model) { prefill in
                        chosenSend = prefill
                        model.selectedRecord = nil
                    }
                }
            }
    }

    private var isReceiptPresented: Binding<Bool> {
        Binding(get: { model.selectedRecord != nil }, set: { if !$0 { model.selectedRecord = nil } })
    }
}

extension View {
    /// Ouvre le reçu de `model.selectedRecord` ; « Pay again » et « Send back » appellent `onSendPrefilled` une fois la
    /// feuille refermée.
    func activityReceiptSheet(model: ActivityViewModel, onSendPrefilled: @escaping (SendPrefill) -> Void) -> some View {
        modifier(ActivityReceiptSheetModifier(model: model, onSendPrefilled: onSendPrefilled))
    }
}

/// Contenu sous l'en-tête : tickets et états. Séparé de la vue défilante.
struct ActivityContent: View {
    @Bindable var model: ActivityViewModel
    /// Filtre imposé (historique d'un tiroir, B2 et B3) ; sinon celui des pastilles de l'onglet.
    var filter: ActivityViewModel.Filter?
    var onPending: () -> Void = {}

    private var shownFilter: ActivityViewModel.Filter { filter ?? model.filter }
    /// Textes de chargement et d'état vide tirés au hasard (`ChimpyLines`).
    @State private var seed = ChimpyLines.seed()

    var body: some View { content }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            loading
        case .failed:
            failure
        case .loaded:
            VStack(alignment: .leading, spacing: 18) {
                if model.isShowingStaleData {
                    ChimpNoticeBanner(text: "Couldn't refresh. Showing what this phone already has.", marker: .error) {
                        ChimpPillButton("Retry") { Task { await model.refresh() } }
                    }
                }
                if model.isEmpty(for: shownFilter) {
                    if case .drawer = shownFilter {
                        ChimpySays(text: "Nothing moved here yet.", pose: .banana)
                    } else {
                        ChimpySays(line: ChimpyLines.pick(ChimpyLines.empty, seed: seed), pose: .banana)
                    }
                }
                ForEach(Array(model.tickets(for: shownFilter).enumerated()), id: \.element.id) { index, ticket in
                    ticketView(ticket, tilt: index.isMultiple(of: 2) ? -0.6 : 0.5)
                        .chimpCascadeAppear(index: index)
                }
                if model.isSyncing {
                    HStack(spacing: ChimpSpacing.s) {
                        ProgressView()
                        Text("Reading older days on Stellar…")
                            .chimpFont(.caption)
                            .foregroundStyle(.chimpTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
                if filter == nil ? (!model.records.isEmpty || model.pending != nil) : !model.visibleRecords(for: shownFilter).isEmpty {
                    Text("Stellar only keeps about a week of history. What this phone has seen stays here.")
                        .chimpFont(.captionS)
                        .foregroundStyle(.chimpTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }


    private func ticketView(_ ticket: ActivityTicket, tilt: Double) -> some View {
        ChimpTicket(
            title: ticket.title, date: ticket.date, net: ticket.net, netColor: color(ticket.netTone),
            showsSeal: !ticket.isPending, tilt: tilt
        ) {
            ForEach(Array(ticket.rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    if let record = row.record { model.selectedRecord = record } else { onPending() }
                } label: {
                    ChimpTicketRow(
                        title: row.title, meta: row.meta, stamp: row.stamp.text, stampColor: row.stamp.color,
                        stampTilt: index.isMultiple(of: 2) ? -3 : 2.5, amount: row.amount, amountColor: color(row.tone)
                    )
                }
                .buttonStyle(ChimpPressableStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint(row.record == nil ? Text("Opens the payment's status") : Text("Opens the receipt"))
            }
        }
    }

    private func color(_ tone: ActivityTone) -> Color {
        switch tone {
        case .positive: Color(.chimpStampReceived)
        case .negative: Color(.chimpStampPaid)
        case .neutral: Color(.chimpTicketInk)
        }
    }

    // MARK: Chargement et erreur

    private var loading: some View {
        VStack(alignment: .leading, spacing: 18) {
            ChimpTicket(title: "Today", date: "Sep 30", net: "+$00.00", tilt: -0.6) {
                ForEach(0..<3, id: \.self) { _ in
                    ChimpTicketRow(title: "You paid GAAA…AAAA", meta: "00:00 · from Main", stamp: "Paid", stampColor: Color(.chimpTicketRule), amount: "−$00.00")
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
            HStack(spacing: ChimpSpacing.s) {
                ProgressView()
                Text(ChimpyLines.pick(ChimpyLines.loading, seed: seed))
                    .chimpFont(.caption)
                    .foregroundStyle(.chimpTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private var failure: some View {
        VStack(spacing: ChimpSpacing.xl) {
            ChimpySays(text: "I can't reach the jungle right now. Check your connection.", pose: .crawl)
            ChimpButton("Try again") { Task { await model.refresh() } }
        }
        .padding(.top, ChimpSpacing.s)
    }
}

extension ActivityStamp {
    /// Textes validés par Barth le 2026-09-30 (en capitales à l'affichage).
    var text: LocalizedStringKey {
        switch self {
        case .paid: "Paid"
        case .gotIt: "Got it"
        case .moved: "Moved"
        case .newCard: "New card"
        case .pending: "Pending"
        }
    }

    var color: Color {
        switch self {
        case .paid: Color(.chimpStampPaid)
        case .gotIt: Color(.chimpStampReceived)
        case .moved: Color(.chimpTicketMuted)
        case .newCard: Color(.chimpStampCard)
        case .pending: Color(.chimpStampPending)
        }
    }
}
