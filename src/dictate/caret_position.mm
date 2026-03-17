#include "caret_position.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

namespace rcli {

std::optional<ScreenPoint> get_caret_screen_position() {
    // Get the frontmost application
    NSRunningApplication* frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!frontApp) return std::nullopt;

    pid_t pid = frontApp.processIdentifier;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return std::nullopt;

    // Get the focused UI element
    AXUIElementRef focused = nullptr;
    AXError err = AXUIElementCopyAttributeValue(
        app, kAXFocusedUIElementAttribute, (CFTypeRef*)&focused);
    CFRelease(app);
    if (err != kAXErrorSuccess || !focused) return std::nullopt;

    // Get the selected text range
    CFTypeRef range = nullptr;
    err = AXUIElementCopyAttributeValue(
        focused, kAXSelectedTextRangeAttribute, &range);
    if (err != kAXErrorSuccess || !range) {
        CFRelease(focused);
        return std::nullopt;
    }

    // Get the bounds for the selected text range
    CFTypeRef bounds = nullptr;
    err = AXUIElementCopyParameterizedAttributeValue(
        focused, kAXBoundsForRangeParameterizedAttribute, range, &bounds);
    CFRelease(range);
    CFRelease(focused);
    if (err != kAXErrorSuccess || !bounds) return std::nullopt;

    // Extract the CGRect from the AXValue
    CGRect rect;
    if (!AXValueGetValue((AXValueRef)bounds, (AXValueType)kAXValueCGRectType, &rect)) {
        CFRelease(bounds);
        return std::nullopt;
    }
    CFRelease(bounds);

    // Return the position at the end of the selection (right edge, top)
    return ScreenPoint{rect.origin.x + rect.size.width, rect.origin.y};
}

} // namespace rcli
