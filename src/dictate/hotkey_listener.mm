#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>

#include "dictate/hotkey_listener.h"
#include <algorithm>
#include <mutex>
#include <sstream>
#include <unordered_map>

namespace rcli {

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

static CFMachPortRef       g_event_tap   = nullptr;
static CFRunLoopSourceRef  g_run_loop_src = nullptr;
static CGKeyCode           g_target_keycode  = 0;
static CGEventFlags        g_target_flags    = 0;
static HotkeyCallback      g_callback;
static std::mutex          g_mutex;
static bool                g_active = false; // true when recording

// ---------------------------------------------------------------------------
// Key-name → CGKeyCode mapping
// ---------------------------------------------------------------------------

static const std::unordered_map<std::string, CGKeyCode>& key_map() {
    static const std::unordered_map<std::string, CGKeyCode> m = {
        {"a", kVK_ANSI_A}, {"b", kVK_ANSI_B}, {"c", kVK_ANSI_C},
        {"d", kVK_ANSI_D}, {"e", kVK_ANSI_E}, {"f", kVK_ANSI_F},
        {"g", kVK_ANSI_G}, {"h", kVK_ANSI_H}, {"i", kVK_ANSI_I},
        {"j", kVK_ANSI_J}, {"k", kVK_ANSI_K}, {"l", kVK_ANSI_L},
        {"m", kVK_ANSI_M}, {"n", kVK_ANSI_N}, {"o", kVK_ANSI_O},
        {"p", kVK_ANSI_P}, {"q", kVK_ANSI_Q}, {"r", kVK_ANSI_R},
        {"s", kVK_ANSI_S}, {"t", kVK_ANSI_T}, {"u", kVK_ANSI_U},
        {"v", kVK_ANSI_V}, {"w", kVK_ANSI_W}, {"x", kVK_ANSI_X},
        {"y", kVK_ANSI_Y}, {"z", kVK_ANSI_Z},
        {"0", kVK_ANSI_0}, {"1", kVK_ANSI_1}, {"2", kVK_ANSI_2},
        {"3", kVK_ANSI_3}, {"4", kVK_ANSI_4}, {"5", kVK_ANSI_5},
        {"6", kVK_ANSI_6}, {"7", kVK_ANSI_7}, {"8", kVK_ANSI_8},
        {"9", kVK_ANSI_9},
        {"space",  kVK_Space},
        {"return", kVK_Return}, {"enter", kVK_Return},
        {"tab",    kVK_Tab},
        {"escape", kVK_Escape}, {"esc", kVK_Escape},
        {"delete", kVK_Delete}, {"backspace", kVK_Delete},
        {"f1",  kVK_F1},  {"f2",  kVK_F2},  {"f3",  kVK_F3},
        {"f4",  kVK_F4},  {"f5",  kVK_F5},  {"f6",  kVK_F6},
        {"f7",  kVK_F7},  {"f8",  kVK_F8},  {"f9",  kVK_F9},
        {"f10", kVK_F10}, {"f11", kVK_F11}, {"f12", kVK_F12},
    };
    return m;
}

// ---------------------------------------------------------------------------
// Parse hotkey string  (e.g. "cmd+shift+j")
// ---------------------------------------------------------------------------

static bool parse_hotkey(const std::string& hotkey_str,
                         CGKeyCode& out_keycode,
                         CGEventFlags& out_flags) {
    out_flags = 0;
    out_keycode = 0;

    // Tokenise on '+'
    std::vector<std::string> parts;
    std::istringstream ss(hotkey_str);
    std::string token;
    while (std::getline(ss, token, '+')) {
        // Trim whitespace and lowercase
        auto start = token.find_first_not_of(" \t");
        auto end   = token.find_last_not_of(" \t");
        if (start == std::string::npos) continue;
        token = token.substr(start, end - start + 1);
        std::transform(token.begin(), token.end(), token.begin(), ::tolower);
        parts.push_back(token);
    }

    if (parts.empty()) return false;

    bool found_key = false;
    for (const auto& p : parts) {
        if (p == "cmd" || p == "command" || p == "meta") {
            out_flags |= kCGEventFlagMaskCommand;
        } else if (p == "shift") {
            out_flags |= kCGEventFlagMaskShift;
        } else if (p == "ctrl" || p == "control") {
            out_flags |= kCGEventFlagMaskControl;
        } else if (p == "alt" || p == "option" || p == "opt") {
            out_flags |= kCGEventFlagMaskAlternate;
        } else {
            // Must be the key itself
            auto it = key_map().find(p);
            if (it == key_map().end()) return false;
            out_keycode = it->second;
            found_key = true;
        }
    }

    return found_key;
}

// ---------------------------------------------------------------------------
// CGEvent tap callback
// ---------------------------------------------------------------------------

static CGEventRef event_tap_callback(CGEventTapProxy /*proxy*/,
                                     CGEventType type,
                                     CGEventRef event,
                                     void* /*userInfo*/) {
    // If the tap is disabled by the system, re-enable it.
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (g_event_tap) {
            CGEventTapEnable(g_event_tap, true);
        }
        return event;
    }

