import SwiftUI

/// First-launch tutorial in three steps (hold, tilt, sprint), then the player's name. "Überspringen" skips the steps
/// but not the name, so every new player is asked for it once; it can stay empty.
struct TutorialView: View {
    /// Receives the name as typed; the caller trims and stores it.
    var onFinish: (String) -> Void
    @State private var page = 0
    @State private var isAskingName = false
    @State private var name: String
    @FocusState private var isNameFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Keeps a page's text clear of the page dots below, also with large text.
    @ScaledMetric private var pageInset = 40.0

    /// - Parameter name: the current player name, prefilled in the last step.
    init(name: String, onFinish: @escaping (String) -> Void) {
        self.onFinish = onFinish
        _name = State(initialValue: name)
    }

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
        Group {
            if isAskingName {
                nameStep
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                stepPages
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.default, value: isAskingName)
    }

    // MARK: Steps

    private var stepPages: some View {
        VStack(spacing: 0) {
            // A bar of its own above the pages, so the button never covers their text, at any text size.
            HStack {
                Spacer(minLength: 0)
                // A large control is at least 44 pt high (50 pt at the default text size) and grows with the text.
                Button(action: askForName) {
                    Text("Überspringen")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .secondaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("tutorial.skip")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    let step = steps[index]
                    stepPage(symbol: step.symbol, title: step.title, text: step.text)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < steps.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    askForName()
                }
            } label: {
                Text("Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .accessibilityIdentifier("tutorial.next")
        }
    }

    // MARK: Name

    /// The field and the button sit at the bottom, outside the scrolling text: the keyboard pushes them up together,
    /// so it can hide neither, and only the text above them scrolls if the room gets short.
    private var nameStep: some View {
        VStack(spacing: 0) {
            stepPage(
                symbol: "person.crop.circle",
                title: "Wie heißt du?",
                text: "Diesen Namen sehen die anderen, wenn ihr zusammen spielt. Ohne Namen heißt du „Spieler“."
            )
            .onTapGesture { isNameFocused = false }

            VStack(spacing: 16) {
                TextField("Spielername", text: $name)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isNameFocused)
                    .onSubmit(finish)
                    .onChange(of: name) { _, value in
                        if value.count > SettingsStore.maxNameLength {
                            name = String(value.prefix(SettingsStore.maxNameLength))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("tutorial.name")

                Text("Ändern kannst du ihn jederzeit in den Einstellungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: finish) {
                    Text("Los geht’s")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .primaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("tutorial.done")
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear {
            // Only a new player starts typing right away; a name to keep (the tutorial opened again from the
            // settings) needs no keyboard.
            if name.isEmpty {
                isNameFocused = true
            }
        }
    }

    private func stepPage(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // Decorative, and it does not grow with the text: at accessibility sizes the text needs the room,
                    // as it does with the keyboard up.
                    if !dynamicTypeSize.isAccessibilitySize, !isNameFocused {
                        Image(systemName: symbol)
                            .font(.system(size: 96, weight: .regular))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(text)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, pageInset)
                // At least a page high, so a step that fits stays centered and only a longer one scrolls.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func askForName() {
        isAskingName = true
    }

    private func finish() {
        isNameFocused = false
        onFinish(name)
    }
}
