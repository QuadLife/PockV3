//
// BatteryState.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//

import Foundation

/// Define the precision, with wich the icon can display the current charging level
public let drawingPrecision = 5.4

///  Defines the state the battery is currently in.
///
///  - chargedAndPlugged: The battery is plugged into a power supply and charged.
///  - charging:          The battery is plugged into a power supply and 
///                       charging. Takes the current percentage as argument.
///  - discharging:       The battery is currently discharging. Accepts the 
///                       current percentage as argument.
enum BatteryState: Equatable {
    case chargedAndPlugged
    case charging(percentage: Int)
    case discharging(percentage: Int)

    /// The current percentage.
    var percentage: Int {
        switch self {
        case .chargedAndPlugged:
            return 100
        case .charging(let percentage):
            return percentage
        case .discharging(let percentage):
            return percentage
        }
    }
}
