//
//  WatchApp.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

@main
struct WatchApp: App {
    @State private var store = ApplicationStore()
    
    var body: some Scene {
        WindowGroup {
            RootView(applicationStore: store)
        }
    }
}
