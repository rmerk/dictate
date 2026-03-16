#include "dictate/overlay.h"
#import <AppKit/AppKit.h>

// -----------------------------------------------------------------------------
// OverlayView — custom NSView that draws mic icon or spinner
// -----------------------------------------------------------------------------

@interface OverlayView : NSView
@property (nonatomic, assign) rcli::OverlayState state;
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic, assign) CGFloat animationPhase;
@end

@implementation OverlayView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _state = rcli::OverlayState::Recording;
        _animationPhase = 0.0;
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)startAnimation {
    [self stopAnimation];
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                      target:self
                                                    selector:@selector(animationTick:)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)stopAnimation {
    [_animationTimer invalidate];
    _animationTimer = nil;
    _animationPhase = 0.0;
}

- (void)animationTick:(NSTimer *)timer {
    _animationPhase += 1.0 / 30.0;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;

    // Draw accent ring
    [self drawRingInRect:bounds];

    if (_state == rcli::OverlayState::Recording) {
        [self drawMicInRect:bounds];
    } else {
        [self drawSpinnerInRect:bounds];
    }
}

- (void)drawRingInRect:(NSRect)bounds {
    CGFloat ringWidth = 2.5;
    NSRect ringRect = NSInsetRect(bounds, ringWidth / 2.0, ringWidth / 2.0);
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:ringRect];
    [ring setLineWidth:ringWidth];

    if (_state == rcli::OverlayState::Recording) {
        // Pulsing red ring
        CGFloat pulse = 0.6 + 0.4 * sin(_animationPhase * M_PI * 2.0);
        [[NSColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:pulse] set];
    } else {
        // Steady blue ring
        [[NSColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.9] set];
    }
    [ring stroke];
}

- (void)drawMicInRect:(NSRect)bounds {
    NSImage *micImage = [NSImage imageWithSystemSymbolName:@"mic.fill"
                                 accessibilityDescription:@"Recording"];
    if (micImage) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:24
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleLarge];
        micImage = [micImage imageWithSymbolConfiguration:config];
        [micImage setTemplate:YES];

        CGFloat imgSize = 28.0;
        NSRect imgRect = NSMakeRect((bounds.size.width - imgSize) / 2.0,
                                    (bounds.size.height - imgSize) / 2.0,
                                    imgSize, imgSize);

        // Lock focus on a new image to draw tinted
        NSImage *tinted = [[NSImage alloc] initWithSize:NSMakeSize(imgSize, imgSize)];
        [tinted lockFocus];
        [[NSColor whiteColor] set];
        NSRect src = NSMakeRect(0, 0, imgSize, imgSize);
        [micImage drawInRect:src fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver fraction:1.0
              respectFlipped:YES hints:nil];
        NSRectFillUsingOperation(src, NSCompositingOperationSourceIn);
        [tinted unlockFocus];

        [tinted drawInRect:imgRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];
    }
}

- (void)drawSpinnerInRect:(NSRect)bounds {
    CGFloat cx = bounds.size.width / 2.0;
    CGFloat cy = bounds.size.height / 2.0;
    CGFloat radius = 14.0;
    CGFloat lineWidth = 3.0;

    // Rotating arc
    CGFloat startAngle = fmod(_animationPhase * 360.0, 360.0);
    CGFloat arcLength = 270.0;

    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy)
                                    radius:radius
                                startAngle:startAngle
                                  endAngle:startAngle + arcLength
                                 clockwise:NO];
    [arc setLineWidth:lineWidth];
    [arc setLineCapStyle:NSLineCapStyleRound];
    [[NSColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.9] set];
    [arc stroke];
}

@end

// -----------------------------------------------------------------------------
// Module-level state
// -----------------------------------------------------------------------------

namespace {
    NSWindow *g_overlayWindow = nil;
    OverlayView *g_overlayView = nil;
    bool g_initialized = false;
}

namespace rcli {

void overlay_init() {
    if (g_initialized) return;

    // Ensure NSApplication exists (needed for NSWindow even in CLI apps)
    if (NSApp == nil) {
        [NSApplication sharedApplication];
        // Accessory mode: no Dock icon, doesn't steal focus from frontmost app
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }

    const CGFloat size = 56.0;
    NSRect frame = NSMakeRect(0, 0, size, size);

    g_overlayWindow = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

    [g_overlayWindow setLevel:NSStatusWindowLevel];
    [g_overlayWindow setOpaque:NO];
    [g_overlayWindow setBackgroundColor:[NSColor clearColor]];
    [g_overlayWindow setHasShadow:YES];
    [g_overlayWindow setIgnoresMouseEvents:YES];
    [g_overlayWindow setCollectionBehavior:
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary];

    // Round corners
    g_overlayWindow.contentView.wantsLayer = YES;
    g_overlayWindow.contentView.layer.cornerRadius = size / 2.0;
    g_overlayWindow.contentView.layer.masksToBounds = YES;

    // Vibrancy effect (frosted glass)
    NSVisualEffectView *vibrancy = [[NSVisualEffectView alloc] initWithFrame:frame];
    vibrancy.material = NSVisualEffectMaterialHUDWindow;
    vibrancy.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vibrancy.state = NSVisualEffectStateActive;
    vibrancy.wantsLayer = YES;
    vibrancy.layer.cornerRadius = size / 2.0;
    vibrancy.layer.masksToBounds = YES;
    [g_overlayWindow.contentView addSubview:vibrancy];

    g_overlayView = [[OverlayView alloc] initWithFrame:frame];
    [g_overlayWindow.contentView addSubview:g_overlayView];

    g_initialized = true;
}

void overlay_show(OverlayState state, std::optional<ScreenPoint> position) {
    if (!g_initialized) return;

    g_overlayView.state = state;

    if (position.has_value()) {
        // Place near caret with offset.
        // AX coordinates use top-left origin; AppKit uses bottom-left origin.
        // Convert: cocoa_y = screen_height - ax_y - window_height
        CGFloat screenHeight = [NSScreen mainScreen].frame.size.height;
        CGFloat x = position->x + 8.0;
        CGFloat y = screenHeight - position->y - 56.0;
        [g_overlayWindow setFrameOrigin:NSMakePoint(x, y)];
    } else {
        // Top-right corner of main screen
        NSScreen *screen = [NSScreen mainScreen];
        if (screen) {
            NSRect screenFrame = screen.frame;
            CGFloat x = screenFrame.origin.x + screenFrame.size.width - 68.0;
            CGFloat y = screenFrame.origin.y + screenFrame.size.height - 68.0;
            [g_overlayWindow setFrameOrigin:NSMakePoint(x, y)];
        }
    }

    [g_overlayView startAnimation];
    [g_overlayWindow orderFront:nil];
}

void overlay_set_state(OverlayState state) {
    if (!g_initialized) return;

    g_overlayView.state = state;
    [g_overlayView stopAnimation];
    [g_overlayView startAnimation];
    [g_overlayView setNeedsDisplay:YES];
}

void overlay_dismiss() {
    if (!g_initialized) return;

    [g_overlayView stopAnimation];
    [g_overlayWindow orderOut:nil];
}

void overlay_cleanup() {
    if (!g_initialized) return;

    [g_overlayView stopAnimation];
    [g_overlayWindow orderOut:nil];
    g_overlayView = nil;
    g_overlayWindow = nil;
    g_initialized = false;
}

} // namespace rcli
