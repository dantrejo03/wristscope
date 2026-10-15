//
//  Settings.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI
import CoreMotion


protocol AppStorageField: CaseIterable, RawRepresentable where RawValue == String {
    static var appStorageKey: String { get }
    static var defaultValue: Self { get }
    static var explanation: String? { get }
    static var fieldTitle: String { get }
}

extension AppStorageField {
    static var appStorageExplanation: String? { nil }

    /// The value currently saved in `UserDefaults`, which is where `@AppStorage` keeps it.
    static var current: Self {
        UserDefaults.standard.string(forKey: appStorageKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}

enum SessionType: String, AppStorageField {
    case live
    case rep
    case workout
    
    static let appStorageKey: String = "sessionType"
    static let defaultValue = SessionType.live
    static let explanation: String? = nil
    static let fieldTitle: String = "Session"
}

enum SampleRate: String, AppStorageField {
    case hz100
    case hz50
    case hz25
    case hz20
    case hz10
    
    static let appStorageKey: String = "sampleRate"
    static let defaultValue = SampleRate.hz100
    static let explanation: String? = nil
    static let fieldTitle: String = "Sample Rate"
}

enum ReferenceFrame: String, AppStorageField {
    case arbitrary
    case arbitraryCorrected
    case magneticNorth
    case trueNorth
    
    static let appStorageKey: String = "referenceFrame"
    static let defaultValue = ReferenceFrame.arbitrary
    static let explanation: String? = "The fixed direction that orientation is measured against."
    static let fieldTitle: String = "Reference Frame"
}


// MARK: - Extensions

extension SessionType {
    var title: String {
        switch self {
        case .live: return "Live"
        case .rep: return "Rep"
        case .workout: return "Workout"
        }
    }
    
    var description: String {
        switch self {
        case .live: return "Streams motion data in real time. Nothing is saved."
        case .rep: return "Short recording. Upload it for review."
        case .workout: return "Long recording saved on the watch. Upload later."
        }
    }
        
    var systemImage: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .rep: return "repeat"
        case .workout: return "figure.run"
        }
    }
    
    var label: some View {
        Label(title, systemImage: systemImage)
    }
}


extension SampleRate {
    var hertz: Int {
        switch self {
        case .hz100: return 100
        case .hz50: return 50
        case .hz25: return 25
        case .hz20: return 20
        case .hz10: return 10
        }
    }
    
    /// Seconds between samples, which is what `CMMotionManager` takes.
    var updateInterval: TimeInterval {
        1.0 / Double(hertz)
    }

    var title: String {
        "\(hertz) Hz"
    }
    
    var description: String {
        switch self {
        case .hz100: return "High precision: vibration, sports swing analysis"
        case .hz50: return "Standard: walking, running, activity recognition"
        case .hz25: return "Balanced: general gestures, battery-friendly"
        case .hz20: return "Low frequency: context tracking, driving, sleeping"
        case .hz10: return "Ultra-low: basic orientation, static states"
        }
    }
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


