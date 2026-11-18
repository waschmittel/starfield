// SPDX-License-Identifier: GPL-3.0-or-later
// Declarations for the ScreenSaver.framework classes that app-extension screensavers subclass. The framework
// exports them but its public headers don't declare them; they are undocumented and can change in any macOS
// release. See https://github.com/AerialScreensaver/AppexSaverMinimal (BACKGROUND.md) for how they were found.
#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

NS_ASSUME_NONNULL_BEGIN

/// Principal class (`NSExtensionPrincipalClass`).
@interface ScreenSaverExtension : NSObject
- (instancetype)init;
@end

/// Provides the saver's view (`ScreenSaverViewControllerClass`). Override `loadView` only.
@interface ScreenSaverViewController : NSViewController
@end

/// Options sheet (`ScreenSaverConfigurationSheetViewControllerClass`).
@interface ScreenSaverConfigurationViewController : NSViewController
- (void)configureSheetWillPresent;
/// Ends the sheet. `dismiss` and `sheetParent` don't work: the sheet belongs to System Settings.
- (void)configureSheetDidEnd;
@end

NS_ASSUME_NONNULL_END
