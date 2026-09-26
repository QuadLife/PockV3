//
// StatusBarIcon.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//

import Cocoa

///  Image names for the images used by the menu bar item icon.
private enum BatteryImage: NSImage.Name {
    case left = "BatteryFillCapLeft"
    case right = "BatteryFillCapRight"
    case middle = "BatteryFill"
    case outline = "BatteryOutline"
    case charging = "Charging"
    case chargingSymbol = "ChargingSymbol"
    case chargedAndPlugged = "ChargedAndPlugged"
    case deadCropped = "DeadCropped"
    case none = "None"
    case lowBattery = "LowBattery"
}

internal struct StatusBarIcon {

    ///  The little margins between the battery outline and the capcity bar.
    private let capacityOffsetX: CGFloat = 2.0
    private let capacityOffsetY: CGFloat = 2.0

    ///  Cache the last drawn battery icon.
    private var cache: BatteryImageCache?

    ///  Draws a battery icon for the given BatteryState.
    ///
    ///  - parameter status:      The BatteryState for the status the battery is currently in, e.g. charging
    ///  - parameter lowPowerMode: Whether Low Power Mode is currently active. Colors the icon yellow.
    ///  - returns: The battery image for the provided battery status.
    mutating internal func drawBatteryImage(forStatus status: BatteryState, lowPowerMode: Bool = false) -> NSImage? {
        if let cache = self.cache, cache.batteryStatus == status, cache.lowPowerMode == lowPowerMode {
            return cache.image
        }

        switch status {
        case let .charging(percentage):
            cache = BatteryImageCache(forStatus: status,
                                      lowPowerMode: lowPowerMode,
                                      withImage: chargingBatteryImage(forPercentage: Double(percentage),
                                                                      lowPowerMode: lowPowerMode))
        case .chargedAndPlugged:
            cache = BatteryImageCache(forStatus: status,
                                      lowPowerMode: lowPowerMode,
                                      withImage: batteryImage(named: .chargedAndPlugged, lowPowerMode: lowPowerMode))
        case let .discharging(percentage):
            cache = BatteryImageCache(forStatus: status,
                                      lowPowerMode: lowPowerMode,
                                      withImage: dischargingBatteryImage(forPercentage: Double(percentage),
                                                                         lowPowerMode: lowPowerMode))
        }

        return cache?.image
    }

    ///  Draws a battery icon for the given BatteryError.
    ///
    ///  - parameter err: The BatteryError object for the corresponding error that happened.
    ///  - returns: A battery icon for the given BatteryError.
    internal func drawBatteryImage(forError error: BatteryError?) -> NSImage? {
        guard let error = error else { return nil }

        switch error {
        case .connectionAlreadyOpen:
            return batteryImage(named: .deadCropped)
        case .serviceNotFound:
            return batteryImage(named: .none)
        }
    }

    ///  Draws a battery icon based on the battery's current percentage.
    ///
    ///  - parameter percentage:  The current percentage of the battery.
    ///  - parameter lowPowerMode: Whether Low Power Mode is active (colors the icon yellow).
    ///  - returns: A battery icon for the supplied percentage.
    private func dischargingBatteryImage(forPercentage percentage: Double, lowPowerMode: Bool) -> NSImage? {
        let fillColor: NSColor = lowPowerMode ? .systemYellow : .white

        guard let batteryOutline = batteryImage(named: .outline),
              let capacityCapLeft = batteryImage(named: .left),
              let capacityCapRight = batteryImage(named: .right),
              let capacityFill = batteryImage(named: .middle) else {
            return nil
        }

        // Delete the image name for the battery outline to keep it's representations out of the NSCachedImageRep
        batteryOutline.setName(nil)
        let drawingRect = NSRect(x: capacityOffsetX,
                                 y: capacityOffsetY,
                                 width: CGFloat(round(percentage / drawingPrecision)) * capacityFill.size.width,
                                 height: capacityFill.size.height)

        // NSImage#drawThreePartImage glitchets when the width of the capacity bar drops
        // below the combined width of startCap and endCap.
        if drawingRect.width < (2 * capacityFill.size.width) {
            return batteryImage(named: .lowBattery, lowPowerMode: lowPowerMode)
        }

        let outline: NSImage = lowPowerMode ? batteryOutline.tint(color: fillColor) : batteryOutline
        if lowPowerMode {
            outline.isTemplate = false
        }
        let startCap: NSImage = lowPowerMode ? capacityCapLeft.tint(color: fillColor) : capacityCapLeft
        let fill: NSImage     = lowPowerMode ? capacityFill.tint(color: fillColor) : capacityFill
        let endCap: NSImage   = lowPowerMode ? capacityCapRight.tint(color: fillColor) : capacityCapRight

        return outline.drawThreePartImage(withStartCap: startCap,
                                          fill: fill,
                                          endCap: endCap,
                                          inFrame: drawingRect)
    }
    
