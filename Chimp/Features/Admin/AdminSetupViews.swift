#if CHIMP_ADMIN
import SwiftUI
import UIKit

/// « Set up Chimp Admin » : le seul écran avant la première utilisation, pour coller la clé admin testnet.
struct AdminSetupView: View {
    let session: AdminSession
    @State private var input = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                    Text(verbatim: "Chimp Admin").chimpFont(.overline).textCase(.uppercase).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: "Set up Chimp Admin").chimpFont(.displayL).foregroundStyle(.chimpTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Paste the admin key. It starts with S. It stays on this iPhone only, and it pays for preparing cards and sending test money.")
                        .chimpFont(.bodyL).foregroundStyle(.chimpTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: ChimpSpacing.xs) {
                    ChimpInputField {
                        SecureField(text: $input) { Text(verbatim: "S…") }
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textContentType(.none)
                            .chimpFont(.fieldM)
                    } accessory: {
                        Button {
                            input = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        } label: { Text(verbatim: "Paste").chimpFont(.buttonSmall) }
                    }
                    if let error = session.key.errorMessage {
                        ChimpFieldMessage(text: untranslated(error), kind: .error)
                    }
                }
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .safeAreaInset(edge: .bottom) {
            ChimpButton(untranslated("Save the key"), size: .large) {
                session.key.save(input)
                input = ""
                session.refreshBalance()
            }
            .disabled(input.isEmpty)
            .padding(.horizontal, ChimpSpacing.screenMargin)
            .padding(.vertical, ChimpSpacing.s)
            .background(Color(.chimpBackground))
        }
    }
}

/// La ligne d'état en haut de chaque onglet : « Admin key ✓ · 19,920 test XLM ».
struct AdminStatusLine: View {
    let session: AdminSession

    var body: some View {
        Text(verbatim: session.statusText)
            .chimpFont(.captionStrong)
            .foregroundStyle(session.key.isUnexpectedAdmin || session.balance == .unavailable ? Color(.chimpNegative) : Color(.chimpTextPrimary))
            .padding(.vertical, ChimpSpacing.xs)
            .padding(.horizontal, ChimpSpacing.m)
            .frame(maxWidth: .infinity)
            .background(Color(.chimpSurfaceSecondary))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
