//
//  BenchmarkSetting.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation


#if DEBUG || BETA
/// Debug builds only. When on, a session logs what happened to every live message and sends the
/// log to the phone when the workout ends. Release builds don't compile this, so a value left
/// over from a debug build does nothing there.
enum BenchmarkSetting: UserDefaultsBacked {
    static let key = "benchmarkConnectivity"

    /// The value currently saved in `UserDefaults`, which is where `@AppStorage` keeps it.
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}
#endif
