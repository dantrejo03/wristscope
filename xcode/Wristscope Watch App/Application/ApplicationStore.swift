//
//  ApplicationStore.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import Foundation
import SwiftUI


@Observable
final class ApplicationStore {
    enum State {
        case home, countdown, active, summary
    }
    
    private(set) var state: State = .home
    
    func startWorkout() {
        state = .countdown
    }
    
    func beginActive() {
        state = .active
    }
}
