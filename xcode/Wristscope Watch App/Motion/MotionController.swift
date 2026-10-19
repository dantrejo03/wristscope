//
//  MotionController.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import CoreMotion
import os

extension Motion {
    final class Controller {
        
        private let sensor: Sensor
        private let sink: any SampleSink
        private let updateInterval: Double
        private let referenceFrame: CMAttitudeReferenceFrame
        
        init(
            sensor: Sensor,
            sink: any SampleSink,
            updateInterval: Double,
            referenceFrame: CMAttitudeReferenceFrame
        ) {
            self.sensor = sensor
            self.sink = sink
            self.updateInterval = updateInterval
            self.referenceFrame = referenceFrame
        }

        /// Reports which sensors are running afterwards. One is false when this device doesn't
        /// have it.
        func startSensors() -> Sensor.Availability {
            let sink = self.sink

            // The sink is on `Motion.Actor`, so this hops there instead of waiting on it.
            Task { @Motion.Actor in sink.openTap() }
            
            // The handlers run on `Motion.queue`, so they can enter `Motion.Actor` directly.
            // Each builds its sample first, since CoreMotion's data classes aren't Sendable.

            let a = sensor.startAccelerometer(updateInterval: updateInterval) { data, error in
                guard let data else {
                    AppLog.motion.error("Accelerometer update failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                Motion.Actor.assumeIsolated { sink.receive(data) }
            }
            
            let g = sensor.startGyroscope(updateInterval: updateInterval) { data, error in
                guard let data else {
                    AppLog.motion.error("Gyroscope update failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                Motion.Actor.assumeIsolated { sink.receive(data) }
            }
            
            let dm = sensor.startDeviceMotion(
                updateInterval: updateInterval, referenceFrame: referenceFrame
            ) { data, error in
                guard let data else {
                    AppLog.motion.error("DeviceMotion updated failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                Motion.Actor.assumeIsolated { sink.receive(data) }
            }
            
            return Sensor.Availability(accelerometer: a, gyro: g, deviceMotion: dm)
        }

        // Samples CoreMotion already queued can still arrive after this.
        func stopSensors() {
            sensor.stopAccelerometer()
            sensor.stopGyroscope()
            sensor.stopDeviceMotion()
            let sink = self.sink
            Task { @Motion.Actor in sink.closeTap() }
        }
    }
}

