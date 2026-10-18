#import <Foundation/Foundation.h>

namespace medusacore_host {

void NoteNavigationDownload(NSString *url, NSString *profile);
bool WasNavigationDownload(NSString *url, NSString *profile);
void ForgetPrivateNavigationDownloads(NSString *profile);

}
