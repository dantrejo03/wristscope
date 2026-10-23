//
//  MotionReadingConversionTests.swift
//  Wristscope Watch AppTests
//
//  Created by Daniel Trejo on 10/23/26.
//

import CoreMotion
import Testing
@testable import Wristscope_Watch_App


/// How each sensor's reading becomes the samples the watch sends. Readings are plain structs,
/// so these build them directly instead of needing CoreMotion's data classes.
struct MotionReadingConversionTests {
    typealias Formatter = Motion.SampleFormatter

    let accelerometer = Motion.AccelerometerReading(
        timestamp: 10,
        acceleration: CMAcceleration(x: 0.1, y: 0.2, z: -0.98)
    )

    let gyro = Motion.GyroReading(
        timestamp: 11,
        rotationRate: CMRotationRate(x: -0.3, y: 0.4, z: 0.05)
    )

    let deviceMotion = Motion.DeviceMotionReading(
        timestamp: 12,
        attitude: CMQuaternion(x: -0.5, y: 0.25, z: -0.25, w: 0.5),
        rotationRate: CMRotationRate(x: 2, y: -2, z: 0.75),
        userAcceleration: CMAcceleration(x: 0.125, y: -0.125, z: 1.5),
        gravity: CMAcceleration(x: 0, y: -0.5, z: -1),
        magneticField: CMCalibratedMagneticField(field: CMMagneticField(x: 0, y: 0, z: 0), accuracy: .uncalibrated),
        heading: 0,
        sensorLocation: .default
    )

    @Test func accelerometerBecomesOneRawAccelerationSample() {
        let record = Formatter.record(from: .accelerometer(accelerometer))
        #expect(record.timestamp == 10)
        #expect(record.samples.map(\.tag) == [1])
        #expect(record.samples.map { $0.measurement.values } == [[0.1, 0.2, -0.98]])
    }

    @Test func gyroBecomesOneRawGyroSample() {
        let record = Formatter.record(from: .gyro(gyro))
        #expect(record.timestamp == 11)
        #expect(record.samples.map(\.tag) == [3])
        #expect(record.samples.map { $0.measurement.values } == [[-0.3, 0.4, 0.05]])
    }

    /// The attitude goes w first, as docs/wire-format.md lists it, though CoreMotion puts w last.
    @Test func deviceMotionBecomesAttitudeUserAccelerationRotationRateAndGravity() {
        let record = Formatter.record(from: .deviceMotion(deviceMotion))
        #expect(record.timestamp == 12)
        #expect(record.samples.map(\.tag) == [5, 2, 4, 6])
        #expect(record.samples.map { $0.measurement.values } == [
            [0.5, -0.5, 0.25, -0.25],
            [0.125, -0.125, 1.5],
            [2, -2, 0.75],
            [0, -0.5, -1],
        ])
    }

    /// `bytesPerRound` sizes the send buffer by hand, so it has to keep up with the conversions.
    @Test func bytesPerRoundIsOneRecordFromEachSensor() {
        let readings: [Motion.Reading] = [.accelerometer(accelerometer), .gyro(gyro), .deviceMotion(deviceMotion)]
        let total = readings.map { Formatter.byteSize(of: Formatter.record(from: $0)) }.reduce(0, +)
        #expect(Formatter.bytesPerRound == total)
    }
}
