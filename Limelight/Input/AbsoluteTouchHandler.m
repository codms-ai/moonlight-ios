//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//
//  Display mode changes: the left button press is deferred briefly so a
//  two-finger gesture never starts with a stray click, two fingers scroll,
//  and a two-finger tap is a right click.
//

#import "AbsoluteTouchHandler.h"

#include <Limelight.h>

// How long to wait after a finger lands before pressing the left button.
// A second finger arriving inside this window turns the gesture into a scroll.
// A move or a lift ends the wait early, so taps and drags are not delayed.
#define PRESS_DELAY 0.060f

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.01f

// How long the double tap deadzone stays in effect between touch up and touch down
#define DOUBLE_TAP_DEAD_ZONE_DELAY 0.250f

// How far the finger can move before it can override the double tap deadzone
#define DOUBLE_TAP_DEAD_ZONE_DELTA 0.025f

// Two-finger tap: maximum duration and travel (fraction of the view) for a right click
#define TWO_FINGER_TAP_MAX_DURATION 0.300f
#define TWO_FINGER_TAP_MAX_DELTA 0.02f

// Wheel units per point of finger travel (120 units = one notch)
#define SCROLL_UNITS_PER_POINT 5.0f

@implementation AbsoluteTouchHandler {
    StreamView* view;

    NSTimer* pressTimer;
    NSTimer* longPressTimer;
    BOOL leftDown;

    CGPoint lastTouchDownLocation;
    NSTimeInterval lastTouchUpTime;
    CGPoint lastTouchUpLocation;

    // Multi-finger gesture state
    BOOL multiTouch;
    NSUInteger maxTouches;
    BOOL scrolled;
    NSTimeInterval multiStartTime;
    CGPoint multiStartCentroid;
    CGPoint lastCentroid;
    CGFloat scrollRemainderX;
    CGFloat scrollRemainderY;
}

- (id)initWithView:(StreamView*)view {
    self = [self init];
    self->view = view;
    lastTouchUpTime = -1;
    return self;
}

static NSArray<UITouch*>* activeTouches(UIEvent* event) {
    NSMutableArray* active = [NSMutableArray array];
    for (UITouch* touch in [event allTouches]) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            [active addObject:touch];
        }
    }
    return active;
}

- (CGPoint)centroidOf:(NSArray<UITouch*>*)touches {
    CGFloat x = 0, y = 0;
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:view];
        x += p.x;
        y += p.y;
    }
    NSUInteger n = MAX(touches.count, 1);
    return CGPointMake(x / n, y / n);
}

- (CGFloat)normalizedDistanceFrom:(CGPoint)a to:(CGPoint)b {
    return sqrt(pow((a.x - b.x) / view.bounds.size.width, 2) +
                pow((a.y - b.y) / view.bounds.size.height, 2));
}

- (void)cancelTimers {
    [pressTimer invalidate];
    pressTimer = nil;
    [longPressTimer invalidate];
    longPressTimer = nil;
}

