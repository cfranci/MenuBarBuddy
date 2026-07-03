#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block and returns the NSException it threw, or nil on success.
/// Swift cannot catch Objective-C exceptions; AppKit APIs like
/// -[NSStatusItem setLength:] throw them on invalid input (macOS 26 caps
/// length at 10,000 and throws above it).
NSException * _Nullable MBBTryCatch(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
