@preconcurrency import Foundation
@preconcurrency import CoreGraphics
import Carbon.HIToolbox

// A single hotkey binding
struct HotKeyBinding {
    let id: String
    var modifiers: CGEventFlags
    var keyCode: CGKeyCode
    var rightCommandOnly: Bool
    let callback: @MainActor () -> Void
}

// Shared context for the C callback
private final class _TapContext: @unchecked Sendable {
    nonisolated(unsafe) static var shared: _TapContext?

    var bindings: [HotKeyBinding] = []
    // Tracked via .flagsChanged events — reliable right-command state
    var rightCommandDown: Bool = false

    nonisolated(unsafe) var tapRef: CFMachPort?
}

// kVK_RightCommand = 54
private let kRightCommandKeyCode: CGKeyCode = 54

/// Manages global hotkey registration using CGEvent tap.
/// Supports multiple key bindings in a single tap.
/// Requires Input Monitoring permission.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var runLoopSource: CFRunLoopSource?
    private var context: _TapContext?

    private init() {}

    /// Register a hotkey binding. Starts the tap automatically if needed.
    @discardableResult
    func register(
        id: String,
        modifiers: CGEventFlags,
        keyCode: CGKeyCode,
        rightCommandOnly: Bool,
        callback: @escaping @MainActor () -> Void
    ) -> Bool {
        // Remove existing binding with same id
        context?.bindings.removeAll { $0.id == id }

        let binding = HotKeyBinding(
            id: id,
            modifiers: modifiers,
            keyCode: keyCode,
            rightCommandOnly: rightCommandOnly,
            callback: callback
        )

        if let ctx = context {
            ctx.bindings.append(binding)
            return true
        }

        // First registration — create the tap
        let ctx = _TapContext()
        ctx.bindings.append(binding)
        self.context = ctx
        _TapContext.shared = ctx

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                guard let ctx = _TapContext.shared else {
                    return Unmanaged.passRetained(event)
                }

                // Track right-command key state via flagsChanged events
                if type == .flagsChanged {
                    let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    if kc == kRightCommandKeyCode {
                        ctx.rightCommandDown = event.flags.contains(.maskCommand)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }

                let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                // Check each binding
                for binding in ctx.bindings {
                    if binding.rightCommandOnly && !ctx.rightCommandDown {
                        continue
                    }

                    let req = binding.modifiers
                    let ok = (eventKeyCode == binding.keyCode)
                        && (req.contains(.maskControl) == flags.contains(.maskControl))
                        && (req.contains(.maskAlternate) == flags.contains(.maskAlternate))
                        && (req.contains(.maskCommand) == flags.contains(.maskCommand))
                        && (req.contains(.maskShift) == flags.contains(.maskShift))

                    if ok {
                        let cb = binding.callback
                        DispatchQueue.main.async { cb() }
                        return nil // consume event
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            self.context = nil
            _TapContext.shared = nil
            return false
        }

        ctx.tapRef = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    /// Update an existing binding's key combination.
    func update(id: String, modifiers: CGEventFlags, keyCode: CGKeyCode, rightCommandOnly: Bool) {
        guard let ctx = context,
              let idx = ctx.bindings.firstIndex(where: { $0.id == id }) else { return }
        ctx.bindings[idx].modifiers = modifiers
        ctx.bindings[idx].keyCode = keyCode
        ctx.bindings[idx].rightCommandOnly = rightCommandOnly
    }

    /// Remove a binding by id.
    func unregister(id: String) {
        context?.bindings.removeAll { $0.id == id }
    }

    /// Stop the event tap and remove all bindings.
    func stop() {
        if let tap = context?.tapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        context = nil
        _TapContext.shared = nil
    }
}
