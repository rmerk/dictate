#pragma once
#include <functional>
#include <string>

namespace rcli {

using HotkeyCallback = std::function<void()>;

// Start listening for a global hotkey.
// hotkey_str: e.g., "cmd+j", "cmd+shift+d"
// Returns true if event tap registered successfully.
// Returns false if Accessibility permission not granted.
bool hotkey_start(const std::string& hotkey_str, HotkeyCallback callback);

// Stop listening and release the event tap.
void hotkey_stop();

// Set whether the hotkey is "active" (i.e., recording in progress).
// When active, bare Enter also triggers the callback to stop recording.
void hotkey_set_active(bool active);

// Check if Accessibility permission is granted.
bool hotkey_check_accessibility();

// Prompt the system to pre-register this binary for Accessibility permission.
// Opens System Settings to the Accessibility pane. Non-blocking.
void hotkey_request_accessibility();

// Block until Accessibility permission is granted or timeout (seconds) elapses.
// Prints progress to stderr. Returns true if granted.
bool hotkey_wait_for_accessibility(int timeout_secs);

} // namespace rcli
