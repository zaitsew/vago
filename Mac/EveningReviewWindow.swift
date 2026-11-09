import AppKit
import SwiftUI
import VagoKit

/// Lab: the evening review as a small window of its own. Two variants, picked in Settings, Lab:
/// one card at a time (`ReviewCardsView`) or one list (`ReviewListView`). Both answer through
/// `AppModel.correctCall`, so minutes move and rules are learned exactly as in the Day window.
@MainActor
enum EveningReviewWindow {
    /// The unsure places, largest first, at most five.
    static let limit = 5

    static func items(_ model: AppModel) -> [CallItem] {
        Array(model.allCalls.filter(\.unsure).sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

    /// A fresh window that holds today's unsure places as they are now.
    static func make(model: AppModel) -> HostedWindow {
        let items = items(model)
        let cards = model.eveningReviewStyle == .cards
        return HostedWindow(title: "Evening review", size: NSSize(width: cards ? 420 : 560, height: cards ? 360 : 420),
                            minSize: NSSize(width: 420, height: 360), resizable: false, autosaveName: "VagoEveningReview") { window in
            let close: @MainActor () -> Void = { [weak window] in window?.close() }
            if cards {
                return AnyView(ReviewCardsView(items: items, answer: { model.correctCall($0, as: $1) }, close: close))
            }
            return AnyView(ReviewListView(items: items, answer: { model.correctCall($0, as: $1) }, close: close))
        }
    }
}

/// "Nothing to review today." and Close.
private struct ReviewEmpty: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Nothing to review today.").font(.title3.weight(.medium))
            Button("Close", action: close).keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func reasonText(_ item: CallItem) -> String {
    let text = Format.reason(item.reason)
    return text.isEmpty ? "Vago could not tell." : text
}

// MARK: - Variant A: cards

struct ReviewCardsView: View {
    let items: [CallItem]
    let answer: (CallItem, Bucket) -> Void
    let close: () -> Void

    @State private var index = 0
    @State private var learned = 0

    var body: some View {
        if items.isEmpty {
            ReviewEmpty(close: close)
        } else if index >= items.count {
            VStack(spacing: 16) {
                Text("Done — \(learned) \(learned == 1 ? "rule" : "rules") learned").font(.title2.weight(.semibold))
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            card(items[index])
        }
    }

    private func card(_ item: CallItem) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    Circle()
                        .fill(i < index ? AnyShapeStyle(Color.accentColor) : i == index ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Place \(index + 1) of \(items.count)")
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(item.label)
                    .font(.system(size: 30, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.middle)
                Text(Format.duration(item.seconds))
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(reasonText(item))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 320)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button { pick(item, .procrastination) } label: {
                    Text("← Waste").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .tint(Palette.waste)
                Button { pick(item, .productive) } label: {
                    Text("Work →").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .tint(Palette.work)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pick(_ item: CallItem, _ bucket: Bucket) {
        answer(item, bucket)
        learned += 1
        index += 1
    }
}

// MARK: - Variant B: list

struct ReviewListView: View {
    let items: [CallItem]
    let answer: (CallItem, Bucket) -> Void
    let close: () -> Void

    /// Chosen answers by place; a place with none stays unsure.
    @State private var picks: [String: Bucket] = [:]

    var body: some View {
        if items.isEmpty {
            ReviewEmpty(close: close)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work or waste?").font(.headline)
                    Text("Each answer moves its minutes and becomes a rule. Leave a row blank to keep it unsure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Divider() }
                            row(item)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
                HStack {
                    Text("\(picks.count) of \(items.count) answered").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done", action: finish).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private func row(_ item: CallItem) -> some View {
        HStack(spacing: 12) {
            Text(item.label).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Format.duration(item.seconds))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Picker("Count as", selection: Binding<Bucket?>(get: { picks[item.id] }, set: { picks[item.id] = $0 })) {
                Text("Work").tag(Bucket?.some(.productive))
                Text("Waste").tag(Bucket?.some(.procrastination))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .frame(height: 44)
    }

    private func finish() {
        for item in items { if let bucket = picks[item.id] { answer(item, bucket) } }
        close()
    }
}
