//
//  HomeView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI


struct HomeView: View {
    @Bindable var applicationStore: ApplicationStore
    
    var body: some View {

        NavigationStack {
            VStack(spacing: 12) {
                AppHeaderView()
                
                Spacer()
                
                Button {
                    applicationStore.startWorkout()
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

#Preview {
    HomeView(applicationStore: ApplicationStore())
}
