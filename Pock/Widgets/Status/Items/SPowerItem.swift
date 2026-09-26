//
//  SPowerItem.swift
//  Pock
//
//  Created by Pierluigi Galdi on 23/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import Defaults
import IOKit.ps

struct SPowerStatus {
    var isCharging: Bool, currentValue: Int
}

class SPowerItem: StatusItem, ClickListener {
    
    /// Core
    private var refreshTimer: Timer?
    private var powerStatus: SPowerStatus = SPowerStatus(isCharging: false, currentValue: 0)
    private var shouldShowBatteryIcon: Bool {
        return Defaults[.shouldShowBatteryIcon]
    }
    private var shouldShowBatteryPercentage: Bool {
        return Defaults[.shouldShowBatteryPercentage]
    }
    private var shouldShowBatteryTime: Bool {
        return Defaults[.shouldShowBatteryTime]
    }
    
    private var lastShouldShowBatteryIcon: Bool = false
    private var lastShouldShowBatteryPercentage: Bool = false
    private var lastShouldShowBatteryTime: Bool = false
    
    /// An abstraction to the battery IO service
    private var battery: BatteryService!
    
    /// UI
    private var stackView: NSClickableStack = NSClickableStack(frame: .zero, id: -11)
    private let iconView: NSImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    private let valueLabel: NSTextField = NSTextField(frame: .zero)
    ///  The icon to display in the battery status bar item.
    private var icon: StatusBarIcon?
    
    init() {
        lastShouldShowBatteryIcon = shouldShowBatteryIcon
        lastShouldShowBatteryTime = shouldShowBatteryTime
        lastShouldShowBatteryPercentage = shouldShowBatteryPercentage
        didLoad()
        //reload()
    }
    
    deinit {
        didUnload()
    }
    
    func didLoad() {
        configureValueLabel()
        configureStackView()
        lastPercentage = nil
        lastBatteryTime = nil
        lowPowerMode = false
        do {
            icon = StatusBarIcon()
            battery = try BatteryService()
            setBatteryStatus(battery)
            registerAsObserver()
            startRefreshTimer()
        } catch {
        }
    }

