//
//  DockWidget.swift
//  Pock
//
//  Created by Pierluigi Galdi on 06/04/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit
import Defaults

/// Passive gesture recognizer which observes Touch Bar touches on the scrubber
/// without ever claiming them — the scrubber's internal pan recognizer keeps
/// handling scrolling. NSScrubber receives touches only through its internal
/// gesture recognizers (touch responder methods never fire), so this is the
/// hook for the long-press context menu.
class DockLongPressObserver: NSGestureRecognizer {

    var onBegan:  ((NSTouch) -> Void)?
    var onEnded:  (() -> Void)?

    private var touchStarted = false
    private var startLocation: NSPoint = .zero

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.allTouches().first, let view = view else { return }
        touchStarted = true
        startLocation = touch.location(in: view)
        onBegan?(touch)
        /// stay in `.possible` — never claim the gesture
    }

    override func touchesMoved(with event: NSEvent) {
        guard touchStarted, let touch = event.allTouches().first, let view = view else { return }
        let location = touch.location(in: view)
        let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
        if distance > 10 {
            /// the finger moved — that is a scrub, not a hold
            onEnded?()
            touchStarted = false
        }
    }

    override func touchesEnded(with event: NSEvent) {
        if touchStarted {
            onEnded?()
            touchStarted = false
        }
        state = .failed
    }

    override func touchesCancelled(with event: NSEvent) {
        if touchStarted {
            onEnded?()
            touchStarted = false
        }
        state = .failed
    }

}

class DockWidget: NSObject, PKWidget {
    
    var identifier: NSTouchBarItem.Identifier = NSTouchBarItem.Identifier.dockView
    var customizationLabel: String            = "Dock".localized
    var view: NSView!
    
    /// Core
    private var dockRepository: DockRepository!
    
    /// UI
    private var stackView:           NSStackView! = NSStackView(frame: .zero)
    private var dockScrubber:        NSScrubber! = NSScrubber(frame: NSRect(x: 0, y: 0, width: 200,  height: 30))
    private var separator:           NSView! = NSView(frame:     NSRect(x: 0, y: 0, width: 1,    height: 20))
    private var persistentScrubber: NSScrubber! = NSScrubber(frame: NSRect(x: 0, y: 0, width: 50,   height: 30))
    private var lastVisibleRange:   NSRange! = NSRange(location: 0, length: 0)

    /// Launch deferred until the finger leaves the icon (see `didSelectItemAt`).
    private var pendingLaunch: (scrubber: NSScrubber, item: DockItem)?

    /// Long-press (3 seconds) on an icon shows the Dock context menu, like a
    /// right-click. Touches on the Touch Bar arrive as `.touches` events; they
    /// are absorbed by the scrubber's internal scroll view, so they can't be
    /// caught on the item views themselves — hence this app-level monitor.
    private var touchEventMonitor: Any?
    private var longPressTimer:      DispatchSourceTimer?
    private var longPressItemView:   DockItemView?
    private var longPressObservers:  [DockLongPressObserver] = []
    
    /// Data
    private var dockItems:       [DockItem] = []
    private var persistentItems: [DockItem] = []
    private var cachedItemViews: [Int: DockItemView] = [:]
    
