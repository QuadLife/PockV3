//
//  PockMainController.swift
//  Pock
//
//  Created by Pierluigi Galdi on 21/10/2018.
//  Copyright © 2018 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit
import Defaults
import PockKit

/// Custom identifiers
extension NSTouchBar.CustomizationIdentifier {
    static let pockTouchBar = "PockTouchBar"
}
extension NSTouchBarItem.Identifier {
    static let pockSystemIcon = NSTouchBarItem.Identifier("Pock")
    static let dockView       = NSTouchBarItem.Identifier("Dock")
    static let escButton      = NSTouchBarItem.Identifier("Esc")
    static let controlCenter  = NSTouchBarItem.Identifier("ControlCenter")
    static let nowPlaying     = NSTouchBarItem.Identifier("NowPlaying")
    static let status         = NSTouchBarItem.Identifier("Status")
}

class PockMainController: PKTouchBarController {

    required override init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadScreenEdgeController),
                                               name: .shouldReloadScreenEdgeController,
                                               object: nil)
    }

    override var systemTrayItem: NSCustomTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: .pockSystemIcon)
        item.view = NSButton(image: #imageLiteral(resourceName: "pock-inner-icon"), target: self, action: #selector(presentFromSystemTrayItem))
        return item
    }
    override var systemTrayItemIdentifier: NSTouchBarItem.Identifier? { return .pockSystemIcon }

    deinit {
        WidgetsDispatcher.default.clearLoadedWidgets()
        edgeController?.tearDown(invalidate: true)
        edgeController = nil
        if !isProd { print("[PockMainController]: Deinit Pock main controller") }
    }

    override func didLoad() {
        WidgetsDispatcher.default.loadInstalledWidget() { widgets in
            self.touchBar?.customizationIdentifier              = .pockTouchBar
            self.touchBar?.defaultItemIdentifiers               = [.nowPlaying, .dockView, .controlCenter, .status]
            self.touchBar?.customizationAllowedItemIdentifiers  = [.escButton, .dockView, .controlCenter, .nowPlaying, .status]

            let customizableIds: [NSTouchBarItem.Identifier] = widgets.map({ $0.identifier })
            self.touchBar?.customizationAllowedItemIdentifiers.append(contentsOf: customizableIds)

            super.awakeFromNib()
        }
        /// Mouse support: give the Touch Bar views a moment to load, then install
        /// the screen edge tracker (re-created on every `present()`).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.parentView = self.touchBarView
            if self.parentView != nil {
                self.reloadScreenEdgeController()
            }else {
                /// The Touch Bar window may not exist yet — try again shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    self.parentView = self.touchBarView
                    self.reloadScreenEdgeController()
                }
            }
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let item = cachedItems[identifier] {
            return item
        }
        var widget: PKWidget?
        switch identifier {
        /// Esc button
        case .escButton:
            widget = EscWidget()
        /// Dock widget
        case .dockView:
            widget = DockWidget()
        /// ControlCenter widget
        case .controlCenter:
            widget = ControlCenterWidget()
        /// NowPlaying widget
        case .nowPlaying:
            widget = NowPlayingWidget()
        /// Status widget
        case .status:
            widget = StatusWidget()
        default:
            widget = WidgetsDispatcher.default.loadedWidgets[identifier]
        }
        guard widget != nil else { return nil }
        let item = PKWidgetTouchBarItem(widget: widget!)
        cachedItems[identifier] = item
        return item
    }

    // MARK: - Mouse support (ported from PockKit v1 `PKTouchBarMouseController`)

    /// The screen edge tracker: an invisible 10pt window along the bottom edge
    /// of the screen which forwards mouse events to the Touch Bar.
    private var edgeController: PKScreenEdgeController?
    private var cursorView: NSView?
    private var draggingInfoView: PKDraggingInfoView?
    private var parentView: NSView?
    private var cachedItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]

    /// The actual Touch Bar view, discovered through a private API.
    private var touchBarView: NSView? {
        /// 1. Legacy (macOS < 27): `NSFunctionRow._topLevelViews()`.
        if let functionRowClass = NSClassFromString("NSFunctionRow"),
           class_getClassMethod(functionRowClass, NSSelectorFromString("_topLevelViews")) != nil,
           let result = (functionRowClass as? NSObject.Type)?.perform(NSSelectorFromString("_topLevelViews")),
           let views = result.takeUnretainedValue() as? [NSView],
           let view = views.last {
            NSLog("[Pock][Mouse] Touch Bar view found via NSFunctionRow._topLevelViews().")
            return view
        }
        /// 2. macOS 27+: Pock's own widget views (e.g. the Dock scrubber) are
        /// rendered inside the Touch Bar window — walk up to its `NSTouchBarView`.
        for item in cachedItems.values {
            guard let widgetItem = item as? PKWidgetTouchBarItem else {
                continue
            }
            var view: NSView? = widgetItem.view
            while let current = view {
                if NSStringFromClass(type(of: current)) == "NSTouchBarView" {
                    NSLog("[Pock][Mouse] Touch Bar view found via NSTouchBarView superview chain.")
                    return current
                }
                view = current.superview
            }
            if let window = widgetItem.view.window {
                NSLog("[Pock][Mouse] Touch Bar view not found, using widget window contentView (class: %@).", NSStringFromClass(type(of: window)))
                return window.contentView
            }
        }
        NSLog("[Pock][Mouse] Touch Bar view not found.")
        return nil
    }

    /// Widgets that handle screen-edge mouse events themselves (e.g. the Dock).
    private var mouseDelegates: [PKScreenEdgeMouseDelegate] {
        return cachedItems.values.compactMap({ ($0 as? PKWidgetTouchBarItem)?.screenEdgeMouseDelegate })
    }

    /// (Re-)create the screen edge tracker according to the user preferences.
    @objc func reloadScreenEdgeController() {
        edgeController?.tearDown(invalidate: true)
        edgeController = nil
        guard Defaults[.mouseSupportEnabled], let parentView = self.parentView else {
            return
        }
        let color: NSColor = Defaults[.showTrackingArea] ? .systemBlue : .clear
        edgeController = PKScreenEdgeController(mouseDelegate: self, parentView: parentView, barColor: color)
    }

    override func visibilityDidChange(_ visible: Bool) {
        edgeController?.window?.setIsVisible(visible)
        if !visible {
            showCursor(nil, at: nil)
            showDraggingInfo(nil, filepath: nil)
        }
    }

    private func forwardToMouseDelegates(_ body: (PKScreenEdgeMouseDelegate) -> Void) {
        mouseDelegates.forEach(body)
    }

    // MARK: Cursor / dragging info views

    private func showCursor(_ cursor: NSCursor?, at location: NSPoint?) {
        cursorView?.removeFromSuperview()
        cursorView = nil
        guard let cursor = cursor, let location = location, let parentView = parentView else {
            return
        }
        cursorView = NSImageView(image: cursor.image)
        cursorView?.frame.size = NSSize(width: 20, height: 20)
        cursorView?.wantsLayer = true
        parentView.addSubview(cursorView!)
        cursorView?.layer?.zPosition = 999
        updateCursorLocation(location)
    }

    private func updateCursorLocation(_ location: NSPoint?) {
        guard let location = location else {
            return
        }
        cursorView?.frame.origin = location
    }

    private func showDraggingInfo(_ info: NSDraggingInfo?, filepath: String?) {
        draggingInfoView?.removeFromSuperview()
        draggingInfoView = nil
        guard let info = info, let filepath = filepath, let parentView = parentView else {
            return
        }
        draggingInfoView = PKDraggingInfoView(filepath: URL(fileURLWithPath: filepath))
        draggingInfoView?.wantsLayer = true
        parentView.addSubview(draggingInfoView!, positioned: .below, relativeTo: cursorView)
        draggingInfoView?.layer?.zPosition = 998
        updateDraggingInfoLocation(info.draggingLocation, animated: false)
    }

    private func updateDraggingInfoLocation(_ location: NSPoint, animated: Bool = true) {
        guard let view = draggingInfoView else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.1275 : 0), execute: {
            view.frame.origin = NSPoint(x: location.x - view.frame.width + 8, y: location.y)
        })
    }

}

