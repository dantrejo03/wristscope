//
//  WatchConnectivityManager.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import Observation
import WatchConnectivity
import os


/// Receives the motion frames the watch sends. Make only one: `WCSession` has a single delegate.
@Observable
final class WatchConnectivityManager {

    private(set) var connection: ConnectionState

    /// Frames received from the watch since launch, whether or not they reached the computer.
    private(set) var framesReceived = 0

    @ObservationIgnored private let session: WCSession?

    @ObservationIgnored private let delegate: WatchConnectivityObserver

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    /// - Parameter onFrame: called with each frame as soon as it arrives, on WatchConnectivity's
    ///   background queue, so forwarding it never waits on the main thread.
    init(onFrame: @escaping @Sendable (Data) -> Void) {
        session = WCSession.isSupported() ? WCSession.default : nil
        connection = session == nil ? .failed(nil) : .activating
        delegate = WatchConnectivityObserver(onFrame: onFrame)
        session?.delegate = delegate
        setUpObservationTask()
        session?.activate()
    }

    deinit {
        observationTask?.cancel()
    }
}


// MARK: - Observation
extension WatchConnectivityManager {
    private func setUpObservationTask() {
        let events = delegate.events
        self.observationTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: WatchSessionEvent) {
        switch event {
        case let .activated(watch):
            connection = .activated(watch)
        case let .activationFailed(code):
            AppLog.connectivity.error("WCSession activation failed: \(String(describing: code))")
            connection = .failed(code)
        case .switchingWatches:
            connection = .activating
        case let .watchStateChanged(watch):
            guard case .activated = connection else { return }
            connection = .activated(watch)
        case .frameReceived:
            framesReceived += 1
        }
    }
}



// MARK: - Observer

nonisolated final class WatchConnectivityObserver: NSObject, WCSessionDelegate {
    let events: AsyncStream<WatchSessionEvent>
    private let continuation: AsyncStream<WatchSessionEvent>.Continuation
    private let onFrame: @Sendable (Data) -> Void

    init(onFrame: @escaping @Sendable (Data) -> Void) {
        // Frames arrive about 10 times a second. The room keeps a burst of them from pushing
        // out a state change if the main thread falls a few seconds behind.
        let (events, continuation) = AsyncStream<WatchSessionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.events = events
        self.continuation = continuation
        self.onFrame = onFrame
        super.init()
    }

    deinit { continuation.finish() }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard error == nil, activationState == .activated else {
            continuation.yield(.activationFailed((error as? WCError)?.code))
            return
        }
        continuation.yield(.activated(WatchState(session)))
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        continuation.yield(.switchingWatches)
    }

    /// The switch to another watch is done. Activating again connects to the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        continuation.yield(.watchStateChanged(WatchState(session)))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        continuation.yield(.watchStateChanged(WatchState(session)))
    }

    /// The watch sends frames with `sendMessageData(_:replyHandler: nil, …)`, which arrive here.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        onFrame(messageData)
        continuation.yield(.frameReceived)
    }

    /// With benchmarking on, the watch sends frames with a reply handler, which arrive here
    /// instead. The reply goes first, so the watch's round trip doesn't include the relay.
    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        replyHandler(Data())
        onFrame(messageData)
        continuation.yield(.frameReceived)
    }

    /// WatchConnectivity deletes the file once this returns, so it's moved now. Documents is the
    /// folder the Files app shows as On My iPhone › Wristscope.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let name = file.fileURL.lastPathComponent
        do {
            try FileManager.default.moveItem(
                at: file.fileURL,
                to: URL.documentsDirectory.appending(path: name)
            )
        } catch {
            AppLog.connectivity.error("Saving \(name) from the watch failed: \(error.localizedDescription)")
        }
    }
}
