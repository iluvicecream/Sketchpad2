//
//  MonitorPortSetting.swift
//  Sketchpad2
//

import Foundation

/// One setting the daemon's monitor accepts for a port, the baud rate being the one that matters
/// to the serial monitor.
nonisolated struct MonitorPortSetting: Sendable {
    /// The identifier the daemon knows the setting by, e.g. `baudrate`.
    let id: String
    /// The values the setting accepts, when the daemon enumerates them.
    let values: [String]
    /// The value the daemon uses when the app doesn't pick one.
    let value: String

    init(_ descriptor: Cc_Arduino_Cli_Commands_V1_MonitorPortSettingDescriptor) {
        self.id = descriptor.settingID
        self.values = descriptor.enumValues
        self.value = descriptor.value
    }

    /// The identifier of the setting that carries a serial port's speed.
    static let baudRateID = "baudrate"

    /// The speed the monitor opens a port at until the daemon says otherwise.
    static let defaultBaudRate = "9600"

    /// The speeds the monitor offers when the selected port's monitor doesn't enumerate its own.
    static let defaultBaudRates = [
        "300", "600", "1200", "2400", "4800", "9600", "19200", "38400", "57600", "74880",
        "115200", "230400", "250000", "500000", "1000000", "2000000",
    ]
}

nonisolated extension Cc_Arduino_Cli_Commands_V1_MonitorPortConfiguration {
    /// The speed the daemon says it configured the port at, when the configuration carries one.
    var baudRate: String? {
        settings.first { $0.settingID == MonitorPortSetting.baudRateID }?.value
    }

    /// The configuration as the daemon wants to receive it, keyed by setting the way the app keeps
    /// them.
    init(settings: [String: String]) {
        self.init()
        self.settings = settings
            .sorted { $0.key < $1.key }
            .map { Cc_Arduino_Cli_Commands_V1_MonitorPortSetting(id: $0.key, value: $0.value) }
    }
}

nonisolated extension Cc_Arduino_Cli_Commands_V1_MonitorPortSetting {
    /// One setting, named the way the daemon names it.
    init(id: String, value: String) {
        var setting = Self()
        setting.settingID = id
        setting.value = value
        self = setting
    }
}
