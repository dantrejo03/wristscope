//
//  RepRecordingView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI

/// Replaces the workout tabs while a rep records, so stopping it is the only thing to do.
struct RepRecordingView: View {
    typealias Formatter = Workout.Metrics.Formatter

    /// When the rep started.
    let since: Date
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label("Recording", systemImage: "record.circle")
                .font(.headline)
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Formatter.elapsedTime(from: context.date.timeIntervalSince(since)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Button("Stop", systemImage: "stop.fill", action: onStop)
                .tint(.red)
        }
    }
}

#Preview {
    RepRecordingView(since: .now.addingTimeInterval(-7), onStop: {})
}
