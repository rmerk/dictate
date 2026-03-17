#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Get the screen position of the text caret in the focused app.
// Writes to out_x and out_y. Returns 0 on success, -1 if unavailable.
int rcli_get_caret_position(double* out_x, double* out_y);

#ifdef __cplusplus
}
#endif
