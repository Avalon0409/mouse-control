#import <Cocoa/Cocoa.h>
#import "IOKitSPI.h"
#import "CoreGraphicsSPI.h"
// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "ScrollSource.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <libproc.h>
#import <time.h>

#define MILLISECOND ((uint64_t)1000000)

static NSString *const kScrollAccelerationTypeKey=@"HIDScrollAccelerationType";
static NSString *const kTrackpadScrollAcceleration=@"HIDTrackpadScrollAcceleration";

// the properties of a sending service that identify it
static NSArray<NSString *> *_identityPropertyKeys(void)
{
    return @[@kIOHIDProductKey, @kIOHIDTransportKey, @kIOHIDVendorIDKey, @kIOHIDProductIDKey, @kIOHIDSerialNumberKey, @kIOHIDLocationIDKey, kScrollAccelerationTypeKey];
}

static NSString *_stringValue(id obj)
{
    return [obj isKindOfClass:[NSString class]]&&[obj length]?obj:nil;
}

static NSNumber *_numberValue(id obj)
{
    return [obj isKindOfClass:[NSNumber class]]?obj:nil;
}

/* Keys are fields joined by "|", with "#continuous" or "#discrete" on the end.
 Escape those separators, and the escape character, inside a field, so a key can't be read two ways. */
static NSString *_escaped(NSString *field)
{
    NSString *result=[field stringByReplacingOccurrencesOfString:@"%" withString:@"%25"];
    result=[result stringByReplacingOccurrencesOfString:@"|" withString:@"%7C"];
    return [result stringByReplacingOccurrencesOfString:@"#" withString:@"%23"];
}

@interface ScrollSource ()
@property (readwrite) NSString *key;
@property (readwrite) NSArray<NSString *> *legacyKeys;
@property (readwrite) ScrollSourceKind kind;
@property (readwrite) ScrollSourceCategory category;
@property (readwrite, nullable) NSString *name;
@property (readwrite, nullable) NSString *path;
@property (readwrite) BOOL continuous;
@end

@implementation ScrollSource

/* The non-continuous and continuous sources for a key, indexed by the event's continuous flag.
 The identifier caches this pair per sender or pid. */
+ (NSArray<ScrollSource *> *)sourcesWithKey:(NSString *)key kind:(ScrollSourceKind)kind category:(ScrollSourceCategory)category name:(NSString *)name path:(NSString *)path
{
    NSMutableArray *const result=[NSMutableArray array];
    for (NSNumber *continuous in @[@NO, @YES]) {
        ScrollSource *const source=[[ScrollSource alloc] init];
        source.legacyKeys=@[];
        source.key=[key stringByAppendingString:[continuous boolValue]?@"#continuous":@"#discrete"];
        source.kind=kind;
        source.category=category;
        source.name=name;
        source.path=path;
        source.continuous=[continuous boolValue];
        [result addObject:source];
    }
    return result;
}

/* A resolved serial shares rules across transports. Anonymous devices use their connection
 location until a physical identity is available. Names remain display metadata. */
