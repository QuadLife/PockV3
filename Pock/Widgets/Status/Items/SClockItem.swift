//
//  SClockItem.swift
//  Pock
//
//  Created by Pierluigi Galdi on 23/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import Defaults

class SClockItem: StatusItem, ClickListener {
    
    /// Core
    private var refreshTimer: Timer?
    
    /// UI
    private var clockLabel: NSClickableTextField!
    
    init() {
        didLoad()
        reload()
    }
    
    deinit {
        didUnload()
    }
    
    func didLoad() {
        // Required else it will lose reference to button currently being displayed
        if clockLabel == nil {
            clockLabel = NSClickableTextField(id: -1111)
            clockLabel.clickDelegate = self
            clockLabel.frame = CGRect(origin: .zero, size: CGSize(width: 100, height: 44))
            clockLabel.font = NSFont.systemFont(ofSize: 13)
            clockLabel.backgroundColor = .clear
            clockLabel.isBezeled = false
            clockLabel.isEditable = false
            clockLabel.sizeToFit()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            self?.reload()
        })
    }
    
    func didUnload() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    var enabled: Bool{ return Defaults[.shouldShowDateItem] }
    
    var title: String  { return "clock" }
    
    var view: NSView { return clockLabel }
    
    func action() {
        if !isProd { print("[Pock]: Clock Status icon tapped!") }
    }
    
    func reload() {
        var format = Defaults[.timeFormatTextField]
        if Defaults[.shouldShowClockSeconds], !format.contains("ss") {
            /// Insert ":ss" ("seconds") after the minutes token, e.g.
            /// "EE dd MMM HH:mm" → "EE dd MMM HH:mm:ss".
            let nsFormat = (format as NSString)
            let range = nsFormat.range(of: "mm", options: .backwards)
            if range.location != NSNotFound {
                format = nsFormat.replacingCharacters(in: NSRange(location: range.location + range.length, length: 0),
                                                      with: ":ss")
            }else {
                format.append("ss")
            }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en_US_POSIX")
        let tempLabel = formatter.string(from: Date())
        if tempLabel != clockLabel?.stringValue {
            clockLabel?.stringValue = tempLabel
            clockLabel?.sizeToFit()
        }
    }
    
    // click handlers
    func didTapHandler() {
        if !Defaults[.shouldMakeClickable] {
            return
        }
        NSWorkspace.shared.launchApplication("Calendar")
    }
    
    func didLongPressHandler() {
    }
    
    func didSwipeLeftHandler() {
    }
    
    func didSwipeRightHandler() {
    }
}