// MARK: - PKScreenEdgeMouseDelegate
extension PockMainController: PKScreenEdgeMouseDelegate {

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {
        showCursor(.arrow, at: location)
        forwardToMouseDelegates({ $0.screenEdgeController(controller, mouseEnteredAtLocation: location, in: view) })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {
        updateCursorLocation(location)
        forwardToMouseDelegates({ $0.screenEdgeController(controller, mouseMovedAtLocation: location, in: view) })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
        forwardToMouseDelegates({ $0.screenEdgeController(controller, mouseClickAtLocation: location, in: view) })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseRightClickAtLocation location: NSPoint, in view: NSView) {
        guard Defaults[.dockContextMenuEnabled] else { return }
        forwardToMouseDelegates({
            $0.screenEdgeController?(controller, mouseRightClickAtLocation: location, in: view)
        })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {
        showCursor(nil, at: nil)
        showDraggingInfo(nil, filepath: nil)
        forwardToMouseDelegates({ $0.screenEdgeController(controller, mouseExitedAtLocation: location, in: view) })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseScrollWithDelta delta: CGFloat, atLocation location: NSPoint, in view: NSView) {
        forwardToMouseDelegates({
            $0.screenEdgeController?(controller, mouseScrollWithDelta: delta, atLocation: location, in: view)
        })
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, draggingEntered info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
        showDraggingInfo(info, filepath: filepath)
        updateCursorLocation(info.draggingLocation)
        for delegate in mouseDelegates {
            if let operation = delegate.screenEdgeController?(controller, draggingEntered: info, filepath: filepath, in: view) {
                return operation
            }
        }
        return NSDragOperation()
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, draggingUpdated info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
        updateCursorLocation(info.draggingLocation)
        updateDraggingInfoLocation(info.draggingLocation)
        for delegate in mouseDelegates {
            if let operation = delegate.screenEdgeController?(controller, draggingUpdated: info, filepath: filepath, in: view) {
                return operation
            }
        }
        return NSDragOperation()
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, performDragOperation info: NSDraggingInfo, filepath: String, in view: NSView) -> Bool {
        for delegate in mouseDelegates {
            if let result = delegate.screenEdgeController?(controller, performDragOperation: info, filepath: filepath, in: view) {
                return result
            }
        }
        return false
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, draggingEnded info: NSDraggingInfo, in view: NSView) {
        showDraggingInfo(nil, filepath: nil)
        forwardToMouseDelegates({
            $0.screenEdgeController?(controller, draggingEnded: info, in: view)
        })
    }

}