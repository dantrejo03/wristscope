//
//  WristscopeApp.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI

@main
struct Wristscope_Watch_AppApp: App {
    @State private var viewModel = ViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
