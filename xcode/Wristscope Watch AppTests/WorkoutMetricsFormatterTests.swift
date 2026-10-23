//
//  WorkoutMetricsFormatterTests.swift
//  Wristscope Watch AppTests
//
//  Created by Daniel Trejo on 10/23/26.
//

import Foundation
import Testing
@testable import Wristscope_Watch_App


/// The text and gauge values on the workout metrics screen.
struct WorkoutMetricsFormatterTests {
    typealias Formatter = Workout.Metrics.Formatter

    @Test func heartRateRoundsToAWholeBeat() {
        #expect(Formatter.string(from: 72.4) == "72")
        #expect(Formatter.string(from: 72.5) == "73")
    }

    @Test func missingHeartRateShowsDashes() {
        #expect(Formatter.string(from: nil) == "--")
    }

    @Test func intensityIsTheShareOfMaxHeartRate() {
        #expect(Formatter.intensity(for: 100, max: 200) == 0.5)
    }

    @Test func intensityStopsAtFull() {
        #expect(Formatter.intensity(for: 250, max: 200) == 1)
    }

    @Test func intensityIsZeroWithoutAReadingOrAMax() {
        #expect(Formatter.intensity(for: nil, max: 200) == 0)
        #expect(Formatter.intensity(for: 100, max: 0) == 0)
    }

    /// Hours show only once there is one, and a part-second never rounds up early.
    @Test(arguments: [
        (0, "00:00"),
        (59.9, "00:59"),
        (61, "01:01"),
        (3599, "59:59"),
        (3600, "1:00:00"),
        (36_061, "10:01:01"),
    ] as [(TimeInterval, String)])
    func elapsedTime(interval: TimeInterval, shown: String) {
        #expect(Formatter.elapsedTime(from: interval) == shown)
    }

    @Test func energyRoundsToAWholeCalorie() {
        #expect(Formatter.energy(from: 349.6) == "350")
    }

    /// Compared with the same number style, so the locale's decimal separator doesn't matter.
    @Test func distanceIsKilometersOrMiles() {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        #expect(Formatter.distance(from: 2_500, true) == 2.5.formatted(style))
        #expect(Formatter.distance(from: 1_609.344, false) == 1.0.formatted(style))
    }
}
