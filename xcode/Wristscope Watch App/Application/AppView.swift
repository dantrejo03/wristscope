//
//  AppView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

struct AppView: View {
    @Bindable var viewModel: ViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ConnectionStatusCard(status: viewModel.connectionStatus)

                Button(action: viewModel.toggleStreaming) {
                    Label(buttonTitle, systemImage: showsStop ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(showsStop ? .red : .green)
                .disabled(!viewModel.canToggleStreaming)

                // Below the button, so the button doesn't move when this appears.
                if viewModel.streamingState == .streaming {
                    ActiveSensorsCard(sources: viewModel.activeSources)
                }
            }
            .animation(.default, value: viewModel.streamingState)
        }
        .alert(
            "Couldn't Start",
            isPresented: $viewModel.isShowingStartFailure,
            presenting: viewModel.startFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private var buttonTitle: String {
        switch viewModel.streamingState {
        case .idle: "Start Streaming"
        case .starting: "Starting…"
        case .streaming: "Stop Streaming"
        case .stopping: "Stopping…"
        }
    }

    private var showsStop: Bool {
        viewModel.streamingState == .streaming || viewModel.streamingState == .stopping
    }
}

#Preview {
    AppView(viewModel: ViewModel())
}
