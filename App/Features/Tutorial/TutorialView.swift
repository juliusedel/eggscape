import SwiftUI

/// First-launch tutorial in three steps: hold, tilt, sprint.
struct TutorialView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Step {
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let steps = [
        Step(
            symbol: "iphone",
            title: "Halten",
            text: "Dein Handy ist der Löffel. Halte es flach vor dir, so wie du gleich laufen willst."
        ),
        Step(
            symbol: "arrow.left.and.right.circle",
            title: "Kippen",
            text: "Kippe das Handy ganz sanft, damit das Ei in der Mitte bleibt. Kippst du zu stark, fällt es herunter."
        ),
        Step(
            symbol: "figure.run",
            title: "Sprinten",
            text: "Halte „Sprint“ gedrückt, um schneller zu laufen. Aber Vorsicht: Das Ei wackelt dann viel mehr."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    let step = steps[index]
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: step.symbol)
                            .font(.system(size: 96, weight: .regular))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)
                        Text(step.title)
                            .font(.largeTitle.bold())
                        Text(step.text)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < steps.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < steps.count - 1 ? "Weiter" : "Los geht’s")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .accessibilityIdentifier("tutorial.next")
        }
        .overlay(alignment: .topTrailing) {
            Button("Überspringen", action: onFinish)
                .padding()
                .accessibilityIdentifier("tutorial.skip")
        }
    }
}
