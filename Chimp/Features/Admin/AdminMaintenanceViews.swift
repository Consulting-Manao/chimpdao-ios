#if CHIMP_ADMIN
import SwiftUI
import UIKit

/// Onglet Maintenance de Chimp Admin : l'état du vault, et la clé admin (la changer ou la retirer).
struct AdminMaintenanceView: View {
    let session: AdminSession
    let vault: VaultHealthModel
    @State private var isConfirmingExtend = false
    @State private var isChangingKey = false
    @State private var isConfirmingRemove = false
    @State private var newKey = ""

    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChimpSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: ChimpSpacing.s) {
                    Text(verbatim: "Stellar Testnet").chimpFont(.overline).textCase(.uppercase).foregroundStyle(.chimpTextSecondary)
                    Text(verbatim: "Maintenance").chimpFont(.displayL).foregroundStyle(.chimpTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                vaultSection
                keySection
            }
            .padding(ChimpSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.chimpBackground))
        .navigationTitle(Text(verbatim: "Maintenance"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vault.refresh() }
        .refreshable {
            vault.refresh()
            await vault.waitForRefresh()
        }
        .confirmationDialog(Text(verbatim: "Extend the vault?"), isPresented: $isConfirmingExtend, titleVisibility: .visible) {
            Button { Task { await vault.extendVault() } } label: { Text(verbatim: "Extend") }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: extendMessage)
        }
        .confirmationDialog(Text(verbatim: "Remove the admin key from this iPhone?"), isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button(role: .destructive) { session.key.erase() } label: { Text(verbatim: "Remove the key") }
            Button(role: .cancel) {} label: { Text(verbatim: "Cancel") }
        } message: {
            Text(verbatim: "Chimp Admin will ask for a key again. The cards and their money are not affected.")
        }
    }

    // MARK: Vault

    private var vaultSection: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text(verbatim: "Savings vault").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary)
            HStack(spacing: ChimpSpacing.m) {
                Circle().fill(vaultColor).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.chimpOutline), lineWidth: ChimpBorder.thin))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ChimpSpacing.xxs) {
                    Text(verbatim: vaultTitle).chimpFont(.rowTitle).foregroundStyle(.chimpTextPrimary)
                    if let detail = vaultDetail {
                        Text(verbatim: detail).chimpFont(.caption).foregroundStyle(.chimpTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if vault.state == .loading { ProgressView() }
            }
            .padding(ChimpSpacing.lg + ChimpBorder.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
            .accessibilityElement(children: .combine)
            if case .soon = vault.state {
                ChimpButton(untranslated("Extend"), isLoading: vault.isExtending) { isConfirmingExtend = true }
                    .disabled(vault.isExtending || !session.hasKey)
            }
            switch vault.extendResult {
            case .extended:
                ChimpNoticeBanner(text: untranslated("The vault was extended."), marker: .success)
            case .failed(let message):
                ChimpNoticeBanner(text: untranslated("The vault wasn't extended. Try again."), marker: .error)
                ChimpTechnicalDetails(details: message)
            case nil:
                EmptyView()
            }
            if case .unavailable(let message) = vault.state {
                ChimpTechnicalDetails(details: message)
            }
        }
    }

    private func day(_ date: Date) -> String { date.formatted(.dateTime.day().month(.wide).year().locale(locale)) }

    private var vaultTitle: String {
        switch vault.state {
        case .loading: "Checking the vault…"
        case .ok(let until): "Vault OK until \(day(until))"
        case .soon(let until): "Vault expires on \(day(until))"
        case .expired(let on): "Vault expired on \(day(on))"
        case .unavailable: "Couldn't check the vault"
        }
    }

    private var vaultDetail: String? {
        switch vault.state {
        case .loading, .ok: nil
        case .soon: "Extend it now so savings keep working. The admin key pays, no card is needed."
        case .expired: "Extending isn't enough anymore. Ask Pamphile to restore it."
        case .unavailable: "Pull down to try again."
        }
    }

    private var vaultColor: Color {
        switch vault.state {
        case .ok: Color(.chimpPositive)
        case .soon: Color(.chimpWarning)
        case .expired, .unavailable: Color(.chimpNegative)
        case .loading: Color(.chimpSurfaceSecondary)
        }
    }

    private var extendMessage: String {
        let cost = vault.extendCost.map { " It costs about \(AdminSession.xlmText($0)) test XLM." } ?? ""
        return "The admin key pays to keep the vault alive for about 3 more months.\(cost) No money moves from the cards."
    }

    // MARK: Clé admin

    private var keySection: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text(verbatim: "Admin key").chimpFont(.displayS).foregroundStyle(.chimpTextPrimary)
            Text(verbatim: "Saved on this iPhone only.").chimpFont(.body).foregroundStyle(.chimpTextSecondary)
            if isChangingKey {
                ChimpInputField {
                    SecureField(text: $newKey) { Text(verbatim: "S…") }
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.none)
                        .chimpFont(.fieldM)
                } accessory: {
                    Button {
                        newKey = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    } label: { Text(verbatim: "Paste").chimpFont(.buttonSmall) }
                }
                if let error = session.key.errorMessage {
                    ChimpFieldMessage(text: untranslated(error), kind: .error)
                }
                ChimpButton(untranslated("Save the new key"), kind: .secondary) {
                    session.key.save(newKey)
                    newKey = ""
                    if session.key.errorMessage == nil {
                        isChangingKey = false
                        session.refreshBalance()
                    }
                }
                .disabled(newKey.isEmpty)
                ChimpButton(untranslated("Cancel"), kind: .link) {
                    newKey = ""
                    isChangingKey = false
                }
            } else {
                ChimpButton(untranslated("Change the key"), kind: .secondary) { isChangingKey = true }
                ChimpButton(untranslated("Remove the key"), kind: .destructive) { isConfirmingRemove = true }
            }
        }
    }
}
#endif
