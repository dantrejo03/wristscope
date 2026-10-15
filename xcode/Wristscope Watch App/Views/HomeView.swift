//
//  HomeView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI


struct HomeView: View {
    @Bindable var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ConnectionStatusCard(status: viewModel.connectionStatus)

                    Button {
                        // Intentionally empty: starting a workout isn't wired up yet.
                    } label: {
                        Label("Start Workout", systemImage: "figure.run")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView(viewModel: ViewModel())
}
