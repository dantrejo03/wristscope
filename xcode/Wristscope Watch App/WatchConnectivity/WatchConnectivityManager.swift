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
    
    nonisolated func sendLive(
        _ data: Data, kind: MessageDataKind,
        onError: (@Sendable (any Error) -> Void)? = nil
    ) {
        guard WCSession.isSupported() else {
            AppLog.connectivity.info("WCSession is not supported on this device; live data not sent")
            return
        }
        
        // self.session has main actor isolation.
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return
        }
        
        var message = Data()
        message.reserveCapacity(1 + data.count)
        message.append(kind.rawValue)
        message.append(data)
        
        session.sendMessageData(message, replyHandler: nil, errorHandler: onError)
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








//@Observable
//final class WatchConnectivityManager {
//    
//    static let shared = WatchConnectivityManager()
//    
//    private(set) var connection: ConnectionState
//    
//    @ObservationIgnored private let session: WCSession?
//    
//    @ObservationIgnored private let delegate = WatchConnectivityObserver()
//    
//    @ObservationIgnored private var observationTask: Task<Void, Never>?
//    
//    private init() {
//        session = WCSession.isSupported() ? WCSession.default : nil
//        connection = session == nil ? .failed(nil) : .activating
//        session?.delegate = delegate
//        setUpObservationTask()
//        session?.activate()
//    }
//    
//    deinit {
//        observationTask?.cancel()
//    }
//    
//    /// Reactivates after a failed activation. A no-op in any other state, or where
//    /// `WCSession` is unsupported, since that failure is permanent.
//    func retryActivation() {
//        guard case .failed = connection, let session else { return }
//        connection = .activating
//        session.activate()
//    }
//    
//    /// Returns false if the frame was dropped because the session isn't
//    /// activated or the phone isn't reachable right now.
//    @discardableResult
//    nonisolated func sendFrame(
//        _ frame: Data,
//        onError: (@Sendable (any Error) -> Void)? = nil
//    ) -> Bool {
//        guard WCSession.isSupported() else { return false }
//        let session = WCSession.default
//        guard session.activationState == .activated, session.isReachable else {
//            return false
//        }
//        session.sendMessageData(frame, replyHandler: nil, errorHandler: onError)
//        return true
//    }
//}
//
//