    required override init() {
        super.init()
        
        self.configureStackView()
        self.configureDockScrubber()
        self.configureSeparator()
        self.configurePersistentScrubber()
        self.displayScrubbers()
        self.view = stackView
        self.dockRepository = DockRepository(delegate: self)
        self.dockRepository.reload(nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayScrubbers), name: .shouldReloadPersistentItems, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reloadDockScrubberLayout), name: .shouldReloadDockLayout, object: nil)
        /// Monitor the gesture/touch event family only — a catch-all mask makes
        /// AppKit route internal events (`.appKitDefined`, …) through the local
        /// monitor, which is unsupported and crashes.
        var touchMask: NSEvent.EventTypeMask = [.gesture, .beginGesture, .endGesture, .magnify, .swipe, .rotate, .smartMagnify, .pressure]
        touchMask.formUnion(NSEvent.EventTypeMask(rawValue: (1 << 37) | (1 << 11) | (1 << 12)))
        touchEventMonitor = NSEvent.addLocalMonitorForEvents(matching: touchMask, handler: { [weak self] event in
            self?.handleTouch(event)
            return event
        })
    }

    deinit {
        stackView           = nil
        dockScrubber        = nil
        separator           = nil
        persistentScrubber  = nil
        dockRepository      = nil
        longPressTimer?.cancel()
        longPressTimer      = nil
        longPressItemView   = nil
        if let monitor = touchEventMonitor {
            NSEvent.removeMonitor(monitor)
            touchEventMonitor = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    /// Configure stack view
    private func configureStackView() {
        stackView.alignment = .centerY
        stackView.orientation = .horizontal
        stackView.distribution = .fill
    }
    
    @objc private func displayScrubbers() {
        self.separator.isHidden          = Defaults[.hidePersistentItems] || persistentItems.isEmpty
        self.persistentScrubber.isHidden = Defaults[.hidePersistentItems] || persistentItems.isEmpty
    }
    
    @objc private func reloadDockScrubberLayout() {
        let dockLayout              = NSScrubberFlowLayout()
        dockLayout.itemSize         = Constants.dockItemSize
        dockLayout.itemSpacing      = CGFloat(Defaults[.itemSpacing])
        dockScrubber.scrubberLayout = dockLayout
        let persistentLayout              = NSScrubberFlowLayout()
        persistentLayout.itemSize         = Constants.dockItemSize
        persistentLayout.itemSpacing      = CGFloat(Defaults[.itemSpacing])
        persistentScrubber.scrubberLayout = persistentLayout
    }
    
    /// Configure dock scrubber
    private func configureDockScrubber() {
        let layout = NSScrubberFlowLayout()
        layout.itemSize    = Constants.dockItemSize
        layout.itemSpacing = CGFloat(Defaults[.itemSpacing])
        dockScrubber.dataSource = self
        dockScrubber.delegate = self
        dockScrubber.showsAdditionalContentIndicators = true
        dockScrubber.mode = .free
        dockScrubber.isContinuous = false
        dockScrubber.itemAlignment = .none
        dockScrubber.scrubberLayout = layout
        attachLongPressObserver(to: dockScrubber)
        stackView.addArrangedSubview(dockScrubber)
    }
    
    /// Configure separator
    private func configureSeparator() {
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.darkGray.cgColor
        separator.snp.makeConstraints({ m in
            m.width.equalTo(1)
            m.height.equalTo(20)
        })
        stackView.addArrangedSubview(separator)
    }
    
    /// Configure persistent scrubber
    private func configurePersistentScrubber() {
        let layout = NSScrubberFlowLayout()
        layout.itemSize    = Constants.dockItemSize
        layout.itemSpacing = CGFloat(Defaults[.itemSpacing])
        persistentScrubber.dataSource = self
        persistentScrubber.delegate = self
        persistentScrubber.showsAdditionalContentIndicators = true
        persistentScrubber.mode = .free
        persistentScrubber.isContinuous = false
        persistentScrubber.itemAlignment = .none
        persistentScrubber.scrubberLayout = layout
        attachLongPressObserver(to: persistentScrubber)
        persistentScrubber.snp.makeConstraints({ m in
            m.width.equalTo((Constants.dockItemSize.width + 8) * CGFloat(persistentItems.count))
        })
        stackView.addArrangedSubview(persistentScrubber)
    }
    
}

extension DockWidget: DockDelegate {
    func didUpdate(apps: [DockItem]) {
        update(scrubber: dockScrubber, oldItems: dockItems, newItems: apps) { [weak self] apps in
            apps.enumerated().forEach({ index, item in
                item.index = index
            })
            self?.dockItems = apps
        }
    }
    func didUpdate(items: [DockItem]) {
        update(scrubber: persistentScrubber, oldItems: persistentItems, newItems: items) { [weak self] items in
            self?.persistentItems = items
            self?.displayScrubbers()
            self?.persistentScrubber.snp.updateConstraints({ m in
                m.width.equalTo((Constants.dockItemSize.width + 8) * CGFloat(self?.persistentItems.count ?? 0))
            })
        }
    }
    
    @discardableResult
    private func updateView(for item: DockItem?) -> DockItemView? {
        guard let item = item else { return nil }
        var view: DockItemView! = cachedItemViews[item.diffId]
        if view == nil {
            view = DockItemView(frame: .zero)
            cachedItemViews[item.diffId] = view
        }
        view.dockItem = item
        view.clear()
        view.set(icon:        item.icon)
        view.set(hasBadge:    item.hasBadge)
        view.set(isRunning:   item.isRunning)
        view.set(isFrontmost: item.isFrontmost)
        return view
    }
    
    private func update(scrubber: NSScrubber?, oldItems: [DockItem], newItems: [DockItem], completion: (([DockItem]) -> Void)? = nil) {
        guard let scrubber = scrubber else {
            completion?(newItems)
            return
        }
        DispatchQueue.main.async { [weak self] in
            completion?(newItems)
            scrubber.reloadData()
            var toIndex = self?.lastVisibleRange.upperBound ?? 0
            if scrubber.numberOfItems > 0 {
                toIndex = toIndex >= scrubber.numberOfItems ? (scrubber.numberOfItems - 1) : toIndex
                scrubber.scrollItem(at: toIndex < 0 ? 0 : toIndex, to: .none)
            }
        }
    }
    func didUpdateBadge(for apps: [DockItem]) {
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.cachedItemViews.forEach({ key, view in
                view.set(hasBadge: apps.first(where: { $0.diffId == key })?.hasBadge ?? false)
            })
        }
    }
    func didUpdateRunningState(for apps: [DockItem]) {
        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.cachedItemViews.forEach({ key, view in
                let item = apps.first(where: { $0.diffId == key })
                view.set(isRunning:   item?.isRunning   ?? false)
                view.set(isFrontmost: item?.isFrontmost ?? false)
                view.set(isLaunching: item?.isLaunching ?? false)
                if let i = item, i.isFrontmost && !i.isPersistentItem {
                    s.dockScrubber?.animator().scrollItem(at: i.index, to: .none)
                }
            })
        }
    }
}

