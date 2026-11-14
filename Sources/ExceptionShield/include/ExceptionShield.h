#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block and returns the NSException it threw, or nil on success.
NSException * _Nullable MBBTryCatch(void (NS_NOESCAPE ^block)(void));

/// Wraps the private MBAssessmentModeAssertion API (MenuBarClientCore.framework).
/// On macOS 27+ this hides third-party menu bar icons natively — truly gone,
/// no cover panel needed. Completion is called on the main queue.
@interface MBBarHider : NSObject
/// Hides all menu bar items except system items and the bundle IDs in allowedIDs.
/// Pass at minimum your own bundle ID; add pinned third-party IDs to keep them visible.
- (void)activateWithAllowedBundleIDs:(NSArray<NSString *> *)allowedIDs
                   allowedSystemItems:(NSArray<NSNumber *> *)sysItems
                           completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)deactivate;
@end

NS_ASSUME_NONNULL_END
