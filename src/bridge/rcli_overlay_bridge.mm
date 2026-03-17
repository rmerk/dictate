#include "bridge/rcli_overlay_bridge.h"
#include "dictate/overlay.h"
#include <optional>

extern "C" {

void rcli_overlay_init(void) {
    rcli::overlay_init();
}

void rcli_overlay_show(int state, double x, double y, int has_position) {
    auto overlay_state = static_cast<rcli::OverlayState>(state);
    std::optional<rcli::ScreenPoint> pos;
    if (has_position) {
        pos = rcli::ScreenPoint{x, y};
    }
    rcli::overlay_show(overlay_state, pos);
}

void rcli_overlay_set_state(int state) {
    rcli::overlay_set_state(static_cast<rcli::OverlayState>(state));
}

void rcli_overlay_dismiss(void) {
    rcli::overlay_dismiss();
}

void rcli_overlay_cleanup(void) {
    rcli::overlay_cleanup();
}

} // extern "C"