extension DockWidget: NSScrubberDataSource {
    func numberOfItems(for scrubber: NSScrubber) -> Int {
        if scrubber == persistentScrubber {
            return persistentItems.count
        }
        return dockItems.count
    }
    
    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let item = scrubber == persistentScrubber ? persistentItems[index] : dockItems[index]
        return updateView(for: item)!
    }
}

extension DockWidget: NSScrubberDelegate {
    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        let item = scrubber == persistentScrubber ? persistentItems[selectedIndex] : dockItems[selectedIndex]
        let itemView = cachedItemViews[item.diffId]
        if itemView?.longPressMenuShown == true {
            /// The context menu was just shown by the long-press: don't launch.
            itemView?.longPressMenuShown = false
            scrubber.selectedIndex = -1
            return
        }
        if itemView?.touchInProgress == true {
            /// The selection arrived while the finger is still down: wait for
            /// the touch to end (a 3-second hold shows the menu instead).
            pendingLaunch = (scrubber, item)
            return
        }
        launch(item: item)
        scrubber.selectedIndex = -1
    }

    /// Launches the given dock item, as a click on it would.
    private func launch(item: DockItem) {
        var result: Bool = false
        if item.bundleIdentifier?.lowercased() == "com.apple.finder" {
            dockRepository.launch(bundleIdentifier: item.bundleIdentifier, completion: { result = $0 })
        }else {
            dockRepository.launch(item: item, completion: { result = $0 })
        }
        NSLog("[Pock]: Did open: \(item.bundleIdentifier ?? item.path?.absoluteString ?? "Unknown") [success: \(result)]")
    }

    /// Launches the deferred item, if any (finger left the icon without the
    /// long-press menu being shown).
    private func launchPendingItem() {
        guard let pending = pendingLaunch else { return }
        pendingLaunch = nil
        launch(item: pending.item)
        pending.scrubber.selectedIndex = -1
    }

    // MARK: Long-press (Touch Bar touch monitor)

    /// How long the finger must stay on an icon to show the Dock context menu,
    /// like a right-click would.
    private static let longPressDelay: TimeInterval = 1.5

    private func handleTouch(_ event: NSEvent) {
        guard Defaults[.dockContextMenuEnabled] else { return }
        guard let touch = event.allTouches().first else { return }
        /// Only Touch Bar touches: the event's window must be the Touch Bar window.
        if let someItemView = cachedItemViews.values.first, let touchBarWindow = someItemView.window {
            guard event.window === touchBarWindow else { return }
            if let itemView = dockItemView(under: touch, in: touchBarWindow.contentView) {
                switch touch.phase {
                case .began:
                    startLongPressTimer(for: itemView)
                case .ended, .cancelled:
                    endLongPress()
                default:
                    break
                }
            }
        }else {
            return
        }
    }

    private func startLongPressTimer(for itemView: DockItemView) {
        endLongPress()
        longPressItemView = itemView
        itemView.touchInProgress    = true
        itemView.longPressMenuShown = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + DockWidget.longPressDelay)
        timer.setEventHandler(handler: { [weak self, weak itemView] in
            guard let self = self, let itemView = itemView, itemView.superview != nil, let item = itemView.dockItem else { return }
            itemView.longPressMenuShown = true
            self.pendingLaunch = nil
            DockMenuHelper.showMenu(for: item)
        })
        longPressTimer = timer
        timer.resume()
    }

    private func endLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
        if let itemView = longPressItemView {
            itemView.touchInProgress = false
            /// If the selection arrived while the finger was down (launch was
            /// deferred), launch it now — unless the menu was just shown.
            if !itemView.longPressMenuShown {
                launchPendingItem()
            }
        }
        longPressItemView = nil
    }

    private func dockItemView(under touch: NSTouch, in container: NSView?) -> DockItemView? {
        for (_, itemView) in cachedItemViews {
            guard itemView.superview != nil, container == nil || itemView.isDescendant(of: container!) else { continue }
            let location = touch.location(in: itemView)
            if itemView.bounds.contains(location) {
                return itemView
            }
        }
        return nil
    }

    // MARK: Long-press (Touch Bar touch observer)

    /// Attach the passive long-press observer to a scrubber.
    private func attachLongPressObserver(to scrubber: NSScrubber) {
        let observer = DockLongPressObserver(target: nil, action: nil)
        observer.delegate = self
        observer.onBegan = { [weak self] touch in
            guard let self = self, Defaults[.dockContextMenuEnabled] else { return }
            if let itemView = self.dockItemView(under: touch, in: scrubber) {
                self.startLongPressTimer(for: itemView)
            }
        }
        observer.onEnded = { [weak self] in
            self?.endLongPress()
        }
        scrubber.addGestureRecognizer(observer)
        longPressObservers.append(observer)
    }

    func scrubber(_ scrubber: NSScrubber, didChangeVisibleRange visibleRange: NSRange) {
        lastVisibleRange = visibleRange
    }

}

