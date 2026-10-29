import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity: the readout in the Dynamic Island and on the Lock Screen; during a
/// focus session the tree and the time left take its place.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VagoActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding()
                .activityBackgroundTint(context.state.tintValue.color.opacity(0.18))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(state.focusStage ?? state.emoji).font(.largeTitle)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = state.focusEnd {
                        Text(timerInterval: Date.now...max(end, .now.addingTimeInterval(1)), countsDown: true)
                            .font(.title2.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90, alignment: .trailing)
                    } else {
                        Text("\(state.minutesUsed)/\(state.limitMinutes)m")
                            .font(.title2.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let start = state.focusStart, let end = state.focusEnd {
                        ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(.green)
                    } else {
                        ProgressView(value: min(Double(state.minutesUsed) / Double(max(state.limitMinutes, 1)), 1))
                            .tint(state.tintValue.color)
                    }
                }
            } compactLeading: {
                Text(state.focusStage ?? state.emoji)
            } compactTrailing: {
                if let end = state.focusEnd {
                    Text(timerInterval: Date.now...max(end, .now.addingTimeInterval(1)), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text("\(state.minutesUsed)m").monospacedDigit()
                }
            } minimal: {
                Text(state.focusStage ?? state.emoji)
            }
            .keylineTint(state.tintValue.color)
        }
    }
}

private struct LockScreenView: View {
    let state: VagoActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Text(state.focusStage ?? state.emoji).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                if let start = state.focusStart, let end = state.focusEnd {
                    Text("Focus").font(.headline)
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(.green)
                    Text(timerInterval: Date.now...max(end, .now.addingTimeInterval(1)), countsDown: true)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.readout).font(.headline.monospacedDigit())
                    ProgressView(value: min(Double(state.minutesUsed) / Double(max(state.limitMinutes, 1)), 1))
                        .tint(state.tintValue.color)
                    Text("procrastination today").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