    func didUnload() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        battery.closeServiceConnection()
    }

    ///  Periodic fallback refresh, in case Low Power Mode toggles do not post power source notifications.
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.setBatteryStatus(self?.battery)
        }
    }
    
    /// Registers the ApplicationController as observer for power source and user preference changes
    private func registerAsObserver() {
        NotificationCenter.default
            .addObserver(self,
                         selector: #selector(SPowerItem.powerSourceChanged(_:)),
                         name: NSNotification.Name(rawValue: powerSourceChangedNotification),
                         object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(onWakeNote(note:)),
                name: NSWorkspace.didWakeNotification, object: nil)
    }
    
    @objc func onWakeNote(note: NSNotification) {
        setBatteryStatus(battery)
    }
    
    ///  This message is sent to the receiver, when a powerSourceChanged message was posted. The receiver
    ///  must be registered as an observer for powerSourceChangedNotification's.
    ///
    ///  - parameter sender: The object that posted powerSourceChanged message.
    @objc public func powerSourceChanged(_: AnyObject) {
        setBatteryStatus(battery)
    }
    
    var enabled: Bool{ return Defaults[.shouldShowPowerItem] }
    
    var title: String  { return "power" }
    
    var view: NSView { return stackView }
    
    func action() {
        if !isProd { print("[Pock]: Power Status icon tapped!") }
    }
    
    private func configureValueLabel() {
        valueLabel.font = NSFont.systemFont(ofSize: 13)
        valueLabel.backgroundColor = .clear
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.isBezeled = false
        valueLabel.isEditable = false
        valueLabel.sizeToFit()
    }
    
    private func configureStackView() {
        stackView = NSClickableStack(frame: .zero, id: -11)
        stackView.clickDelegate = self
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 2
        stackView.addArrangedSubview(valueLabel)
        stackView.addArrangedSubview(iconView)
    }
    
    var lastPercentage: BatteryState? = nil
    var lastBatteryTime: String? = nil
    ///  Low Power Mode state as reported by `pmset`. The IOPS snapshot the BatteryService
    ///  reads from is throttled by the system to ~30 seconds for data that does not
    ///  trigger a power source notification, so Low Power Mode toggles are read from
    ///  `pmset -g` instead, which is always fresh.
    private var lowPowerMode: Bool = false
    private let pmsetQueue = DispatchQueue(label: "Pock.LowPowerModeCheck", qos: .utility)

    /// Marker files watched by the Low Power Mode LaunchDaemons, and their plists.
    private static let lpmMarkerOn     = "/private/var/tmp/pock.lpm.on"
    private static let lpmMarkerOff    = "/private/var/tmp/pock.lpm.off"
    private static let lpmDaemonPlistOn  = "/Library/LaunchDaemons/ch.pock.lpm.on.plist"
    private static let lpmDaemonPlistOff = "/Library/LaunchDaemons/ch.pock.lpm.off.plist"

    ///  Sets the pock bar item's battery icon.
    ///
    ///  - parameter battery: The battery to render the status bar icon for.
    private func setBatteryStatus(_ battery: BatteryService?) {
        if let batteryState = battery?.state {
            if lastPercentage != batteryState {
                setBatteryIcon(batteryState, lowPowerMode: lowPowerMode)
            }
            lastPercentage = batteryState
            if !shouldShowBatteryTime {
                setTitle(battery)
            }
        }
        refreshLowPowerMode()
        if shouldShowBatteryTime {
            if let timeRemaining = battery?.timeRemainingFormatted {
                valueLabel.isHidden = false
                if lastBatteryTime != timeRemaining {
                    lastBatteryTime = "\(timeRemaining)"
                    valueLabel.stringValue = timeRemaining
                }
            }
        }
    }

    ///  Reads the Low Power Mode state from `pmset -g` in the background and redraws
    ///  the icon on the main thread when it changed.
    private func refreshLowPowerMode() {
        pmsetQueue.async { [weak self] in
            let isOn = SPowerItem.readLowPowerModeFromPMSet()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.refreshTimer != nil, isOn != self.lowPowerMode else { return }
                NSLog("[Pock][Battery] Low Power Mode changed to %d (pmset)", isOn ? 1 : 0)
                self.lowPowerMode = isOn
                if let batteryState = self.battery?.state {
                    self.setBatteryIcon(batteryState, lowPowerMode: isOn)
                }
            }
        }
    }

    ///  Parses `pmset -g` for the "lowpowermode" line.
    private static func readLowPowerModeFromPMSet() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutPipe.fileHandleForReading.closeFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return false
        }
        return output.range(of: "lowpowermode[ \t]+1", options: .regularExpression) != nil
    }


    ///  Sets the pock bar item's battery icon.
    private func setBatteryIcon(_ batteryState: BatteryState, lowPowerMode: Bool) {
        if shouldShowBatteryIcon {
            iconView.image = icon?.drawBatteryImage(forStatus: batteryState, lowPowerMode: lowPowerMode)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
            iconView.image    = nil
        }
    }
    
    ///  Sets the pock bar item's title
    ///
    ///  - parameter battery: The battery to build the status bar title for.
    private func setTitle(_ battery: BatteryService?) {
        if shouldShowBatteryTime {
            guard let timeRemaining = battery?.timeRemainingFormatted
            else {
                return
            }
            valueLabel.isHidden = false
            valueLabel.stringValue = timeRemaining
        } else if shouldShowBatteryPercentage {
            guard let percentage = battery?.percentageFormatted
            else {
                return
            }
            valueLabel.isHidden = false
            valueLabel.stringValue = percentage
        } else {
            valueLabel.isHidden = true
            valueLabel.stringValue = ""
        }
    }
    
    // click handlers
    func didTapHandler() {
        if !Defaults[.shouldMakeClickable] {
            return
        }
        toggleLowPowerMode()
    }

    ///  Toggles Low Power Mode (économie d'énergie). `pmset` requires root, so a
    ///  one-time installed pair of LaunchDaemons (installed with a single admin
    ///  password prompt) performs the change; the app only touches marker files,
    ///  which needs no privileges.
    private func toggleLowPowerMode() {
        let installed = FileManager.default.fileExists(atPath: SPowerItem.lpmDaemonPlistOn) &&
                        FileManager.default.fileExists(atPath: SPowerItem.lpmDaemonPlistOff)
        if installed {
            triggerLowPowerMode()
        } else {
            installLowPowerHelpers()
        }
    }

    ///  Signals the LaunchDaemon by writing the target state into its watch file.
    private func triggerLowPowerMode() {
        let target = lowPowerMode ? 0 : 1
        let marker = target == 1 ? SPowerItem.lpmMarkerOn : SPowerItem.lpmMarkerOff
        if !FileManager.default.createFile(atPath: marker, contents: Data([UInt8(48 + target)])) {
            NSLog("[Pock][Battery] Could not write LPM marker \(marker)")
        }
        // The next `pmset -g` poll picks up the new state and recolors the icon.
    }

    ///  Installs the two LaunchDaemons (one per target state) with a single
    ///  administrator password prompt.
    private var isInstallingLowPowerHelpers = false
    private func installLowPowerHelpers() {
        guard !isInstallingLowPowerHelpers else { return }
        isInstallingLowPowerHelpers = true
        let tmpDir = NSTemporaryDirectory() as NSString
        let onPlistPath  = tmpDir.appendingPathComponent("ch.pock.lpm.on.plist")
        let offPlistPath = tmpDir.appendingPathComponent("ch.pock.lpm.off.plist")
        try? SPowerItem.launchDaemonPlist(label: "ch.pock.lpm.on", mode: 1, marker: SPowerItem.lpmMarkerOn)
            .write(toFile: onPlistPath, atomically: true, encoding: .utf8)
        try? SPowerItem.launchDaemonPlist(label: "ch.pock.lpm.off", mode: 0, marker: SPowerItem.lpmMarkerOff)
            .write(toFile: offPlistPath, atomically: true, encoding: .utf8)
        let user = NSUserName()
        let script = "do shell script \"cp '\(onPlistPath)' /Library/LaunchDaemons/ && cp '\(offPlistPath)' /Library/LaunchDaemons/ && touch \(SPowerItem.lpmMarkerOn) \(SPowerItem.lpmMarkerOff) && chown \(user) \(SPowerItem.lpmMarkerOn) \(SPowerItem.lpmMarkerOff) && (launchctl bootout system/ch.pock.lpm.on 2>/dev/null; launchctl bootout system/ch.pock.lpm.off 2>/dev/null; true) && launchctl bootstrap system /Library/LaunchDaemons/ch.pock.lpm.on.plist && launchctl bootstrap system /Library/LaunchDaemons/ch.pock.lpm.off.plist\" with administrator privileges"
        pmsetQueue.async { [weak self] in
            _ = self?.runOsascript(script)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isInstallingLowPowerHelpers = false
                if FileManager.default.fileExists(atPath: SPowerItem.lpmDaemonPlistOn) {
                    self.triggerLowPowerMode()
                } else {
                    NSLog("[Pock][Battery] LPM helper installation failed or was cancelled")
                }
            }
        }
    }

    ///  launchd plist for one Low Power Mode helper: watches the marker file and
    ///  runs `pmset -a lowpowermode <mode>` as root when the file is written to.
    private static func launchDaemonPlist(label: String, mode: Int, marker: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(label)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>/bin/sh</string>
        \t\t<string>-c</string>
        \t\t<string>/usr/bin/pmset -a lowpowermode \(mode)</string>
        \t</array>
        \t<key>WatchPaths</key>
        \t<array>
        \t\t<string>\(marker)</string>
        \t</array>
        </dict>
        </plist>
        """
    }

    ///  Runs an AppleScript source through `/usr/bin/osascript`, returns its output.
    private func runOsascript(_ source: String) -> String? {
        guard let scriptData = source.data(using: .utf8) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        stdinPipe.fileHandleForWriting.write(scriptData)
        stdinPipe.fileHandleForWriting.closeFile()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutPipe.fileHandleForReading.closeFile()
        return String(data: data, encoding: .utf8)
    }
    
    func didLongPressHandler() {
        if !Defaults[.shouldMakeClickable] {
            return
        }
        if shouldShowBatteryTime {
            Defaults[.shouldShowBatteryTime] = false
            Defaults[.shouldShowBatteryPercentage] = true
            NSWorkspace.shared.notificationCenter.post(name: .shouldReloadStatusWidget, object: nil)
        } else if shouldShowBatteryPercentage {
            Defaults[.shouldShowBatteryTime] = true
            Defaults[.shouldShowBatteryPercentage] = false
            NSWorkspace.shared.notificationCenter.post(name: .shouldReloadStatusWidget, object: nil)
        }
    }
    
    func didSwipeLeftHandler() {
    }
    
    func didSwipeRightHandler() {
    }
    
    func reload() {
        /*
        if lastShouldShowBatteryPercentage != shouldShowBatteryPercentage ||
            lastShouldShowBatteryTime != shouldShowBatteryTime {
            lastShouldShowBatteryTime = shouldShowBatteryTime
            lastShouldShowBatteryPercentage = shouldShowBatteryPercentage
            setTitle(battery)
        }
        if lastShouldShowBatteryIcon != shouldShowBatteryIcon {
            lastShouldShowBatteryIcon = shouldShowBatteryIcon
            if let batteryState = battery?.state {
                setBatteryIcon(batteryState)
            }
        }*/
    }
}
