//
//  ReferenceFrame.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import CoreMotion


enum ReferenceFrame: String, AppStorageField {
    case arbitrary
    case arbitraryCorrected
    case magneticNorth
    case trueNorth
    
    static let key: String = "referenceFrame"
    static let defaultValue = ReferenceFrame.arbitrary
    static let explanation: String? = "The fixed direction that orientation is measured against."
    static let fieldTitle: String = "Reference Frame"
}

extension ReferenceFrame {
    var title: String {
        switch self {
        case .arbitrary: return "Arbitrary"
        case .arbitraryCorrected: return "Arbitrary (Corrected)"
        case .magneticNorth: return "Magnetic North"
        case .trueNorth: return "True North"
        }
    }
    
    var description: String {
        switch self {
        case .arbitrary: return "Up is gravity. Heading starts at zero when the session begins and may drift."
        case .arbitraryCorrected: return "Same start heading, but the compass corrects drift."
        case .magneticNorth: return "Heading is tied to magnetic north."
        case .trueNorth: return "Heading is tied to true (geographic) north. Needs location."
        }
    }

    /// The Core Motion equivalent, which is what `startDeviceMotionUpdates(using:)` takes.
    var cmFrame: CMAttitudeReferenceFrame {
        switch self {
        case .arbitrary: return .xArbitraryZVertical
        case .arbitraryCorrected: return .xArbitraryCorrectedZVertical
        case .magneticNorth: return .xMagneticNorthZVertical
        case .trueNorth: return .xTrueNorthZVertical
        }
    }

    /// The frames this device can use and that the settings view offers. True north is left out
    /// until the app asks for location permission.
    static var available: [ReferenceFrame] {
        let supported = CMMotionManager.availableAttitudeReferenceFrames()
        return allCases.filter { $0 != .trueNorth && supported.contains($0.cmFrame) }
    }

    /// The saved frame, or the default if the saved one isn't available on this device.
    static var currentAvailable: ReferenceFrame {
        let saved = current
        if available.contains(saved) { return saved }
        return available.contains(defaultValue) ? defaultValue : (available.first ?? defaultValue)
    }
}