    ///  Draws a battery icon with the fill at the battery's current percentage
    ///  and the charging symbol overlaid, as shown while the power cable is
    ///  plugged in.
    ///
    ///  - parameter percentage:  The current percentage of the battery.
    ///  - parameter lowPowerMode: Whether Low Power Mode is active (colors the icon yellow).
    ///  - returns: A charging battery icon for the supplied percentage.
    private func chargingBatteryImage(forPercentage percentage: Double, lowPowerMode: Bool) -> NSImage? {
        let fillColor: NSColor = lowPowerMode ? .systemYellow : .white

        guard let batteryOutline = batteryImage(named: .outline),
              let capacityCapLeft = batteryImage(named: .left),
              let capacityCapRight = batteryImage(named: .right),
              let capacityFill = batteryImage(named: .middle) else {
            return nil
        }

        // Delete the image name for the battery outline to keep it's representations out of the NSCachedImageRep
        batteryOutline.setName(nil)
        let drawingRect = NSRect(x: capacityOffsetX,
                                 y: capacityOffsetY,
                                 width: CGFloat(round(percentage / drawingPrecision)) * capacityFill.size.width,
                                 height: capacityFill.size.height)

        // NSImage#drawThreePartImage glitchets when the width of the capacity bar drops
        // below the combined width of startCap and endCap.
        if drawingRect.width < (2 * capacityFill.size.width) {
            return batteryImage(named: .lowBattery, lowPowerMode: lowPowerMode)
        }

        // Flatten every part to an explicit color: a plain copy of a template image
        // rasterizes with the dark label color and becomes invisible on the Touch Bar.
        let outline: NSImage = batteryOutline.tint(color: fillColor)
        let startCap: NSImage = capacityCapLeft.tint(color: fillColor)
        let fill: NSImage     = capacityFill.tint(color: fillColor)
        let endCap: NSImage   = capacityCapRight.tint(color: fillColor)

        outline.lockFocus()
        NSDrawThreePartImage(drawingRect, startCap, fill, endCap, false, .copy, 1, false)
        // Overlay the charging symbol in black, so it stays visible on top of the fill.
        if let chargingSymbol = batteryImage(named: .chargingSymbol) {
            let symbol = chargingSymbol.tint(color: .black)
            symbol.draw(in: NSRect(x: (outline.size.width - symbol.size.width) / 2,
                                   y: (outline.size.height - symbol.size.height) / 2,
                                   width: symbol.size.width,
                                   height: symbol.size.height))
        }
        outline.unlockFocus()

        return outline
    }

    ///  Returns the image object associated with the specified name as template.
    ///
    ///  - parameter name: The name of an image in the app bundle.
    ///  - parameter lowPowerMode: Whether Low Power Mode is active (tints the image yellow).
    ///  - returns: An image object associated with the specified name as template.
    private func batteryImage(named name: BatteryImage, lowPowerMode: Bool = false) -> NSImage? {
        guard let img = NSImage(named: name.rawValue) else { return nil }
        img.isTemplate = true
        if lowPowerMode {
            return img.tint(color: .systemYellow)
        }

        return img
    }

}
