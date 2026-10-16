//
//  ApplicationStore.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import Foundation
import HealthKit
import SwiftUI


@Observable
final class ApplicationStore {
    private(set) var state: State = .home

    // `HKWorkoutSession.delegate` is weak, so this is the only strong reference.
    @ObservationIgnored private let observer = Workout.Session.Observer()
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init() {
        setUpObservationTask()
    }

    deinit {
        observationTask?.cancel()
    }

    func start(_ workout: Workout.Kind) async {
        do {
            if try await Workout.Manager.shared.needsAuthorization() {
                try await Workout.Manager.shared.requestAuthorization()
            }

            let session = try Workout.Manager.shared.prepare(workout.activityType, delegate: observer)
            state = .countdown(Workout.Store(session: session, type: SessionType.current), showLoading: false)
        } catch {

        }

        UserDefaults.standard.set(workout.rawValue, forKey: Workout.Kind.key)
    }

    func countdownEnded() {
        guard case .countdown(let store, _) = state else { return }
        
        guard store.session.state == .prepared else {
            state = .countdown(store, showLoading: true)
            return
        }
        Task { await begin() }
    }

    private func begin() async {
        guard case .countdown(let store, _) = state else { return }
        
        do {
            try await Workout.Manager.shared.begin(store.session)
            state = .active(store)
        } catch {

        }
    }
}


extension ApplicationStore {
    enum State {
        case home
        case countdown(Workout.Store, showLoading: Bool)
        case active(Workout.Store)
        case summary
    }
}


// MARK: - Observation

extension ApplicationStore {
    private func setUpObservationTask() {
        let events = observer.events
        observationTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: Workout.Event) {
        switch event {
        case .prepared:
            // The countdown already ended and is waiting on this
            if case .countdown(_, showLoading: true) = state {
                Task { await begin() }
            }
        case .running, .paused:
            // The session has only one delegate, so the workout store hears these through here
            if case .active(let store) = state {
                store.handle(event)
            }
        case .ended, .failed:
            break
        }
    }
}
