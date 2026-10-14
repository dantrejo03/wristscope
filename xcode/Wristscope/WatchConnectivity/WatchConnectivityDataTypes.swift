//
//  WatchConnectivityDataTypes.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import WatchConnectivity


nonisolated enum WatchSessionEvent: Sendable {
    case activated(WatchState)
    case activationFailed(WCError.Code?)
    /// The user is switching to another watch. The session reactivates once the switch is done.
    case switchingWatches
    case watchStateChanged(WatchState)
    case frameReceived
}

nonisolated struct WatchState: Sendable, Equatable {
    let isPaired: Bool
    let isWatchAppInstalled: Bool
    /// True while the watch app is running, so messages can go both ways.
    let isReachable: Bool

    /// Only meaningful once `session` is activated.
    init(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    init(isPaired: Bool, isWatchAppInstalled: Bool, isReachable: Bool) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.isReachable = isReachable
    }
}

nonisolated enum ConnectionState: Sendable, Equatable {
    case activating
    case failed(WCError.Code?)
    case activated(WatchState)
}
