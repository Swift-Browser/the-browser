#ifndef MEDUSA_CORE_MEDUSACORE_INTERNAL_H_
#define MEDUSA_CORE_MEDUSACORE_INTERNAL_H_

#import "medusa/core/public/MedusaCore.h"

class Profile;

namespace content {
class WebContents;
}

namespace medusacore {
class WindowHost;

void NoteProfileDying(Profile* profile);
bool IsProfileDying(const Profile* profile);
void NoteProfileDeleting(Profile* profile);
bool IsProfileDeleting(const Profile* profile);
}

@interface MedusaCoreProfile ()
+ (MedusaCoreProfile*)wrapperFor:(Profile*)profile;
@property(readonly) Profile* chromeProfile;
@end

@interface MedusaCoreTab ()
- (instancetype)initWithContents:(content::WebContents*)contents;
@property(readonly) content::WebContents* contents;
- (void)contentsDestroyed;
- (void)notify:(SEL)selector;
@end

@interface MedusaCoreWindow ()
@property(readonly) medusacore::WindowHost* host;
@end

#endif
