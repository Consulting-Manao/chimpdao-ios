import SwiftUI

/// Une étape d'une opération en cours (création du compte, envoi).
struct ChimpProgressStep: Identifiable {
    enum State: Equatable {
        case done
        case current
        case failed
        case todo
    }

    let id: Int
    let label: Text
    let state: State
}

/// Liste d'étapes avec leur état (✓, roue, ✕, cercle vide), dans une carte. États absents de la maquette :
/// « Setting up your account » (onboarding, étape 4) et « Sending… » (Envoyer, étape C).
struct ChimpProgressSteps: View {
    let steps: [ChimpProgressStep]

    var body: some View {
        VStack(alignment: .leading, spacing: ChimpSpacing.m) {
            ForEach(steps) { step in
                row(step)
            }
        }
        .padding(ChimpSpacing.lg + ChimpBorder.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartoonSurface(RoundedRectangle(cornerRadius: ChimpRadius.panel), fill: Color(.chimpSurface), shadow: .card)
    }

    private func row(_ step: ChimpProgressStep) -> some View {
        HStack(spacing: ChimpSpacing.m) {
            ZStack {
                switch step.state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.chimpPositive)
                case .current:
                    ProgressView()
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.chimpNegative)
                case .todo:
                    Image(systemName: "circle").foregroundStyle(.chimpTextSecondary)
                }
            }
            .font(.system(size: 22, weight: .heavy))
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            step.label
                .chimpFont(.reviewStep)
                .foregroundStyle(step.state == .todo ? Color(.chimpTextSecondary) : Color(.chimpTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(stateLabel(step.state)))
    }

    private func stateLabel(_ state: ChimpProgressStep.State) -> LocalizedStringKey {
        switch state {
        case .done: "Done"
        case .current: "In progress"
        case .failed: "Failed"
        case .todo: "Not started"
        }
    }
}

#Preview {
    ChimpProgressSteps(steps: [
        ChimpProgressStep(id: 0, label: Text(verbatim: "Signed by Jungle"), state: .done),
        ChimpProgressStep(id: 1, label: Text(verbatim: "Checking with Stellar"), state: .current),
        ChimpProgressStep(id: 2, label: Text(verbatim: "Sending"), state: .todo),
    ])
    .padding()
    .background(Color(.chimpBackground))
}
