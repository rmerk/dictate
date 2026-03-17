#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MIC_PERM_AUTHORIZED = 0,
    MIC_PERM_DENIED = 1,
    MIC_PERM_NOT_DETERMINED = 2,
    MIC_PERM_RESTRICTED = 3
} MicPermissionStatus;

MicPermissionStatus check_mic_permission(void);

// Blocks until the user responds to the macOS permission popup.
// Returns 1 if granted, 0 if denied.
int request_mic_permission(void);

// Non-blocking: request mic permission with a timeout (seconds).
// Returns 1 if granted, 0 if timed out or denied.
int request_mic_permission_timeout(int timeout_secs);

#ifdef __cplusplus
}
#endif
