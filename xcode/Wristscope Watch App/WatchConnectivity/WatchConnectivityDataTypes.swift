//
//  WatchConnectivityDataTypes.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import WatchConnectivity


nonisolated enum WatchSessionEvent: Sendable {
    case activated(isReachable: Bool, isCompanionAppInstalled: Bool)
    case activationFailed(WCError.Code?)
    case reachabilityChanged(Bool)
    case companionAppInstalledChanged(Bool)
    case fileTransferFinished(URL, error: (any Error)?)
}

nonisolated enum ConnectionState: Sendable, Equatable {
    case activating
    case failed(WCError.Code?)
    case activated(isReachable: Bool, isCompanionAppInstalled: Bool)
}
