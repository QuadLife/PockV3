//
//  PKScreenEdgeController.swift
//  PockKit
//
//  Created by Pierluigi Galdi on 15/11/20.
//  Ported from PockKit (https://github.com/pock/pockkit) for Pock v3.
//

import Foundation
import AppKit

@objc public class PKScreenEdgeController: NSWindowController {

	/// ScreenEdgeWindow
	private class ScreenEdgeWindow: NSPanel {
		convenience init(color: NSColor?) {
			self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false, screen: NSScreen.main)
			collectionBehavior   	  = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
			isExcludedFromWindowsMenu = true
			isReleasedWhenClosed 	  = true
			ignoresMouseEvents   	  = false
			hidesOnDeactivate    	  = false
			canHide 		     	  = false
			level 				 	  = .mainMenu
			animationBehavior    	  = .none
			hasShadow  				  = false
			isOpaque   				  = false
			backgroundColor 		  = color ?? .clear
			alphaValue 				  = 1
			/// Setup view
			contentView?.wantsLayer = true
			contentView?.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
			contentView?.layer?.cornerRadius  = 6
			contentView?.layer?.masksToBounds = true
			/// Dragging support
			registerForDraggedTypes([.URL, .fileURL, .filePromise])
		}
	}

	/// Core
	private var trackingArea: NSTrackingArea?

	/// Delegates
	public private(set) weak var mouseDelegate: PKScreenEdgeMouseDelegate?
	public private(set)      var parentView: NSView!

	/// Data
	private var screenBottomEdgeRect: NSRect {
		return NSRect(x: 0, y: 0, width: parentView.visibleRect.width, height: 10)
	}

	/// Deinit
	deinit {
		tearDown(invalidate: true)
	}

	/// Initialiser
	public convenience init(mouseDelegate: PKScreenEdgeMouseDelegate?, parentView: NSView, barColor: NSColor? = nil) {
		/// Create tracking window
		let window = ScreenEdgeWindow(color: barColor)
		/// Create controller
		self.init(window: window)
		self.mouseDelegate = mouseDelegate
		self.parentView    = parentView
		/// Setup window
		window.orderFrontRegardless()
		window.delegate = self
		window.setFrame(screenBottomEdgeRect, display: true, animate: false)
		window.centerHorizontally()
		self.setupTrackingArea()
	}

	/// Tear down
	public func tearDown(invalidate: Bool = false) {
		if invalidate {
			mouseDelegate = nil
		}
		if let trackingArea = trackingArea {
			window?.contentView?.removeTrackingArea(trackingArea)
		}
		window?.close()
	}

	private func setupTrackingArea() {
		if let previousTrackingArea = trackingArea {
			window?.contentView?.removeTrackingArea(previousTrackingArea)
			trackingArea = nil
		}
		guard let window = window else {
			return
		}
		trackingArea = NSTrackingArea(rect: screenBottomEdgeRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
		window.contentView?.addTrackingArea(trackingArea!)
	}

}

// MARK: Mouse Delegate
extension PKScreenEdgeController: NSWindowDelegate {

	/// Mouse did enter in edge window
	override public func mouseEntered(with event: NSEvent) {
		guard let delegate = mouseDelegate, let point = window?.mouseLocationOutsideOfEventStream else {
			return
		}
		delegate.screenEdgeController(self, mouseEnteredAtLocation: point, in: parentView)
	}

	/// Did move mouse in edge window
	override public func mouseMoved(with event: NSEvent) {
		guard let delegate = mouseDelegate, let point = window?.mouseLocationOutsideOfEventStream else {
			return
		}
		delegate.screenEdgeController(self, mouseMovedAtLocation: point, in: parentView)
	}

	/// Did scroll mouse in edge window
	override public func scrollWheel(with event: NSEvent) {
		guard let delegate = mouseDelegate else {
			return
		}
		/// Forward the dominant axis: horizontal for the Dock, but a vertical
		/// two-finger scroll must work as well.
		let delta = abs(event.deltaX) >= abs(event.deltaY) ? event.deltaX : event.deltaY
		delegate.screenEdgeController?(self, mouseScrollWithDelta: delta, atLocation: event.locationInWindow, in: parentView)
	}

	/// Did click in edge window
	override public func mouseUp(with event: NSEvent) {
		guard let delegate = mouseDelegate else {
			return
		}
		delegate.screenEdgeController(self, mouseClickAtLocation: event.locationInWindow, in: parentView)
	}

	/// Did right-click in edge window
	override public func rightMouseUp(with event: NSEvent) {
		guard let delegate = mouseDelegate else {
			return
		}
		delegate.screenEdgeController?(self, mouseRightClickAtLocation: event.locationInWindow, in: parentView)
	}

	/// Mouse did exit from edge window
	override public func mouseExited(with event: NSEvent) {
		mouseDelegate?.screenEdgeController(self, mouseExitedAtLocation: event.locationInWindow, in: parentView)
	}

}

// MARK: Dragging Delegate
extension PKScreenEdgeController: NSDraggingDestination {

	public func wantsPeriodicDraggingUpdates() -> Bool {
		return false
	}

	public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard let delegate = mouseDelegate,
			  let pasteboard = sender.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray,
			  let path = pasteboard[0] as? String else {
			return NSDragOperation()
		}
		NSCursor.hide()
		return delegate.screenEdgeController?(self, draggingEntered: sender, filepath: path, in: parentView) ?? NSDragOperation()
	}

	public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard let delegate = mouseDelegate,
			  let pasteboard = sender.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray,
			  let path = pasteboard[0] as? String else {
			return NSDragOperation()
		}
		return delegate.screenEdgeController?(self, draggingUpdated: sender, filepath: path, in: parentView) ?? NSDragOperation()
	}

	public func draggingExited(_ sender: NSDraggingInfo?) {
		NSCursor.unhide()
		guard let delegate = mouseDelegate, let location = sender?.draggingLocation ?? window?.mouseLocationOutsideOfEventStream else {
			return
		}
		delegate.screenEdgeController(self, mouseExitedAtLocation: location, in: parentView)
	}

	public func draggingEnded(_ sender: NSDraggingInfo) {
		guard let delegate = mouseDelegate else {
			return
		}
		delegate.screenEdgeController?(self, draggingEnded: sender, in: parentView)
	}

	public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard let delegate = mouseDelegate,
			  let pasteboard = sender.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray,
			  let path = pasteboard[0] as? String else {
			return false
		}
		return delegate.screenEdgeController?(self, performDragOperation: sender, filepath: path, in: parentView) ?? false
	}

}

private extension NSWindow {
	func centerHorizontally() {
		if let screenSize = screen?.frame.size {
			self.setFrameOrigin(NSPoint(x: (screenSize.width - frame.size.width) / 2, y: frame.origin.y))
		}
	}
}