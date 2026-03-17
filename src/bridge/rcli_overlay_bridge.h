#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Overlay states matching rcli::OverlayState enum
#define RCLI_OVERLAY_RECORDING    0
#define RCLI_OVERLAY_TRANSCRIBING 1

void rcli_overlay_init(void);
void rcli_overlay_show(int state, double x, double y, int has_position);
void rcli_overlay_set_state(int state);
void rcli_overlay_dismiss(void);
void rcli_overlay_cleanup(void);

#ifdef __cplusplus
}
#endif
