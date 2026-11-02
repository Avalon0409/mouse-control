#import <Cocoa/Cocoa.h>

extern const int64_t MouseControlSyntheticScrollTag;

@interface SmoothScrollEngine : NSObject
@property BOOL enabled;
@property double duration;
@property double multiplier;
@property double acceleration;
- (BOOL)processEvent:(CGEventRef)event continuous:(BOOL)continuous;
- (void)stop;
@end
