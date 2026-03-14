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

// Check if Accessibility permission is granted.
bool hotkey_check_accessibility();

// Prompt the user to grant Accessibility permission with a friendly dialog.
void hotkey_request_accessibility();

} // namespace rcli