+ (NSArray<ScrollSource *> *)deviceSourcesWithKind:(ScrollSourceKind)kind properties:(NSDictionary<NSString *, id> *)properties trackpadDriver:(BOOL)trackpadDriver
{
    NSString *const product=_stringValue(properties[@kIOHIDProductKey]);
    NSString *const transport=_stringValue(properties[@kIOHIDTransportKey]);
    NSNumber *const vendorID=_numberValue(properties[@kIOHIDVendorIDKey]);
    NSNumber *const productID=_numberValue(properties[@kIOHIDProductIDKey]);
    NSMutableArray *const parts=[NSMutableArray arrayWithObjects:
                                 kind==ScrollSourceKindLocalDevice?@"device":@"remote",
                                 transport?_escaped(transport):@"",
                                 vendorID?[vendorID stringValue]:@"",
                                 productID?[productID stringValue]:@"",
                                 nil];

    NSString *const serial=_stringValue(properties[@kIOHIDSerialNumberKey]);
    if (serial) [parts addObject:[@"sn:" stringByAppendingString:_escaped(serial)]];
    else if (![vendorID integerValue]&&![productID integerValue]) [parts addObject:product?_escaped(product):@""];
    NSString *legacyBase=[parts componentsJoinedByString:@"|"];
    NSString *normalized=[[serial stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *alphanumeric=[[normalized componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
    BOOL validSerial=alphanumeric.length && [[alphanumeric stringByReplacingOccurrencesOfString:@"0" withString:@""] length] && [[alphanumeric stringByReplacingOccurrencesOfString:@"f" withString:@""] length];
    NSString *physical=_stringValue(properties[@"MouseControlPhysicalIdentity"]);
    NSString *prefix=kind==ScrollSourceKindLocalDevice?@"device":@"remote";
    NSString *weakBase=[NSString stringWithFormat:@"%@|%@|%@|%@|loc:%@",prefix,transport?_escaped(transport):@"",vendorID?:@"",productID?:@"",properties[@kIOHIDLocationIDKey]?:@0];
    NSString *oldSerialBase=validSerial?[NSString stringWithFormat:@"%@|%@|sn:%@",prefix,vendorID?:@"",_escaped(normalized)]:nil;
    NSString *serialBase=validSerial?[NSString stringWithFormat:@"%@|physical:serial:%@",prefix,_escaped(normalized)]:nil;
    NSString *base=physical?[NSString stringWithFormat:@"%@|physical:%@",prefix,_escaped(physical)]:(serialBase?:weakBase);
    const BOOL trackpad=trackpadDriver||[properties[kScrollAccelerationTypeKey] isEqual:kTrackpadScrollAcceleration];
    NSArray *sources=[self sourcesWithKey:base kind:kind category:trackpad?ScrollSourceCategoryTrackpad:ScrollSourceCategoryMouse name:product path:nil];
    for (NSUInteger i=0;i<sources.count;i++) {
        NSString *suffix=i?@"#continuous":@"#discrete";
        NSMutableArray *keys=[NSMutableArray array];
        for (NSString *candidate in @[legacyBase,weakBase,oldSerialBase?:weakBase,serialBase?:weakBase]) {
            NSString *key=[candidate stringByAppendingString:suffix];
            if (![key isEqualToString:[sources[i] key]] && ![keys containsObject:key]) [keys addObject:key];
        }
        [sources[i] setLegacyKeys:keys];
    }
    return sources;
}

+ (NSArray<ScrollSource *> *)appSourcesWithIdentifier:(NSString *)identifier name:(NSString *)name path:(NSString *)path
{
    return [self sourcesWithKey:[@"app|" stringByAppendingString:_escaped(identifier)] kind:ScrollSourceKindApp category:ScrollSourceCategoryOther name:name path:path];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ kind %ld category %ld name %@>", [self class], self.key, (long)self.kind, (long)self.category, self.name];
}

@end

#pragma mark Lookups

// The multitouch drivers publish an AppleMultitouchDevice child, which is the HID event
// service that sends the events, so check the parent's class too.
static BOOL _conformsToSelfOrParent(io_service_t service, const char *className)
{
    if (IOObjectConformsTo(service, className)) {
        return YES;
    }
    io_registry_entry_t parent=0;
    if (IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)!=KERN_SUCCESS) {
        return NO;
    }
    const BOOL result=IOObjectConformsTo(parent, className);
    IOObjectRelease(parent);
    return result;
}

// The sender of a HID event is the registry entry ID of the HID event service.
static NSArray<ScrollSource *> *_localDeviceSources(IOHIDEventSenderID senderID, NSDictionary *identities)
{
    const io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(senderID));
    if (!service) {
        return nil;
    }
    NSMutableDictionary *const properties=[NSMutableDictionary dictionary];
    for (NSString *key in _identityPropertyKeys()) {
        properties[key]=CFBridgingRelease(IORegistryEntryCreateCFProperty(service, (__bridge CFStringRef)key, kCFAllocatorDefault, 0));
    }
    NSString *transport=[_stringValue(properties[@kIOHIDTransportKey]) lowercaseString]?:@"";
    if ([transport containsString:@"bluetooth"]) transport=@"bluetooth";
    NSUInteger vendor=[properties[@kIOHIDVendorIDKey] unsignedIntegerValue];
    NSUInteger productID=[properties[@kIOHIDProductIDKey] unsignedIntegerValue];
    NSUInteger location=[properties[@kIOHIDLocationIDKey] unsignedIntegerValue];
    NSString *connection=[NSString stringWithFormat:@"%04lx:%04lx:%08lx:%@",(unsigned long)vendor,(unsigned long)productID,(unsigned long)location,transport];
    NSString *fallback=[NSString stringWithFormat:@"%04lx:%04lx:*:%@",(unsigned long)vendor,(unsigned long)productID,transport];
    properties[@"MouseControlPhysicalIdentity"]=identities[connection]?:identities[fallback];
    // for a trackpad whose node lacks the scroll acceleration type
    const BOOL trackpadDriver=_conformsToSelfOrParent(service, "AppleMultitouchTrackpadHIDEventDriver");
    IOObjectRelease(service);
    return [ScrollSource deviceSourcesWithKind:ScrollSourceKindLocalDevice properties:properties trackpadDriver:trackpadDriver];
}

/* Services created in user space, such as the ones Universal Control creates to mirror the
 other Mac's devices, are not in the IORegistry. Look for them in the HID event system
 instead. They copy the original device's properties, including the scroll acceleration type. */
static NSArray<ScrollSource *> *_remoteDeviceSources(IOHIDEventSenderID senderID)
{
    static IOHIDEventSystemClientRef client;
    if (!client) {
        client=IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    }
    NSArray *const services=CFBridgingRelease(IOHIDEventSystemClientCopyServices(client));
    for (id obj in services) {
        IOHIDServiceClientRef const service=(__bridge IOHIDServiceClientRef)obj;
        if ([(__bridge NSNumber *)IOHIDServiceClientGetRegistryID(service) isEqual:@(senderID)]) {
            NSMutableDictionary *const properties=[NSMutableDictionary dictionary];
            for (NSString *key in _identityPropertyKeys()) {
                properties[key]=CFBridgingRelease(IOHIDServiceClientCopyProperty(service, (__bridge CFStringRef)key));
            }
            return [ScrollSource deviceSourcesWithKind:ScrollSourceKindRemoteDevice properties:properties trackpadDriver:NO];
        }
    }
    return nil;
}

/* Apps are identified by bundle ID, or by executable path if the executable is not in a
 bundle. Never by pid, which changes every time the app restarts. */
static NSArray<ScrollSource *> *_appSources(pid_t pid)
{
    char buffer[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, buffer, sizeof(buffer))<=0) {
        return nil;
    }
    NSString *const executablePath=[[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer length:strlen(buffer)];

    // A bundle's executable is at <bundle>/Contents/MacOS/<executable>.
    NSString *const macOSPath=[executablePath stringByDeletingLastPathComponent];
    NSString *const contentsPath=[macOSPath stringByDeletingLastPathComponent];
    if ([[macOSPath lastPathComponent] isEqualToString:@"MacOS"]&&[[contentsPath lastPathComponent] isEqualToString:@"Contents"]) {
        NSBundle *const bundle=[NSBundle bundleWithPath:[contentsPath stringByDeletingLastPathComponent]];
        NSString *const bundleID=_stringValue([bundle bundleIdentifier]);
        if (bundleID) {
            NSString *const name=_stringValue([bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"])?:
                _stringValue([bundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey])?:
                [[NSFileManager defaultManager] displayNameAtPath:[bundle bundlePath]];
            return [ScrollSource appSourcesWithIdentifier:bundleID name:name path:[bundle bundlePath]];
        }
    }
    return [ScrollSource appSourcesWithIdentifier:executablePath name:[executablePath lastPathComponent] path:executablePath];
}

#pragma mark -

@interface ScrollSourceIdentifier ()
@property NSMutableDictionary<NSNumber *, NSArray<ScrollSource *> *> *senderSources;
@property NSMutableDictionary<NSNumber *, NSNumber *> *senderRetryTimes;
@property NSMutableDictionary<NSNumber *, NSArray<ScrollSource *> *> *pidSources;
@property NSMutableDictionary<NSNumber *, dispatch_source_t> *pidExitSources;
@property NSArray<ScrollSource *> *unidentifiedDeviceSources;
@property NSArray<ScrollSource *> *unknownAppSources;
@property NSArray<ScrollSource *> *unidentifiedSources;
@end

@implementation ScrollSourceIdentifier

- (instancetype)init
{
    self=[super init];
    if (self) {
        self.senderSources=[NSMutableDictionary dictionary];
        self.senderRetryTimes=[NSMutableDictionary dictionary];
        self.pidSources=[NSMutableDictionary dictionary];
        self.pidExitSources=[NSMutableDictionary dictionary];
        // each bucket has its own prefix, so the first field of a key always says what kind it is
        self.unidentifiedDeviceSources=[ScrollSource sourcesWithKey:@"unidentified-device" kind:ScrollSourceKindUnidentifiedDevice category:ScrollSourceCategoryOther name:nil path:nil];
        self.unknownAppSources=[ScrollSource sourcesWithKey:@"unknown-app" kind:ScrollSourceKindApp category:ScrollSourceCategoryOther name:nil path:nil];
        self.unidentifiedSources=[ScrollSource sourcesWithKey:@"unidentified" kind:ScrollSourceKindUnidentified category:ScrollSourceCategoryOther name:nil path:nil];
    }
    return self;
}

- (void)setHardwareIdentities:(NSDictionary<NSString *,NSString *> *)identities
{
    if ([_hardwareIdentities isEqualToDictionary:identities]) return;
    _hardwareIdentities=[identities copy];
    [self.senderSources removeAllObjects];
    [self.senderRetryTimes removeAllObjects];
}

- (void)dealloc
{
    for (dispatch_source_t source in [self.pidExitSources allValues]) {
        dispatch_source_cancel(source);
    }
}

- (ScrollSource *)sourceForHIDEvent:(IOHIDEventRef)hidEvent pid:(pid_t)pid continuous:(BOOL)continuous
{
    NSArray<ScrollSource *> *sources;
    if (hidEvent) {
        const IOHIDEventSenderID senderID=IOHIDEventGetSenderID(hidEvent);
        sources=senderID?[self sourcesForSender:senderID]:self.unidentifiedDeviceSources;
    }
    else if (pid) {
        sources=[self sourcesForPID:pid];
    }
    else {
        sources=self.unidentifiedSources;
    }
    return sources[continuous?1:0];
}

/* Registry entry IDs are not reused within a boot, so the result can be cached per sender.
 A new virtual service can send events before the HID event system lists it, so look up
 unidentified senders again, at most every 250ms. */
- (NSArray<ScrollSource *> *)sourcesForSender:(IOHIDEventSenderID)senderID
{
    NSNumber *const key=@(senderID);
    NSArray<ScrollSource *> *sources=self.senderSources[key];
    const uint64_t now=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (sources&&(sources!=self.unidentifiedDeviceSources||now<[self.senderRetryTimes[key] unsignedLongLongValue])) {
        return sources;
    }

    sources=_localDeviceSources(senderID,self.hardwareIdentities)?:_remoteDeviceSources(senderID);
    if (sources) {
        [self.senderRetryTimes removeObjectForKey:key];
        NSLog(@"HID sender 0x%llx is %@", senderID, sources[0]);
    }
    else {
        sources=self.unidentifiedDeviceSources;
        self.senderRetryTimes[key]=@(now+MILLISECOND*250);
    }
    self.senderSources[key]=sources;
    return sources;
}

/* Resolve a pid the first time it is seen, while the process still exists. Forget it when the
 process exits, since the pid may be reused. */
- (NSArray<ScrollSource *> *)sourcesForPID:(pid_t)pid
{
    NSNumber *const key=@(pid);
    NSArray<ScrollSource *> *sources=self.pidSources[key];
    if (sources) {
        return sources;
    }

    sources=_appSources(pid);
    if (!sources) {
        // the process has already gone
        return self.unknownAppSources;
    }
    NSLog(@"pid %d is %@", pid, sources[0]);
    self.pidSources[key]=sources;

    // If the process has already exited, libdispatch delivers the exit event straight away.
    dispatch_source_t const exitSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    if (exitSource) {
        __weak ScrollSourceIdentifier *const weakSelf=self;
        dispatch_source_set_event_handler(exitSource, ^{
            ScrollSourceIdentifier *const strongSelf=weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf.pidSources removeObjectForKey:key];
            dispatch_source_cancel(strongSelf.pidExitSources[key]);
            [strongSelf.pidExitSources removeObjectForKey:key];
        });
        self.pidExitSources[key]=exitSource;
        dispatch_resume(exitSource);
    }
    return sources;
}

@end
