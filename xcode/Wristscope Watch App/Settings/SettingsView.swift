//
//  SettingsView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI


struct SettingsView: View {
    @AppStorage(SessionType.key) private var sessionType = SessionType.defaultValue
    @AppStorage(SampleRate.key) private var sampleRate = SampleRate.defaultValue
    @AppStorage(ReferenceFrame.key) private var referenceFrame = ReferenceFrame.defaultValue
    #if DEBUG || BETA
    @AppStorage(BenchmarkSetting.key) private var isBenchmarking = false
    #endif

    var body: some View {
        List {
            Section {
                Picker("Session", selection: $sessionType) {
                    ForEach(SessionType.visibleCases, id: \.self) { type in
                        type.label.tag(type)
                    }
                }
                detail(sessionType.description)
            } footer: {
                explanation(SessionType.explanation)
            }

            Section {
                Picker("Sample Rate", selection: $sampleRate) {
                    ForEach(SampleRate.visibleCases, id: \.self) { rate in
                        Text(rate.title).tag(rate)
                    }
                }
                detail(sampleRate.description)
            } footer: {
                explanation(SampleRate.explanation)
            }

            Section {
                Picker("Reference Frame", selection: $referenceFrame) {
                    ForEach(ReferenceFrame.available, id: \.self) { frame in
                        Text(frame.title).tag(frame)
                    }
                }
                detail(referenceFrame.description)
            } footer: {
                explanation(ReferenceFrame.explanation)
            }

            #if DEBUG || BETA
            Section("Debug") {
                Toggle("Benchmark", isOn: $isBenchmarking)
                detail("Logs every live message and sends the log to the phone when the workout ends.")
            }
            #endif
        }
        .navigationTitle("Settings")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func explanation(_ text: String?) -> some View {
        if let text {
            Text(text)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

