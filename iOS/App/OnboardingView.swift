import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private enum Step: Int, CaseIterable {
        case welcome, access, procrastination, ambiguous, productive
    }

    @State private var step: Step = .welcome
    @State private var picking: SelectionKind?
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .padding(.horizontal)
                .padding(.top)
            Spacer()
            content
                .padding(.horizontal, 28)
                .transition(.opacity)
                .id(step)
            Spacer()
            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .animation(.smooth, value: step)
        .sheet(item: $picking) { kind in PickerSheet(kind: kind) }
        .onAppear {
            // Reopened after the access was granted but the lists were never finished.
            if model.authorized && step == .welcome && model.count(.procrastination) == 0 { step = .procrastination }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page("😄", "Vago", "Counts the time you lose to scrolling and the time you work, on your iPhone and your Mac. The goal: at most 30 minutes of procrastination a day.")
        case .access:
            page("🔒", "Screen Time access", "Vago uses Apple's Screen Time to count. It sees which of your chosen apps ran and for how long. Nothing leaves your devices and iCloud.")
        case .procrastination:
            listPage("📱", "Procrastination", "Apps and categories that only cost you time.", suggestion: "Try Social, Entertainment and Games.", kind: .procrastination)
        case .ambiguous:
            listPage("🤔", "Work or scroll", "Apps you use for both. They ask “Work or scroll?” each time they open.", suggestion: "Try Instagram, YouTube, X, LinkedIn, Telegram, WhatsApp.", kind: .ambiguous)
        case .productive:
            listPage("💼", "Work", "Apps that count as work and never get paused.", suggestion: "Try Productivity, Education, and your work tools. You can skip this.", kind: .productive)
        }
    }

    private func page(_ emoji: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 80))
            Text(title).font(.largeTitle.weight(.bold))
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func listPage(_ emoji: String, _ title: String, _ text: String, suggestion: String, kind: SelectionKind) -> some View {
        VStack(spacing: 16) {
            page(emoji, title, text)
            Text(suggestion).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("An app you pick in a more specific list wins: Work beats Both, and Both beats Procrastination.")
                .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button {
                picking = kind
            } label: {
                Label(model.count(kind) == 0 ? "Choose apps" : "\(model.count(kind)) selected · change",
                      systemImage: "square.grid.2x2")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let message = model.errorMessage, step == .access {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                Task { await advance() }
            } label: {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working || !canAdvance)
        }
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: "Get started"
        case .access: "Allow Screen Time"
        case .procrastination, .ambiguous: "Continue"
        case .productive: "Start counting"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .procrastination: model.count(.procrastination) > 0
        case .ambiguous: model.count(.ambiguous) > 0
        default: true
        }
    }

    private func advance() async {
        switch step {
        case .welcome:
            step = .access
        case .access:
            working = true
            await model.requestAuthorization()
            working = false
            if model.authorized { step = .procrastination }
        case .procrastination:
            step = .ambiguous
        case .ambiguous:
            step = .productive
        case .productive:
            working = true
            await model.finishOnboarding()
            working = false
        }
    }
}
