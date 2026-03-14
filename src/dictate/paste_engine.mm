#include "dictate/paste_engine.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

#include <unistd.h>
#include <string>

namespace rcli {

bool clipboard_copy(const std::string& text) {
    @autoreleasepool {
        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        if (!nsText) return false;
        return [pb setString:nsText forType:NSPasteboardTypeString];
    }
}

void simulate_paste() {
    @autoreleasepool {
        // Re-activate the previously frontmost app so Cmd+V goes to it,
        // not to our overlay's NSApplication
        NSRunningApplication* frontApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
        if (frontApp && ![frontApp isEqual:[NSRunningApplication currentApplication]]) {
            [frontApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            usleep(50000); // 50ms for app activation
        }
    }

    // Keycode 9 = V key
    CGEventRef keyDown = CGEventCreateKeyboardEvent(nullptr, 9, true);
    CGEventRef keyUp   = CGEventCreateKeyboardEvent(nullptr, 9, false);

    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp,   kCGEventFlagMaskCommand);

    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);

    CFRelease(keyDown);
    CFRelease(keyUp);
}

void send_notification(const std::string& title, const std::string& body) {
    @autoreleasepool {
        // CLI apps can't use UNUserNotificationCenter (no bundle proxy).
        // Use NSAppleScript which works for all processes.
        NSString *escapedBody = [[NSString stringWithUTF8String:body.c_str()]
            stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *escapedTitle = [[NSString stringWithUTF8String:title.c_str()]
            stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *script = [NSString stringWithFormat:
            @"display notification \"%@\" with title \"%@\"",
            escapedBody, escapedTitle];
        NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
        [appleScript executeAndReturnError:nil];
    }
}

void dictation_output(const std::string& transcript, bool paste, bool notification) {
    clipboard_copy(transcript);

    if (paste) {
        usleep(50000); // 50ms delay for pasteboard readiness
        simulate_paste();
    }

    if (notification) {
        send_notification("rcli Dictation", transcript);
    }
}

} // namespace rcli
