#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*RCLIHotkeyCallback)(void* user_data);

// Start listening for a global hotkey (e.g., "cmd+j").
// Returns 1 on success, 0 on failure (Accessibility not granted).
int rcli_hotkey_start(const char* hotkey_str, RCLIHotkeyCallback callback, void* user_data);

// Stop listening and release the event tap.
void rcli_hotkey_stop(void);

// Set whether the hotkey is "active" (recording in progress).
// When active, bare Enter also triggers the callback.
void rcli_hotkey_set_active(int active);

// Check if Accessibility permission is granted. Returns 1 if yes.
int rcli_hotkey_check_accessibility(void);

#ifdef __cplusplus
}
#endif