- (void)pressLeft {
    [pressTimer invalidate];
    pressTimer = nil;
    if (leftDown) {
        return;
    }
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    leftDown = YES;

    // Start the long press timer (measured from touch down)
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY - PRESS_DELAY
                                                      target:self
                                                    selector:@selector(onLongPressStart:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)onPressTimer:(NSTimer*)timer {
    pressTimer = nil;
    [self pressLeft];
}

- (void)onLongPressStart:(NSTimer*)timer {
    longPressTimer = nil;
    // Raise the left click and start a right click
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
}

- (void)releaseButtons {
    [self cancelTimers];
    if (leftDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        // Raise right button too in case we triggered a long press gesture
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        leftDown = NO;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    NSArray<UITouch*>* active = activeTouches(event);

    if (active.count == 1 && !multiTouch) {
        UITouch* touch = [touches anyObject];
        CGPoint touchLocation = [touch locationInView:view];

        // Don't reposition for finger down events within the deadzone. This makes double-clicking easier.
        if (touch.timestamp - lastTouchUpTime > DOUBLE_TAP_DEAD_ZONE_DELAY ||
            [self normalizedDistanceFrom:touchLocation to:lastTouchUpLocation] > DOUBLE_TAP_DEAD_ZONE_DELTA) {
            [view updateCursorLocation:touchLocation isMouse:NO];
        }

        lastTouchDownLocation = touchLocation;
        maxTouches = 1;

        // Wait briefly in case a second finger follows
        [self cancelTimers];
        pressTimer = [NSTimer scheduledTimerWithTimeInterval:PRESS_DELAY
                                                      target:self
                                                    selector:@selector(onPressTimer:)
                                                    userInfo:nil
                                                     repeats:NO];
        return;
    }

    if (leftDown && !multiTouch) {
        // Already dragging with one finger: ignore extra fingers
        return;
    }

    // Two or more fingers: scroll / right click / keyboard gesture, never a left click
    [self cancelTimers];
    if (!multiTouch) {
        multiTouch = YES;
        scrolled = NO;
        multiStartTime = [[touches anyObject] timestamp];
        scrollRemainderX = scrollRemainderY = 0;
    }
    maxTouches = MAX(maxTouches, active.count);
    lastCentroid = [self centroidOf:active];
    multiStartCentroid = lastCentroid;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    NSArray<UITouch*>* active = activeTouches(event);

    if (multiTouch) {
        if (active.count != 2 || maxTouches != 2) {
            return;
        }
        CGPoint centroid = [self centroidOf:active];
        if ([self normalizedDistanceFrom:centroid to:multiStartCentroid] > TWO_FINGER_TAP_MAX_DELTA) {
            scrolled = YES;
        }

        // Natural scrolling: content follows the fingers
        scrollRemainderY += (centroid.y - lastCentroid.y) * SCROLL_UNITS_PER_POINT;
        scrollRemainderX += (centroid.x - lastCentroid.x) * SCROLL_UNITS_PER_POINT;
        lastCentroid = centroid;

        short dy = (short)scrollRemainderY;
        short dx = (short)scrollRemainderX;
        if (dy != 0) {
            LiSendHighResScrollEvent(dy);
            scrollRemainderY -= dy;
        }
        if (dx != 0) {
            LiSendHighResHScrollEvent(-dx);
            scrollRemainderX -= dx;
        }
        return;
    }

    if (active.count != 1) {
        return;
    }

    UITouch* touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];

    if ([self normalizedDistanceFrom:touchLocation to:lastTouchDownLocation] > LONG_PRESS_ACTIVATION_DELTA) {
        // Moved too far since touch down: this is a drag. Press now if we
        // were still waiting, and cancel the right click timer.
        if (pressTimer != nil) {
            [self pressLeft];
        }
        [longPressTimer invalidate];
        longPressTimer = nil;
    }

    [view updateCursorLocation:touchLocation isMouse:NO];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    // Only fire this logic if all touches have ended
    if (activeTouches(event).count > 0) {
        return;
    }

    UITouch* touch = [touches anyObject];

    if (multiTouch) {
        if (maxTouches == 2 && !scrolled &&
            touch.timestamp - multiStartTime < TWO_FINGER_TAP_MAX_DURATION) {
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        }
        multiTouch = NO;
        maxTouches = 0;
        [self releaseButtons];
        return;
    }

    // A quick tap lifts before the press delay: click now
    if (pressTimer != nil) {
        [self pressLeft];
    }
    [self releaseButtons];

    // Remember this last touch for touch-down deadzoning
    lastTouchUpTime = touch.timestamp;
    lastTouchUpLocation = [touch locationInView:view];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    // Never leave a button stuck down
    [self cancelTimers];
    if (leftDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        leftDown = NO;
    }
    if (activeTouches(event).count == 0) {
        multiTouch = NO;
        maxTouches = 0;
    }
}

@end
