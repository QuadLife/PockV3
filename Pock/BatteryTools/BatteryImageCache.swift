//
// BatteryImageCache.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//

import Cocoa

struct BatteryImageCache {

    ///  The cached battery icon.
    let image: NSImage?
    ///  The BatteryState associated with the cached battery icon.
    let batteryStatus: BatteryState
    ///  Whether the icon was drawn for Low Power Mode.
    let lowPowerMode: Bool

    ///  Cache a battery icon alongside it's corresponding BatteryState.
    ///
    /// - parameter status: The BatteryState to cache the battery icon for.
    /// - parameter lowPowerMode: Whether Low Power Mode was active for this icon.
    /// - parameter img: The battery icon to cache.
    init(forStatus status: BatteryState, lowPowerMode: Bool = false, withImage img: NSImage?) {
        batteryStatus = status
        self.lowPowerMode = lowPowerMode
        image = img
    }

}
