#pragma once
#include "caret_position.h"
#include <optional>

namespace rcli {

enum class OverlayState {
    Recording,    // Pulsing mic icon
    Transcribing, // Spinner
};

// Show the overlay at the given position (or top-right corner if nullopt).
void overlay_show(OverlayState state, std::optional<ScreenPoint> position);

// Update the overlay state (e.g., recording → transcribing).
void overlay_set_state(OverlayState state);

// Dismiss and hide the overlay.
void overlay_dismiss();

// Initialize overlay resources (call once from main thread).
void overlay_init();

// Cleanup overlay resources.
void overlay_cleanup();

} // namespace rcli
