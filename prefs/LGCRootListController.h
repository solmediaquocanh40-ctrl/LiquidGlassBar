#import <Preferences/PSListController.h>

@interface LGCRootListController : PSListController
- (void)openSelectedColorPicker:(id)sender;
- (void)openGlassTintColorPicker:(id)sender;
- (void)presentColorPickerForKey:(NSString *)prefKey defaultHex:(NSString *)defaultHex title:(NSString *)title;
@end
