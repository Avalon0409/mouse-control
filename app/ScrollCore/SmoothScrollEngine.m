#import "SmoothScrollEngine.h"

const int64_t MouseControlSyntheticScrollTag = 0x4D435343524F4C4C;

@interface SmoothScrollEngine ()
@property NSTimer *timer;
@property double pendingX;
@property double pendingY;
@property CGEventTimestamp previousEventTime;
@end

@implementation SmoothScrollEngine
- (instancetype)init {
    if ((self = [super init])) { _duration = 0.16; _multiplier = 1; }
    return self;
}

- (BOOL)processEvent:(CGEventRef)event continuous:(BOOL)continuous {
    if (continuous) return NO;
    double x = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
    double y = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    CGEventTimestamp now = CGEventGetTimestamp(event);
    double interval = self.previousEventTime && now > self.previousEventTime ? (now - self.previousEventTime) / 1e9 : 0.1;
    self.previousEventTime = now;
    double speed = hypot(x, y) / MAX(0.01, interval);
    double gain = MIN(5, MAX(0.1, self.multiplier)) * (1 + MIN(2, MAX(0, self.acceleration)) * MIN(2, speed / 800));
    if (!self.enabled) {
        if (fabs(gain - 1) > 0.001) {
            CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1, llround(y * gain));
            CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2, llround(x * gain));
            CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1, y * gain);
            CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2, x * gain);
        }
        return NO;
    }
    self.pendingX += x * gain;
    self.pendingY += y * gain;
    if (!self.timer) {
        __weak SmoothScrollEngine *weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    return YES;
}

- (void)tick {
    double fraction = MIN(1, (1.0 / 120) * 4 / MAX(0.04, MIN(0.6, self.duration)));
    int32_t x = (int32_t)llround(self.pendingX * fraction);
    int32_t y = (int32_t)llround(self.pendingY * fraction);
    if (!x && fabs(self.pendingX) >= 0.5) x = self.pendingX > 0 ? 1 : -1;
    if (!y && fabs(self.pendingY) >= 0.5) y = self.pendingY > 0 ? 1 : -1;
    self.pendingX -= x; self.pendingY -= y;
    if (x || y) {
        CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, y, x);
        if (event) {
            CGEventSetIntegerValueField(event, kCGEventSourceUserData, MouseControlSyntheticScrollTag);
            CGEventPost(kCGHIDEventTap, event);
            CFRelease(event);
        }
    }
    if (fabs(self.pendingX) < 0.5 && fabs(self.pendingY) < 0.5) [self stop];
}

- (void)stop { [self.timer invalidate]; self.timer = nil; self.pendingX = 0; self.pendingY = 0; }
- (void)dealloc { [_timer invalidate]; }
@end
