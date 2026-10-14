//
//  ContentView.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    let viewModel: ViewModel

    @State private var hostDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Watch") {
                    ConnectionStatusRow(status: viewModel.watchStatus)
                    LabeledContent("Frames received", value: viewModel.framesReceived, format: .number)
                }

                Section {
                    Label(viewModel.computerStatus, systemImage: "desktopcomputer")
                    TextField("IP address", text: $hostDraft, prompt: Text("Find automatically"))
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { viewModel.connectToComputer(host: hostDraft) }
                } header: {
                    Text("Computer")
                } footer: {
                    Text("Leave the address empty to find the computer on your network automatically. Otherwise enter its IP address; it should listen on port 9000.")
                }
            }
            .navigationTitle("Wristscope")
        }
        .onAppear {
            hostDraft = viewModel.computerHost
            // iOS suspends the app when the phone locks, which ends the stream.
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}

#Preview {
    ContentView(viewModel: ViewModel())
}