extension DockWidget: NSGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        /// observe only — never interfere with the scrubber's own recognizers
        return true
    }
}

// MARK: - Mouse support
extension DockWidget: PKScreenEdgeMouseDelegate {

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {
        /// nothing to do here — the cursor is displayed by the main controller.
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {
        /// nothing to do here — the cursor is displayed by the main controller.
    }

    func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {
        /// nothing to do here — the cursor is displayed by the main controller.
    }

    /// Mouse click: launch the dock item under the cursor.
    func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
        guard let (scrubber, item) = dockItem(at: location, in: view) else {
            return
        }
        launch(item: item)
        scrubber.selectedIndex = -1
    }

    /// Mouse right-click: show the authentic Dock context menu for the item under the cursor.
    func screenEdgeController(_ controller: PKScreenEdgeController, mouseRightClickAtLocation location: NSPoint, in view: NSView) {
        guard let (_, item) = dockItem(at: location, in: view) else {
            return
        }
        DockMenuHelper.showMenu(for: item)
    }

    /// Mouse scroll: scroll the dock scrubber.
    func screenEdgeController(_ controller: PKScreenEdgeController, mouseScrollWithDelta delta: CGFloat, atLocation location: NSPoint, in view: NSView) {
        guard dockScrubber.numberOfItems > 0 else { return }
        scrollAccumulator += delta
        let steps = Int(scrollAccumulator)
        guard steps != 0 else { return }
        scrollAccumulator -= CGFloat(steps)
        var index = lastVisibleRange.location
        index = steps > 0 ? index - steps : index + abs(steps)
        index = max(0, min(dockScrubber.numberOfItems - 1, index))
        /// `.leading` always performs a real scroll (an item already visible
        /// with `.none` would be a no-op, which made the scroll feel stuck).
        dockScrubber.scrollItem(at: index, to: .leading)
    }

