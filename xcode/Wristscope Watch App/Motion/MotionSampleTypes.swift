//
//  MotionSampleTypes.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import CoreMotion


// MARK: - Accelerometer

nonisolated struct AccelerometerSample: MotionSampleType {
    static let source = Motion.Source.accelerometer
    static let fieldCount = 4
    
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMAccelerometerData) {
        timestamp = data.timestamp
        x = data.acceleration.x
        y = data.acceleration.y
        z = data.acceleration.z
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        x = reader.double()
        y = reader.double()
        z = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(x)
        bytes.append(y)
        bytes.append(z)
    }
}


// MARK: - Gyro

nonisolated struct GyroSample: MotionSampleType {
    static let source = Motion.Source.gyro
    static let fieldCount = 4
    
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMGyroData) {
        timestamp = data.timestamp
        x = data.rotationRate.x
        y = data.rotationRate.y
        z = data.rotationRate.z
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        x = reader.double()
        y = reader.double()
        z = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(x)
        bytes.append(y)
        bytes.append(z)
    }
}


// MARK: - Device motion

nonisolated struct DeviceMotionSample: MotionSampleType {
    static let source = Motion.Source.deviceMotion
    static let fieldCount = 18
    
    let timestamp: TimeInterval
    
    let attW: Double
    let attX: Double
    let attY: Double
    let attZ: Double

    let rotX: Double
    let rotY: Double
    let rotZ: Double

    let uAccX: Double
    let uAccY: Double
    let uAccZ: Double

    let gX: Double
    let gY: Double
    let gZ: Double
    
    let mX: Double
    let mY: Double
    let mZ: Double
    
    let heading: Double
    
    init(from motion: CMDeviceMotion) {
        timestamp = motion.timestamp
        
        attW = motion.attitude.quaternion.w
        attX = motion.attitude.quaternion.x
        attY = motion.attitude.quaternion.y
        attZ = motion.attitude.quaternion.z
        
        rotX = motion.rotationRate.x
        rotY = motion.rotationRate.y
        rotZ = motion.rotationRate.z
        
        uAccX = motion.userAcceleration.x
        uAccY = motion.userAcceleration.y
        uAccZ = motion.userAcceleration.z
        
        gX = motion.gravity.x
        gY = motion.gravity.y
        gZ = motion.gravity.z
        
        mX = motion.magneticField.field.x
        mY = motion.magneticField.field.y
        mZ = motion.magneticField.field.z
        
        heading = motion.heading
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        attW = reader.double()
        attX = reader.double()
        attY = reader.double()
        attZ = reader.double()
        rotX = reader.double()
        rotY = reader.double()
        rotZ = reader.double()
        uAccX = reader.double()
        uAccY = reader.double()
        uAccZ = reader.double()
        gX = reader.double()
        gY = reader.double()
        gZ = reader.double()
        mX = reader.double()
        mY = reader.double()
        mZ = reader.double()
        heading = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(attW)
        bytes.append(attX)
        bytes.append(attY)
        bytes.append(attZ)
        bytes.append(rotX)
        bytes.append(rotY)
        bytes.append(rotZ)
        bytes.append(uAccX)
        bytes.append(uAccY)
        bytes.append(uAccZ)
        bytes.append(gX)
        bytes.append(gY)
        bytes.append(gZ)
        bytes.append(mX)
        bytes.append(mY)
        bytes.append(mZ)
        bytes.append(heading)
    }
}

