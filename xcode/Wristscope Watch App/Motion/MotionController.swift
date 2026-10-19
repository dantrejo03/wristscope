//
//  MotionController.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import CoreMotion
import Foundation

extension Motion {
    final class Controller {
        
        private let sensor: Sensor
        private var sink: any SampleSink
        
        init(sensor: Sensor, sink: any SampleSink) {
            self.sensor = sensor
            self.sink = sink
        }

        /// Reports which sensors are running afterwards. One is false when this device doesn't
        /// have it.
        func startSensors() -> Sensor.Availability {
            let interval = SampleRate.current.updateInterval
            let frame = ReferenceFrame.currentAvailable.cmFrame
            let sink = self.sink

            // The sink is on `Motion.Actor`, so this hops there instead of waiting on it.
            Task { @Motion.Actor in sink.start() }

            let a = sensor.startAccelerometer(updateInterval: interval) {
                sink.receive($0)
            }
            
            let g = sensor.startGyroscope(updateInterval: interval) {
                sink.receive($0)
            }
            
            let dm = sensor.startDeviceMotion(
                updateInterval: interval, referenceFrame: frame
            ) {
                sink.receive($0)
            }
            
            return Sensor.Availability(accelerometer: a, gyro: g, deviceMotion: dm)
        }

        func stopSensors() {
            sensor.stopAccelerometer()
            sensor.stopGyroscope()
            sensor.stopDeviceMotion()
            let sink = self.sink
            Task { @Motion.Actor in sink.stop() }
        }
    }
}

extension Motion.Sensor {
    struct Availability {
        let accelerometer: Bool
        let gyro: Bool
        let deviceMotion: Bool
    }
}
