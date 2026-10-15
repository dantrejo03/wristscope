//
//  Settings.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI
import CoreMotion


protocol AppStorageField {
    static var appStorageKey: String { get }
    static var appStorageExplanation: String? { get }
}

extension AppStorageField {
    static var appStorageExplanation: String? { nil }
}

enum SessionType: AppStorageField {
    case live
    case rep
    case workout
    
    static let appStorageKey: String = "sessionType"
    static let appStorageExplanation: String? = nil
}

enum SampleRate: AppStorageField {
    case hz100
    case hz50
    case hz25
    case hz20
    case hz10
    
    static let appStorageKey: String = "sampleRate"
    static let appStorageExplanation: String? = nil
}

enum ReferenceFrame: AppStorageField {
    case arbitrary
    case arbitraryCorrected
    case magneticNorth
    case trueNorth
    
    static let appStorageKey: String = "referenceFrame"
    static let appStorageExplanation: String? = "The fixed direction that orientation is measured against."
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
    
    static func isEqual(lhs: Self, rhs: CMAttitudeReferenceFrame) -> Bool {
        switch lhs {
        case .arbitrary:
            if rhs == .xArbitraryZVertical { return true }
            else { return false }
        case .arbitraryCorrected:
            if rhs == .xArbitraryCorrectedZVertical { return true }
            else { return false }
        case .magneticNorth:
            if rhs == .xMagneticNorthZVertical { return true }
            else { return false }
        case .trueNorth:
            if rhs == .xTrueNorthZVertical { return true }
            else { return false }
        }
    }
}


