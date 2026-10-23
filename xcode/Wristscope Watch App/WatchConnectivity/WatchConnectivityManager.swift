//
//  WatchConnectivityManager.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import Observation
import WatchConnectivity
import os


@Observable
final class WatchConnectivityManager {
    
    static let shared = WatchConnectivityManager()
    
    private(set) var connection: ConnectionState
    
    @ObservationIgnored private let session: WCSession?
    
    @ObservationIgnored private let delegate = WatchConnectivityObserver()
    
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    
    private init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        connection = session == nil ? .failed(nil) : .activating
        session?.delegate = delegate
        setUpObservationTask()
        session?.activate()
    }
    
    /// Reactivates after a failed activation. A no-op in any other state, or where
    /// `WCSession` is unsupported, since that failure is permanent.
    func retryActivation() {
        guard case .failed = connection, let session else { return }
        connection = .activating
        session.activate()
    }
    
    /// Throws a `WatchSessionError` without sending when the phone can't be reached right now.
    /// Once sent, failures go to `onError` instead, on WatchConnectivity's queue.
    nonisolated func sendMessage(
        _ data: Data,
        onReply: (@Sendable (Data) -> Void)? = nil,
        onError: (@Sendable (any Error) -> Void)? = nil
    ) throws {
        guard WCSession.isSupported() else {
            AppLog.connectivity.info("WCSession is not supported on this device; live data not sent")
            throw WatchSessionError.connectionNotSupported
        }

        // self.session has main actor isolation
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            throw WatchSessionError.phoneNotReachable
        }

        session.sendMessageData(data, replyHandler: onReply, errorHandler: onError)
    }

    /// Queues `url` for the phone. WatchConnectivity keeps trying in the background after this
    /// returns, and the file is deleted once it arrives.
    nonisolated func transferFile(_ url: URL, metadata: [String: Any]? = nil) throws {
        guard WCSession.isSupported() else {
            throw WatchSessionError.connectionNotSupported
        }
        // Transferring on a session that isn't activated is a programmer error.
        let session = WCSession.default
        guard session.activationState == .activated else {
            throw WatchSessionError.notActivated
        }
        session.transferFile(url, metadata: metadata)
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
        case let .activated(isReachable, isCompanionAppInstalled):
            connection = .activated(
                isReachable: isReachable,
                isCompanionAppInstalled: isCompanionAppInstalled
            )
        case let .activationFailed(code):
            AppLog.connectivity.error("WCSession activation failed: \(String(describing: code))")
            connection = .failed(code)
        case let .reachabilityChanged(isReachable):
            guard case let .activated(_, isCompanionAppInstalled) = connection else { return }
            connection = .activated(
                isReachable: isReachable,
                isCompanionAppInstalled: isCompanionAppInstalled
            )
        case let .companionAppInstalledChanged(isCompanionAppInstalled):
            guard case let .activated(isReachable, _) = connection else { return }
            connection = .activated(
                isReachable: isReachable,
                isCompanionAppInstalled: isCompanionAppInstalled
            )
        case let .fileTransferFinished(url, error):
            if let error {
                AppLog.connectivity.error("Transferring \(url.lastPathComponent) failed: \(error.localizedDescription)")
                return
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                AppLog.connectivity.error("Deleting \(url.lastPathComponent) after its transfer failed: \(error.localizedDescription)")
            }
        }
    }
}



// MARK: - Observer

nonisolated final class WatchConnectivityObserver: NSObject, WCSessionDelegate {
    let events: AsyncStream<WatchSessionEvent>
    private let continuation: AsyncStream<WatchSessionEvent>.Continuation

    override init() {
        let (events, continuation) = AsyncStream<WatchSessionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        self.events = events
        self.continuation = continuation
        super.init()
    }

    deinit { continuation.finish() }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        // watchOS has no `.inactive`: anything but `.activated` is a failure.
        guard error == nil, activationState == .activated else {
            continuation.yield(.activationFailed((error as? WCError)?.code))
            return
        }
        continuation.yield(.activated(
            isReachable: session.isReachable,
            isCompanionAppInstalled: session.isCompanionAppInstalled
        ))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        continuation.yield(.reachabilityChanged(session.isReachable))
    }

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        continuation.yield(.companionAppInstalledChanged(session.isCompanionAppInstalled))
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        continuation.yield(.fileTransferFinished(fileTransfer.file.fileURL, error: error))
    }
}
