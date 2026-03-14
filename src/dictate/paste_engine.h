#pragma once
#include <string>

namespace rcli {

// Copy text to system clipboard via NSPasteboard.
bool clipboard_copy(const std::string& text);

// Simulate Cmd+V paste into the active text field via CGEvent.
void simulate_paste();

// Send a macOS notification with the given title and body.
// Uses UNUserNotificationCenter, falls back to osascript.
void send_notification(const std::string& title, const std::string& body);

// Full dictation output pipeline: clipboard → paste → notify.
// Skips paste if paste=false. Skips notification if notification=false.
void dictation_output(const std::string& transcript, bool paste, bool notification);

} // namespace rcli
