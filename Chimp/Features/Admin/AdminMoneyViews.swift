#if CHIMP_ADMIN
import SwiftUI
import UIKit

/// Onglet Money de Chimp Admin : le solde de l'admin, et « Send test money » vers une adresse G… ou C….
struct AdminMoneyView: View {
    let session: AdminSession
    @Bindable var model: AdminMoneyModel

    var body: some View {
        PrepareStepScreen(overline: "Stellar Testnet", title: "Money",
                          lead: "Test XLM paid by the admin key. It has no value. When the admin runs low, friendbot tops it up.") {
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: balanceText).chimpFont(.displayXL).foregroundStyle(.chimpTextPrimary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(verbatim: "test XLM on the admin key").chimpFont(.bodyL).foregroundStyle(.chimpTextSecondary)
            }
            .padding(ChimpSpacing.lg + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
            .accessibilityElement(children: .combine)

            Text(verbatim: "Send test money").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary)
                .padding(.top, ChimpSpacing.s)
            VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                Text(verbatim: "To").chimpFont(.captionStrong).foregroundStyle(.chimpTextSecondary)
                ChimpInputField {
                    TextField(text: $model.address) { Text(verbatim: "G… or C…") }
                        .chimpFont(.address)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } accessory: {
                    Button {
                        model.address = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    } label: { Text(verbatim: "Paste").chimpFont(.buttonSmall) }
                }
                if let problem = model.addressProblem {
                    ChimpFieldMessage(text: untranslated(problem), kind: .error)
                }
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
            case .sent(let text):
                ChimpNoticeBanner(text: untranslated(text), marker: .success)
            case .failed(let text):
                ChimpNoticeBanner(text: untranslated("The test money wasn't sent. Try again."), marker: .error)
                ChimpTechnicalDetails(details: text)
            case nil:
                EmptyView()
            }
        } actions: {
            ChimpButton(untranslated(model.amount.map { "Send \($0) test XLM" } ?? "Send test money"), size: .large,
                        isLoading: model.isSending) {
                Task { await model.send() }
            }
            .disabled(!model.canSend)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "Money"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { session.refreshBalance() }
        .onAppear { session.refreshBalance() }
    }

    private var balanceText: String {
        switch session.balance {
        case .xlm(let amount): AdminSession.xlmText(amount)
        case .unavailable: "—"
        case .unknown, .loading: "…"
        }
    }
}
#endif
