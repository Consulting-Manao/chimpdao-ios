#if CHIMP_ADMIN
import SwiftUI

/// « Reserve money for this card » (Chimp Admin, D5) : ce qui est déjà mis de côté, le montant, une confirmation qui dit
/// que l'argent ne revient pas, puis le dépôt par la clé admin. Textes en anglais et non traduits, comme tout le mode admin.
struct AdminPrizeView: View {
    @State var model: AdminPrizeModel

    var body: some View {
        PrepareStepScreen(
            overline: "Partner card",
            title: "Reserve money",
            lead: "Test XLM from the admin key, set aside for \(model.title). Only this card can claim it, into its own wallet, in ChimpDAO."
        ) {
            PrepareFacts(rows: rows)
            if case .failed(let message) = model.reservation {
                ChimpNoticeBanner(text: untranslated("The prize contract couldn't be read."), marker: .error)
                ChimpTechnicalDetails(details: message)
            }
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: "Amount").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                ChimpInputField {
                    HStack {
                        TextField(text: $model.amountText) { Text(verbatim: "50") }
                            .keyboardType(.numberPad)
                            .chimpFont(.fieldM)
                        Text(verbatim: "XLM").chimpFont(.fieldM).foregroundStyle(.chimpTextSecondary)
                    }
                }
                if let problem = model.amountProblem {
                    ChimpFieldMessage(text: untranslated(problem), kind: .error)
                }
            }
            switch model.message {
            case .reserved(let text):
                ChimpNoticeBanner(text: untranslated(text), marker: .success)
            case .failed(let text):
                ChimpNoticeBanner(text: untranslated("Nothing was reserved. Try again."), marker: .error)
                ChimpTechnicalDetails(details: text)
            case nil:
                EmptyView()
            }
        } actions: {
            ChimpButton(untranslated(model.amount.map { "Reserve \($0) test XLM" } ?? "Reserve money"), size: .large,
                        isLoading: model.isReserving) {
                model.isConfirming = true
            }
            .disabled(!model.canReserve)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "Reserve money"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isReserving)
        .task { await model.load() }
        .confirmationDialog(Text(verbatim: "Reserve \(model.amount ?? 0) test XLM?"), isPresented: $model.isConfirming, titleVisibility: .visible) {
            Button { Task { await model.reserve() } } label: { Text(verbatim: "Reserve (it can't be taken back)") }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "The money leaves the admin key for the prize contract. Only \(model.title) can claim it. "
                + "The contract has no refund: if nobody claims it, it stays there.")
        }
    }

    private var rows: [(String, String)] {
        switch model.reservation {
        case .loading:
            [("Card", model.title), ("Already reserved", "…")]
        case .loaded(let reservation):
            [("Card", model.title), ("NFT number", String(format: "N°%04u", reservation.tokenID)),
             ("Already reserved", "\(AdminPrizeModel.xlmText(reservation.reserved)) XLM")]
        case .failed:
            [("Card", model.title), ("Already reserved", "unavailable")]
        }
    }
}
#endif
