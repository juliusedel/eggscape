import SwiftUI

/// Results of a single-player run.
struct RunResultsView: View {
    let outcome: RunOutcome
    var onRestart: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(outcome.finished ? "Im Ziel!" : "Alle Eier kaputt")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("results.title")
            if outcome.isPersonalBest {
                Label("Neue Bestleistung!", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                if outcome.finished {
                    GridRow {
                        Text("Zeit")
                        Text(verbatim: RaceFormat.time(outcome.time))
                            .monospacedDigit()
                            .bold()
                            .accessibilityIdentifier("results.time")
                    }
                }
                GridRow {
                    Text("Strecke")
                    Text("\(RaceFormat.meters(outcome.meters)) m").monospacedDigit().bold()
                }
                GridRow {
                    Text("Verlorene Eier")
                    Text(verbatim: "\(outcome.eggsLost)").monospacedDigit().bold()
                }
            }
            .font(.title3)
            if let reward = outcome.reward, reward.total > 0 {
                HStack(spacing: 8) {
                    CoinIcon(size: 26)
                    Text("+\(reward.total) Münzen")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.14), in: .capsule)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("results.coins")
            }
            HStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Fertig").frame(maxWidth: .infinity, minHeight: 32)
                }
                .secondaryActionStyle()
                .accessibilityIdentifier("results.done")
                Button(action: onRestart) {
                    Text("Nochmal").frame(maxWidth: .infinity, minHeight: 32)
                }
                .primaryActionStyle()
                .accessibilityIdentifier("results.again")
            }
            .font(.headline)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 400)
        .floatingPanel()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.2))
    }
}
