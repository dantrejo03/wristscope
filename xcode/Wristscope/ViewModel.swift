//
//  ViewModel.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import Observation


/// Relays every frame from the watch to the computer, and reports how both ends are doing.
@Observable
final class ViewModel {

    /// Reads through to the connectivity manager, so views redraw when the connection changes.
    var watchStatus: ConnectionStatus {
        ConnectionStatus(connectivity.connection)
    }

    var framesReceived: Int {
        connectivity.framesReceived
    }

    /// The streamer's latest report, such as "Streaming to the computer".
    private(set) var computerStatus = "Starting…"

    @ObservationIgnored private let streamer: MotionStreamer

    @ObservationIgnored private let connectivity: WatchConnectivityManager

    init() {
        let streamer = MotionStreamer()
        self.streamer = streamer
        connectivity = WatchConnectivityManager(onFrame: { streamer.send($0) })
        streamer.onStatus = { [weak self] in self?.computerStatus = $0 }
        streamer.listen()
    }
}


// MARK: - Connection status

/// What the status row shows for a `ConnectionState`.
struct ConnectionStatus: Equatable {
    enum Tone: Equatable {
        case pending
        case ok
        case warning
        case error
    }

    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone
}

extension ConnectionStatus {
    init(_ state: ConnectionState) {
        switch state {
        case .activating:
            self.init(
                title: "Connecting…",
                detail: "Activating session",
                systemImage: "applewatch",
                tone: .pending
            )
        case .failed:
            self.init(
                title: "Connection Failed",
                detail: "Session couldn't activate",
                systemImage: "exclamationmark.triangle.fill",
                tone: .error
            )
        case let .activated(watch) where !watch.isPaired:
            self.init(
                title: "No Apple Watch",
                detail: "Pair a watch in the Watch app",
                systemImage: "applewatch.slash",
                tone: .error
            )
        case let .activated(watch) where !watch.isWatchAppInstalled:
            self.init(
                title: "No Watch App",
                detail: "Install Wristscope on your Apple Watch",
                systemImage: "applewatch.slash",
                tone: .error
            )
        case let .activated(watch) where !watch.isReachable:
            self.init(
                title: "Not Reachable",
                detail: "Open Wristscope on your watch",
                systemImage: "applewatch.slash",
                tone: .warning
            )
        case .activated:
            self.init(
                title: "Connected",
                detail: "Watch app is running",
                systemImage: "applewatch.radiowaves.left.and.right",
                tone: .ok
            )
        }
    }
}
