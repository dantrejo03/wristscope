//
//  WristscopeApp.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI

@main
struct WristscopeApp: App {
    // Created at launch, even when WatchConnectivity launches the app in the background,
    // so the session is active before the watch's first frame arrives.
    @State private var viewModel = ViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