    if (type != kCGEventKeyDown) return event;

    CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(
        event, kCGKeyboardEventKeycode);
    CGEventFlags flags = CGEventGetFlags(event);

    // Mask to only the modifier bits we care about
    const CGEventFlags mod_mask =
        kCGEventFlagMaskCommand | kCGEventFlagMaskShift |
        kCGEventFlagMaskControl | kCGEventFlagMaskAlternate;

    bool is_hotkey = (keycode == g_target_keycode &&
                      (flags & mod_mask) == g_target_flags);

    // Bare Enter (no modifiers) also stops recording when active
    bool is_enter_stop = false;
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        is_enter_stop = g_active && keycode == kVK_Return && (flags & mod_mask) == 0;
    }

    if (is_hotkey || is_enter_stop) {
        HotkeyCallback cb;
        {
            std::lock_guard<std::mutex> lk(g_mutex);
            cb = g_callback;
        }
        if (cb) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cb();
            });
        }
        return NULL; // Consume the event
    }

    return event; // Pass through
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

bool hotkey_start(const std::string& hotkey_str, HotkeyCallback callback) {
    hotkey_stop(); // Clean up any previous tap

    CGKeyCode keycode = 0;
    CGEventFlags flags = 0;
    if (!parse_hotkey(hotkey_str, keycode, flags)) return false;

    {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_target_keycode = keycode;
        g_target_flags   = flags;
        g_callback       = std::move(callback);
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);

    g_event_tap = CGEventTapCreate(
        kCGHIDEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,  // Active tap — can consume events
        mask,
        event_tap_callback,
        nullptr);

    // CGEventTapCreate is the ground truth for accessibility permission —
    // AXIsProcessTrusted() is unreliable for unsigned/dev builds.
    if (!g_event_tap) return false;

    g_run_loop_src = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, g_event_tap, 0);

    if (!g_run_loop_src) {
        CFRelease(g_event_tap);
        g_event_tap = nullptr;
        return false;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       g_run_loop_src,
                       kCFRunLoopCommonModes);

    CGEventTapEnable(g_event_tap, true);
    return true;
}

void hotkey_set_active(bool active) {
    std::lock_guard<std::mutex> lk(g_mutex);
    g_active = active;
}

void hotkey_stop() {
    if (g_run_loop_src) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              g_run_loop_src,
                              kCFRunLoopCommonModes);
        CFRelease(g_run_loop_src);
        g_run_loop_src = nullptr;
    }
    if (g_event_tap) {
        CGEventTapEnable(g_event_tap, false);
        CFRelease(g_event_tap);
        g_event_tap = nullptr;
    }
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_callback = nullptr;
    }
}

bool hotkey_check_accessibility() {
    return AXIsProcessTrusted();
}

void hotkey_request_accessibility() {
    @autoreleasepool {
        // Open System Settings directly to the Accessibility pane.
        // We avoid AXIsProcessTrustedWithOptions(prompt: YES) because it tries to
        // display a modal dialog, which blocks indefinitely in non-GUI contexts
        // (e.g. LaunchAgent, background shell).
        NSURL* url = [NSURL URLWithString:
            @"x-apple.systempreferences:"
            @"com.apple.preference.security?Privacy_Accessibility"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

bool hotkey_wait_for_accessibility(int timeout_secs) {
    for (int i = 0; i < timeout_secs; ++i) {
        if (AXIsProcessTrusted()) return true;
        if (i % 5 == 0 && i > 0) {
            fprintf(stderr, "  Still waiting for Accessibility permission... (%ds)\n", i);
        }
        sleep(1);
    }
    return AXIsProcessTrusted();
}

} // namespace rcli
