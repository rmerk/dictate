#pragma once
#include <optional>

namespace rcli {

struct ScreenPoint {
    double x;
    double y;
};

// Attempt to get the screen position of the text caret in the focused app.
// Returns nullopt if no text field is focused or the app doesn't expose caret position.
// Never shows an error — fails silently.
std::optional<ScreenPoint> get_caret_screen_position();

} // namespace rcli
