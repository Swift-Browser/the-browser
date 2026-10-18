#import "ACIsolation.h"

#import <objc/runtime.h>

static NSString *gDataDirectory;
static NSUserDefaults *gDefaults;

NSString *ACIsolatedDataDirectory(void) { return gDataDirectory; }

static NSUserDefaults *IsolatedStandardUserDefaults(id self, SEL _cmd) { return gDefaults; }

@interface ACIsolation : NSObject
@end

@implementation ACIsolation

+ (void)load {
  const char *dir = getenv("MEDUSA_DATA_DIR");
  if (!dir || !*dir) dir = getenv("MEDUSA_DATA_DIR");
  if (!dir || !*dir) return;
  NSString *path = @(dir);
  if (!path.absolutePath)
    path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
  gDataDirectory = path.stringByStandardizingPath;
  NSString *domain = NSBundle.mainBundle.bundleIdentifier ?: @"com.medusa.browser";
  gDefaults = [[NSUserDefaults alloc]
      initWithSuiteName:[[gDataDirectory stringByAppendingPathComponent:@"Preferences"] stringByAppendingPathComponent:domain]];
  if (!gDefaults) return;
  method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)),
                           (IMP)IsolatedStandardUserDefaults);
}

@end
