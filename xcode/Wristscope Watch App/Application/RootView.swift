//
//  RootView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

struct RootView: View {
    var applicationStore: ApplicationStore
    
    var body: some View {
        switch applicationStore.state {
        case .home: HomeView(applicationStore: applicationStore)
        case .countdown: CountdownView(onFinish: applicationStore.beginActive)
        case .active: ActiveWorkoutView()
        case .summary: EmptyView()
        }
    }
}

#Preview {
    RootView(applicationStore: ApplicationStore())
}
