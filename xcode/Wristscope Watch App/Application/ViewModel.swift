//
//  ViewModel.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Foundation
import Observation


@Observable
final class ViewModel {

    enum StreamingState: Equatable {
        case idle
        case starting
        case streaming
        case stopping
    }

    private(set) var streamingState: StreamingState = .idle

    /// The sensors that started, in display order. Empty while not streaming.
    private(set) var activeSources: [Motion.Source] = []

    /// Why the last start failed, until the alert is dismissed.
    private(set) var startFailure: SessionStartFailure?

    var isShowingStartFailure: Bool {
        get { startFailure != nil }
        set { if !newValue { startFailure = nil } }
    }

    /// False while a start or stop is in progress.
    var canToggleStreaming: Bool {
        streamingState == .idle || streamingState == .streaming
    }

    /// Reads through to the connectivity manager, so views redraw when the connection changes.
    var connectionStatus: ConnectionStatus {
        ConnectionStatus(connectivity.connection)
    }

    @ObservationIgnored private let connectivity = WatchConnectivityManager.shared

    @ObservationIgnored private let motion = Motion.Controller()

    @ObservationIgnored private let workout = Workout.Manager.shared

    @ObservationIgnored private var session: Session?

    /// Starting waits for this, so it can't mistake the new workout for a leftover one.
    @ObservationIgnored private var leftoverCleanup: Task<Void, Never>?

    init() {
        // Policy for now: a workout still running from an earlier launch wasn't ended
        // properly, so it's discarded rather than saved.
        leftoverCleanup = Task { [workout] in
            await workout.discardLeftoverSession()
        }
    }

    func toggleStreaming() {
        switch streamingState {
        case .idle:
            startStreaming()
        case .streaming:
            streamingState = .stopping
            session?.end()
        case .starting, .stopping:
            break
        }
    }

    private func startStreaming() {
        streamingState = .starting
        Task {
            await leftoverCleanup?.value

            let session: Session
            do throws(SessionStartFailure) {
                session = try await Session.start(motion: motion, workout: workout)
            } catch {
                startFailure = error
                streamingState = .idle
                return
            }

            self.session = session
            activeSources = Motion.Source.allCases.filter(session.activeSources.contains)
            streamingState = .streaming

            await finish(session)
        }
    }

    /// Waits for the session to end, whether the user stopped it or the system did.
    private func finish(_ session: Session) async {
        let ending = await session.ended()
        self.session = nil
        activeSources = []

        // Policy for now: only a workout the user stopped is saved.
        if ending.wasRequested {
            await session.saveWorkout(endingAt: ending.date)
        } else {
            session.discardWorkout()
        }
        streamingState = .idle
    }
}

extension SessionStartFailure {
    var message: String {
        switch self {
        case .healthDenied:
            "Wristscope needs permission to save workouts. Turn it on in Health settings."
        case .couldNotStart:
            "The workout couldn't start. Try again."
        }
    }
}


// MARK: - Connection status

/// What the status card shows for a `ConnectionState`.
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
                systemImage: "iphone",
                tone: .pending
            )
        case .failed:
            self.init(
                title: "Connection Failed",
                detail: "Session couldn't activate",
                systemImage: "exclamationmark.triangle.fill",
                tone: .error
            )
        case .activated(_, isCompanionAppInstalled: false):
            self.init(
                title: "No iPhone App",
                detail: "Install Wristscope on iPhone",
                systemImage: "iphone.slash",
                tone: .error
            )
        case .activated(isReachable: false, _):
            self.init(
                title: "Not Reachable",
                detail: "iPhone is out of range",
                systemImage: "iphone.slash",
                tone: .warning
            )
        case .activated(isReachable: true, _):
            self.init(
                title: "Connected",
                detail: "iPhone is reachable",
                systemImage: "iphone.radiowaves.left.and.right",
                tone: .ok
            )
        }
    }
}


// MARK: - Sensor display

extension Motion.Source {
    var displayName: String {
        switch self {
        case .accelerometer: "Accelerometer"
        case .gyro: "Gyroscope"
        case .deviceMotion: "Device Motion"
        }
    }

    var systemImage: String {
        switch self {
        case .accelerometer: "move.3d"
        case .gyro: "gyroscope"
        case .deviceMotion: "rotate.3d"
        }
    }
}
