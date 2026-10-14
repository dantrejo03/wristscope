//
//  Logging.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import os

nonisolated enum AppLog {
    private static let subsystem = "com.wristscope.app"

    static let connectivity = Logger(subsystem: subsystem, category: "Connectivity")
}
