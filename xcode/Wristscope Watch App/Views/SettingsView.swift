//
//  SettingsView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI


struct SettingsView: View {
    @AppStorage(SessionType.appStorageKey) private var sessionType = SessionType.defaultValue
    @AppStorage(SampleRate.appStorageKey) private var sampleRate = SampleRate.defaultValue
    @AppStorage(ReferenceFrame.appStorageKey) private var referenceFrame = ReferenceFrame.defaultValue

    var body: some View {
        List {
            Section {
                Picker("Session", selection: $sessionType) {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        type.label.tag(type)
                    }
                }
                detail(sessionType.description)
            } footer: {
                explanation(SessionType.appStorageExplanation)
            }

            Section {
                Picker("Sample Rate", selection: $sampleRate) {
                    ForEach(SampleRate.allCases, id: \.self) { rate in
                        Text(rate.title).tag(rate)
                    }
                }
                detail(sampleRate.description)
            } footer: {
                explanation(SampleRate.appStorageExplanation)
            }

            Section {
                Picker("Reference Frame", selection: $referenceFrame) {
                    ForEach(ReferenceFrame.available, id: \.self) { frame in
                        Text(frame.title).tag(frame)
                    }
                }
                detail(referenceFrame.description)
            } footer: {
                explanation(ReferenceFrame.appStorageExplanation)
            }
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
