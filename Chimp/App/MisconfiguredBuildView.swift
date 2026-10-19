import SwiftUI

/// Ce build ne peut pas démarrer : sa configuration réseau est incomplète (mainnet pas encore prêt). Un écran pour le
/// développeur, jamais pour un utilisateur : un build Release ne doit pas être publié dans cet état.
struct MisconfiguredBuildView: View {
    let error: NetworkConfigError

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            Text("This build isn't ready")
                .chimpFont(.displayL)
                .foregroundStyle(.chimpTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Its network settings are incomplete, so it won't connect to anything. Nothing was sent.")
                .chimpFont(.bodyL)
                .foregroundStyle(.chimpTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if case let .incomplete(network, missing) = error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Missing for \(network.rawValue):")
                    ForEach(missing, id: \.self) { Text(verbatim: "· \($0)") }
                }
                .chimpFont(.mono)
                .foregroundStyle(.chimpTextSecondary)
            }
        }
        .padding(ChimpSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.chimpBackground))
    }
}
