import Foundation
import Observation
import CoreGraphics
import Carbon
import CRCLIEngine

@MainActor
@Observable
final class HotkeyService {
    var isListening: Bool = false
    var isRecording: Bool = false
    var isCommandRecording: Bool = false
    var hotkeyString: String = "cmd+j"
    var commandHotkeyString: String = "cmd+shift+j"
    /// Set to true when the user explicitly stops the listener via the toggle,
    /// preventing the accessibility observer from auto-restarting it.
    var userDisabled: Bool = false

    var onHotkeyPressed: (() -> Void)?
    var onCommandHotkeyPressed: (() -> Void)?

    // Swift-native CGEventTap for the command hotkey (C API supports only one tap)
    private var commandEventTap: CFMachPort?
    private var commandRunLoopSource: CFRunLoopSource?
    // Strongly owned context — lifetime tied to the tap; use passUnretained for the C pointer.
    private var commandTapContext: CommandTapContext?

    /// True while either hotkey is actively capturing audio.
    var isCapturing: Bool { isRecording || isCommandRecording }

    init() {
        if let saved = ConfigService.shared.read(key: "hotkey"), !saved.isEmpty {
            hotkeyString = saved
        }
        if let saved = ConfigService.shared.read(key: "command_hotkey"), !saved.isEmpty {
            commandHotkeyString = saved
        }
    }

    func start() -> Bool {
        // Stop any existing listener before registering a new one to prevent
        // multiple CGEventTaps from being registered simultaneously.
        if isListening { stop() }
        userDisabled = false
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let result = rcli_hotkey_start(hotkeyString, Self.hotkeyTrampoline, ptr)
        isListening = (result != 0)

        // Register command hotkey via a separate Swift CGEventTap
        if isListening && !commandHotkeyString.isEmpty {
            startCommandTap()
        }

        return isListening
    }

    func stop() {
        stopInternal()
        userDisabled = true
    }

    private func stopInternal() {
        stopCommandTap()
        rcli_hotkey_stop()
        isListening = false
        isRecording = false
        isCommandRecording = false
    }

    func restart(with newHotkey: String) -> Bool {
        let wasListening = isListening
        stopInternal()
        hotkeyString = newHotkey
        do {
            try ConfigService.shared.write(key: "hotkey", value: newHotkey)
        } catch {
            print("[HotkeyService] Failed to persist hotkey: \(error)")
        }
        return wasListening ? start() : false
    }

    func restartCommandHotkey(with newHotkey: String) -> Bool {
        let wasListening = isListening
        commandHotkeyString = newHotkey
        do {
            try ConfigService.shared.write(key: "command_hotkey", value: newHotkey)
        } catch {
            print("[HotkeyService] Failed to persist command hotkey: \(error)")
        }
        if wasListening {
            stopInternal()
            return start()
        }
        return false
    }

    func setRecording(_ active: Bool) {
        isRecording = active
        rcli_hotkey_set_active(active ? 1 : 0)
    }

    func setCommandRecording(_ active: Bool) {
        isCommandRecording = active
        // Do NOT touch rcli_hotkey_set_active here — that flag belongs to the
        // C dictation tap's Enter-to-stop logic. Command recording is managed
        // purely in Swift via isCommandRecording.
    }

    static func checkAccessibility() -> Bool {
        rcli_hotkey_check_accessibility() != 0
    }

    // MARK: - Swift CGEventTap for command hotkey

    private func startCommandTap() {
        guard let parsed = Self.parseHotkeyString(commandHotkeyString) else { return }

        // HotkeyService owns the context strongly; use passUnretained so the
        // C callback can read it without a +1 that would never be balanced.
        let ctx = CommandTapContext(service: self)
        ctx.targetKeyCode = parsed.keyCode
        ctx.targetModifiers = parsed.modifiers
        commandTapContext = ctx  // keeps ctx alive for the tap's lifetime

        let ctxPtr = Unmanaged.passUnretained(ctx).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let ctx = Unmanaged<CommandTapContext>.fromOpaque(userInfo).takeUnretainedValue()

                // Re-enable if the system disabled the tap
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ctx.eventTapRef { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else { return Unmanaged.passRetained(event) }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                let modMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

                guard keyCode == ctx.targetKeyCode,
                      flags.intersection(modMask) == ctx.targetModifiers.intersection(modMask)
                else { return Unmanaged.passRetained(event) }

                Task { @MainActor in
                    ctx.service?.onCommandHotkeyPressed?()
                }
                return nil  // consume/swallow
            },
            userInfo: ctxPtr)

        guard let tap else {
            // Tap creation failed (accessibility denied); release strong ref.
            commandTapContext = nil
            return
        }

        ctx.eventTapRef = tap  // so the re-enable handler can reach it

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        commandEventTap = tap
        commandRunLoopSource = src
    }

    private func stopCommandTap() {
        if let tap = commandEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            commandEventTap = nil
        }
        if let src = commandRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            commandRunLoopSource = nil
        }
        commandTapContext = nil
    }

    // MARK: - Hotkey string parser
    // Parses "cmd+shift+j" style strings into a CGKeyCode + CGEventFlags pair.

    private struct ParsedHotkey {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags
    }

    private static func parseHotkeyString(_ str: String) -> ParsedHotkey? {
        let parts = str.lowercased().components(separatedBy: "+")
        var modifiers: CGEventFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.maskCommand)
            case "shift":          modifiers.insert(.maskShift)
            case "ctrl", "control":modifiers.insert(.maskControl)
            case "opt", "alt", "option": modifiers.insert(.maskAlternate)
            default: keyPart = part
            }
        }

        guard let key = keyPart, let keyCode = keyCodeForString(key) else { return nil }
        return ParsedHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyCodeForString(_ s: String) -> CGKeyCode? {
        // Map common letter/digit keys via Carbon TIS
        let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayoutPtr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        let char = s.unicodeScalars.first.map { Character($0) } ?? Character(s)
        // Search keycodes 0...127 for the matching character
        for keyCode in CGKeyCode(0)...CGKeyCode(127) {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var charCount = 0
            let err = UCKeyTranslate(keyLayoutPtr, keyCode, UInt16(kUCKeyActionDisplay),
                                     0, UInt32(LMGetKbdType()),
                                     OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                     &deadKeyState, 4, &charCount, &chars)
            if err == noErr, charCount > 0 {
                let result = String(utf16CodeUnits: chars, count: charCount).lowercased()
                if result == String(char).lowercased() { return keyCode }
            }
        }
        return nil
    }

    // MARK: - Trampolines

    private static let hotkeyTrampoline: RCLIHotkeyCallback = { userData in
        guard let userData else { return }
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            service.onHotkeyPressed?()
        }
    }
}

// MARK: - Command tap context (heap object so C callback can reach it)

// Must only be accessed on the main thread (tap registered on CFRunLoopGetMain()).
private final class CommandTapContext {
    weak var service: HotkeyService?
    var targetKeyCode: CGKeyCode = 0
    var targetModifiers: CGEventFlags = []
    var eventTapRef: CFMachPort?

    init(service: HotkeyService) {
        self.service = service
    }
}


