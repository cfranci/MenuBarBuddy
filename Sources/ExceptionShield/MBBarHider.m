#import "include/ExceptionShield.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// Type-safe invocation for activateWithConfiguration:completionHandler:
typedef void (*MBActivateFn)(id, SEL, id, void (^)(NSError *_Nullable));

static void mbbhLog(NSString *msg) {
    NSString *line = [msg stringByAppendingString:@"\n"];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/mbb-debug.log"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:url error:nil];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToURL:url atomically:YES];
    }
}

@implementation MBBarHider {
    id _assertion;
}

- (void)activateWithAllowedBundleIDs:(NSArray<NSString *> *)allowedIDs
                   allowedSystemItems:(NSArray<NSNumber *> *)sysItems
                           completion:(void (^)(BOOL, NSError * _Nullable))completion {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
               RTLD_NOW | RTLD_GLOBAL);
    });

    Class configClass    = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
    if (!configClass || !assertionClass) {
        mbbhLog(@"MBBarHider: MenuBarClientCore classes unavailable");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, [NSError errorWithDomain:@"MBBarHider" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"MenuBarClientCore unavailable"}]);
        });
        return;
    }

    // Build config: empty sysItems → initWithUnrestrictedMenuBarItems (allow ALL system items).
    // Non-empty sysItems → initWithAllowedSystemItems:allowedBundleIdentifiers: (allow only listed).
    id config;
    if (sysItems.count == 0) {
        config = [[configClass alloc] performSelector:@selector(initWithUnrestrictedMenuBarItems)];
        mbbhLog(@"MBBarHider: using initWithUnrestrictedMenuBarItems (all system items allowed)");
    } else {
        config = [[configClass alloc]
            performSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)
                 withObject:sysItems
                 withObject:allowedIDs];
        mbbhLog([NSString stringWithFormat:@"MBBarHider: restricted sysItems=%@ bundleIDs=%@", sysItems, allowedIDs]);
    }

    // Invalidate any previous assertion before creating a new one.
    if (_assertion) {
        [_assertion performSelector:@selector(invalidate)];
        _assertion = nil;
    }

    id assertion = [[assertionClass alloc] init];
    _assertion = assertion;

    mbbhLog([NSString stringWithFormat:@"MBBarHider: activating assertion config=%@", config]);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSError *activateError = nil;

        SEL activateSel = @selector(activateWithConfiguration:completionHandler:);
        IMP imp = [assertion methodForSelector:activateSel];
        MBActivateFn fn = (MBActivateFn)imp;
        fn(assertion, activateSel, config, ^(NSError *err) {
            activateError = err;
            mbbhLog([NSString stringWithFormat:@"MBBarHider: completion fired error=%@", err]);
            dispatch_semaphore_signal(sem);
        });

        long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        if (waited != 0) {
            mbbhLog(@"MBBarHider: TIMEOUT — completion block never fired in 5s");
        }

        if (activateError) {
            mbbhLog([NSString stringWithFormat:@"MBBarHider: FAILED code=%ld domain=%@ desc=%@",
                     (long)activateError.code, activateError.domain,
                     activateError.localizedDescription]);
            self->_assertion = nil;
        } else if (waited == 0) {
            mbbhLog(@"MBBarHider: SUCCESS");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(activateError == nil && waited == 0, activateError);
        });
    });
}

- (void)deactivate {
    if (_assertion) {
        mbbhLog(@"MBBarHider: deactivating");
        [_assertion performSelector:@selector(invalidate)];
        _assertion = nil;
    }
}

@end
