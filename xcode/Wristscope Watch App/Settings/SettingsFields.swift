//
//  SettingsFields.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation


protocol UserDefaultsBacked {
    static var key: String { get }
}

protocol AppStorageField: CaseIterable, UserDefaultsBacked, RawRepresentable where RawValue == String {
    static var defaultValue: Self { get }
    static var explanation: String? { get }
    static var fieldTitle: String { get }
}


extension AppStorageField {
    static var explanation: String? { nil }

    /// The value currently saved in `UserDefaults`, which is where `@AppStorage` keeps it.
    static var current: Self {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}
