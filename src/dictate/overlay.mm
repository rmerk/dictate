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

    if (_state == rcli::OverlayState::Recording) {
        [self drawMicInRect:bounds];
    } else {
        [self drawSpinnerInRect:bounds];
    }
}

- (void)drawMicInRect:(NSRect)bounds {
    // Pulsing alpha based on animation phase
    CGFloat alpha = 0.5 + 0.5 * sin(_animationPhase * M_PI * 2.0);

    NSImage *micImage = [NSImage imageWithSystemSymbolName:@"mic.fill"
                                 accessibilityDescription:@"Recording"];
    if (micImage) {
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:22
                                                            weight:NSFontWeightMedium
                                                             scale:NSImageSymbolScaleLarge];
        micImage = [micImage imageWithSymbolConfiguration:config];

        [[NSColor colorWithWhite:1.0 alpha:alpha] set];

        CGFloat imgSize = 24.0;
        NSRect imgRect = NSMakeRect((bounds.size.width - imgSize) / 2.0,
                                    (bounds.size.height - imgSize) / 2.0,
                                    imgSize, imgSize);

        [micImage drawInRect:imgRect
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:alpha
              respectFlipped:YES
                       hints:nil];
    } else {
        // Fallback: draw a simple circle as mic placeholder
        [[NSColor colorWithWhite:1.0 alpha:alpha] set];
        NSRect circle = NSInsetRect(bounds, 14, 14);
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:circle];
        [path fill];
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
    [[NSColor colorWithWhite:1.0 alpha:0.9] set];
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
    }

    const CGFloat size = 48.0;
    NSRect frame = NSMakeRect(0, 0, size, size);

    g_overlayWindow = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

    [g_overlayWindow setLevel:NSStatusWindowLevel];
    [g_overlayWindow setOpaque:NO];
    [g_overlayWindow setBackgroundColor:[NSColor colorWithWhite:0.1 alpha:0.85]];
    [g_overlayWindow setHasShadow:YES];
    [g_overlayWindow setIgnoresMouseEvents:YES];
    [g_overlayWindow setCollectionBehavior:
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary];

    // Round corners
    g_overlayWindow.contentView.wantsLayer = YES;
    g_overlayWindow.contentView.layer.cornerRadius = size / 2.0;
    g_overlayWindow.contentView.layer.masksToBounds = YES;

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
        CGFloat y = screenHeight - position->y - 48.0;
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
