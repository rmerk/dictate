#include "dictate/paste_engine.h"

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <ApplicationServices/ApplicationServices.h>

#include <unistd.h>
#include <atomic>
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

namespace {

std::atomic<bool> g_notification_authorized{false};
std::atomic<bool> g_notification_checked{false};

void request_notification_auth() {
    if (g_notification_checked.load()) return;
    g_notification_checked.store(true);

    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                         completionHandler:^(BOOL granted, NSError* _Nullable error) {
        g_notification_authorized.store(granted);
        if (error) {
            // Authorization failed; fallback will be used
        }
    }];
}

} // anonymous namespace

void send_notification(const std::string& title, const std::string& body) {
    @autoreleasepool {
        request_notification_auth();

        // Give a brief moment for authorization callback on first call
        if (!g_notification_authorized.load()) {
            usleep(100000); // 100ms for auth callback
        }

        if (g_notification_authorized.load()) {
            UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
            UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
            content.title = [NSString stringWithUTF8String:title.c_str()];
            content.body  = [NSString stringWithUTF8String:body.c_str()];

            NSString* identifier = [[NSUUID UUID] UUIDString];
            UNNotificationRequest* request =
                [UNNotificationRequest requestWithIdentifier:identifier
                                                     content:content
                                                     trigger:nil];
            [center addNotificationRequest:request withCompletionHandler:nil];
        } else {
            // Fallback: NSAppleScript (avoids shell injection from transcript text)
            NSString *script = [NSString stringWithFormat:
                @"display notification %@ with title %@",
                [NSString stringWithFormat:@"\"%@\"",
                    [[NSString stringWithUTF8String:body.c_str()]
                        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]],
                [NSString stringWithFormat:@"\"%@\"",
                    [[NSString stringWithUTF8String:title.c_str()]
                        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
            NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
            [appleScript executeAndReturnError:nil];
        }
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
