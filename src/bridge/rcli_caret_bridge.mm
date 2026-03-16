#include "bridge/rcli_caret_bridge.h"
#include "dictate/caret_position.h"

extern "C" {

int rcli_get_caret_position(double* out_x, double* out_y) {
    if (!out_x || !out_y) return -1;
    auto pos = rcli::get_caret_screen_position();
    if (!pos) return -1;
    *out_x = pos->x;
    *out_y = pos->y;
    return 0;
}

} // extern "C"
