//
//  Logging.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import os

nonisolated enum AppLog {
    private static let subsystem = "com.wristscope.watchapp"

    static let connectivity = Logger(subsystem: subsystem, category: "Connectivity")
    static let workout = Logger(subsystem: subsystem, category: "Workout")
}
