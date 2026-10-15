//
//  WatchApp.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

@main
struct WatchApp: App {
    @State private var viewModel = ViewModel()

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: viewModel)
        }
    }
}
