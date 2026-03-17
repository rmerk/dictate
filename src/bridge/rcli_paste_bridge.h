#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Copy text to clipboard and simulate Cmd+V paste.
// Returns 0 on success, -1 on failure.
int rcli_paste_text(const char* text);

// Send a macOS notification.
void rcli_send_notification(const char* title, const char* body);

#ifdef __cplusplus
}
#endif
