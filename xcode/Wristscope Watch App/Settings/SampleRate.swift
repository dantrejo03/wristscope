//
//  SampleRate.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import CoreMotion


enum SampleRate: String, AppStorageField {
    case hz100
    case hz50
    case hz25
    case hz20
    case hz10
    
    static let key: String = "sampleRate"
    static let defaultValue = SampleRate.hz100
    static let explanation: String? = nil
    static let fieldTitle: String = "Sample Rate"
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