    /// Drag & drop: open the dragged file with the app under the cursor.
    func screenEdgeController(_ controller: PKScreenEdgeController, performDragOperation info: NSDraggingInfo, filepath: String, in view: NSView) -> Bool {
        guard let (_, item) = dockItem(at: info.draggingLocation, in: view), let path = item.path else {
            return false
        }
        if #available(macOS 10.15, *) {
            NSWorkspace.shared.open([URL(fileURLWithPath: filepath)], withApplicationAt: path, configuration: NSWorkspace.OpenConfiguration())
        }else {
            NSWorkspace.shared.openFile(filepath, withApplication: path.path)
        }
        return true
    }

    /// Finds the dock item whose icon view is under the given location
    /// (in the Touch Bar view coordinates), using the real view hierarchy.
    private func dockItem(at location: NSPoint, in view: NSView) -> (NSScrubber, DockItem)? {
        guard let hit = view.hitTest(location) else {
            return nil
        }
        var current: NSView? = hit
        while let itemView = current {
            if let dockItemView = itemView as? DockItemView, let item = dockItemView.dockItem {
                if persistentItems.contains(where: { $0.diffId == item.diffId }) {
                    return (persistentScrubber, item)
                }
                return (dockScrubber, item)
            }
            current = itemView.superview
        }
        return nil
    }

    private var scrollAccumulator: CGFloat {
        get { return DockWidgetScrollAccumulator.value }
        set { DockWidgetScrollAccumulator.value = newValue }
    }

}

/// Storage for the scroll accumulator (extensions can't add stored properties).
private final class DockWidgetScrollAccumulator {
    static var value: CGFloat = 0
}

// MARK: - Authentic Dock context menu
final class DockMenuHelper {

    /// Shows the authentic Dock context menu for the given dock item by
    /// performing the accessibility `AXShowMenu` action on the matching real
    /// Dock icon. The menu then appears at the bottom of the screen, above the
    /// real icon — exactly as a right-click on the Dock would.
    ///
    /// - parameter item: The dock item to show the context menu for.
    /// - returns: `true` when the menu was shown.
    @discardableResult
    static func showMenu(for item: DockItem) -> Bool {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return false
        }
        let appElement = AXUIElementCreateApplication(dock.processIdentifier)
        for dockItem in DockMenuHelper.dockItemElements(in: appElement) {
            guard let title = DockMenuHelper.string(dockItem, "AXTitle"),
                  DockMenuHelper.string(dockItem, "AXSubrole") == "AXApplicationDockItem",
                  DockMenuHelper.matches(item: item, axTitle: title) else {
                continue
            }
            return AXUIElementPerformAction(dockItem, "AXShowMenu" as CFString) == .success
        }
        NSLog("[Pock][DockMenu] No matching AX dock item found for '%@'.", item.name ?? "?")
        return false
    }

    // MARK: Private

    private static func dockItemElements(in appElement: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for child in children(of: appElement) {
            if string(child, "AXRole") == "AXDockItem" {
                result.append(child)
            }
            result.append(contentsOf: dockItemElements(in: child))
        }
        return result
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success, let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Matches a Touch Bar dock item against a real Dock icon.
    /// Note: `AXURL` is no longer exposed by the Dock on macOS 27, so matching
    /// relies on localized names. Names are compared with spaces and case
    /// ignored: the Dock's AXTitle comes from the `file-label` (e.g.
    /// "ExpressInvoice") which may differ from the localized name
    /// ("Express Invoice").
    private static func matches(item: DockItem, axTitle: String) -> Bool {
        // 1. Match by the localized name of the running application.
        if let bundleID = item.bundleIdentifier,
           let localizedName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName,
           matches(axTitle, localizedName) {
            return true
        }
        // 2. Match by the item name (file-label, matches the Dock's AXTitle).
        if let name = item.name, matches(axTitle, name) {
            return true
        }
        // 3. Match by the localized name of the app bundle (for not-running apps
        // whose file-label differs from the current localized name).
        if let bundleID = item.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: appURL),
           let displayName = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String),
           matches(axTitle, displayName) {
            return true
        }
        return false
    }

    /// Case- and space-insensitive name comparison.
    private static func matches(_ axTitle: String, _ name: String) -> Bool {
        return axTitle.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(name.replacingOccurrences(of: " ", with: "")) == .orderedSame
    }

}
