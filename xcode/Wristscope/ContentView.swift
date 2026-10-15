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

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Watch") {
                    ConnectionStatusRow(status: viewModel.watchStatus)
                    LabeledContent("Frames received", value: viewModel.framesReceived, format: .number)
                }

                Section {
                    Label(viewModel.computerStatus, systemImage: "cable.connector")
                } header: {
                    Text("Computer")
                } footer: {
                    Text("Plug this iPhone into the computer with a cable and run wristscope there. It connects on its own.")
                }
            }
            .navigationTitle("Wristscope")
        }
        .onAppear {
            // iOS suspends the app when the phone locks, which ends the stream.
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}

#Preview {
    ContentView(viewModel: ViewModel())
}
