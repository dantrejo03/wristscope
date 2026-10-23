//
//  MotionTypes.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation


extension Motion {
    nonisolated struct Record {
        var timestamp: Double
        var samples: [Sample]
    }
}

extension Motion {
    nonisolated enum Sample {
        case rawAcceleration(Vector3)
        case userAcceleration(Vector3)
        case rawGyro(Vector3)
        case rotationRate(Vector3)
        case attitude(Vector4)
        case gravity(Vector3)
    }
}

extension Motion.Sample {
    /// Each case's payload. A case whose payload isn't a Measurement won't compile here.
    nonisolated var measurement: any Motion.Measurement {
        switch self {
        case .rawAcceleration(let m),
                .userAcceleration(let m),
                .rawGyro(let m),
                .rotationRate(let m),
                .gravity(let m):
            return m
        case .attitude(let m):
            return m
        }
    }

    /// The byte written before this sample's values.
    nonisolated var tag: UInt8 {
        switch self {
        case .rawAcceleration: 1
        case .userAcceleration: 2
        case .rawGyro: 3
        case .rotationRate: 4
        case .attitude: 5
        case .gravity: 6
        }
    }
}

extension Motion {
    nonisolated protocol Measurement: Sendable {
        static var valueCount: Int { get }
        var values: [Double] { get }
    }
}

extension Motion {
    nonisolated struct Vector3: Motion.Measurement {
        static let valueCount = 3
        let values: [Double]
        
        init(x: Double, y: Double, z: Double) {
            self.values = [x,y,z]
        }
    }
    
    nonisolated struct Vector4: Motion.Measurement {
        static let valueCount = 4
        let values: [Double]
        
        init(w: Double, x: Double, y: Double, z: Double) {
            self.values = [w,x,y,z]
        }
    }
}

