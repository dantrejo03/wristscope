//
//  MotionSample.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation


extension Motion {
    nonisolated protocol Sample: Sendable {
        static var tag: SampleTag { get }
        var tag: SampleTag { get }
        
        var timestamp: Double { get }
    }
    
    nonisolated enum SampleTag: UInt8, CaseIterable {
        case accelerometer = 1
        case gyro = 2
        case deviceMotion = 3
        
        var name: String {
            switch self {
            case .accelerometer: "accelerometer"
            case .gyro: "gyro"
            case .deviceMotion: "device motion"
            }
        }
    }
}


nonisolated struct AccelerometerSample: Motion.Sample {
    static let tag: Motion.SampleTag = .accelerometer
    var tag: Motion.SampleTag { AccelerometerSample.tag }
    
    let timestamp: Double
    
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct GyroSample: Motion.Sample {
    static let tag: Motion.SampleTag = .gyro
    var tag: Motion.SampleTag { GyroSample.tag }
    
    let timestamp: Double
    
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct DeviceMotionSample: Motion.Sample {
    static let tag: Motion.SampleTag = .deviceMotion
    var tag: Motion.SampleTag { DeviceMotionSample.tag }
    
    let timestamp: Double
    
    let attW: Double
    let attX: Double
    let attY: Double
    let attZ: Double
    
    let accX: Double
    let accY: Double
    let accZ: Double
    
    let rotX: Double
    let rotY: Double
    let rotZ: Double
    
    let gX: Double
    let gY: Double
    let gZ: Double
}
