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
        case .countdown(_, let showLoading):
            CountdownView(showLoading: showLoading, onFinish: applicationStore.countdownEnded)
        case .active(let store): ActiveWorkoutView(store: store)
        case .summary: EmptyView()
        }
    }
}

#Preview {
    RootView(applicationStore: ApplicationStore())
}
