//
//  SessionType.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI


enum SessionType: String, AppStorageField {
    case live
    case rep
    case workout
    
    static let key: String = "sessionType"
    static let defaultValue = SessionType.live
    static let explanation: String? = nil
    static let fieldTitle: String = "Session"
}

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

    /// Label for this session type's wildcard button on the controls page.
    var wildcardTitle: String {
        switch self {
        case .live: return "Connection"
        case .rep: return "Record Rep"
        case .workout: return "Mark Event"
        }
    }

    var wildcardSymbol: String {
        switch self {
        case .live: return "iphone.radiowaves.left.and.right"
        case .rep: return "record.circle"
        case .workout: return "flag.fill"
        }
    }
    
    var shouldShowInView: Bool {
        switch self {
        case .live: return true
        case .rep, .workout: return false
        }
    }
}
