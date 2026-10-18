#ifndef MEDUSA_CORE_AC_TAB_INFO_H_
#define MEDUSA_CORE_AC_TAB_INFO_H_

#import <Foundation/Foundation.h>

#include <string>

class GURL;

namespace content {
class WebContents;
}

namespace medusacore {

NSDictionary* SecurityInfoFor(content::WebContents* contents);

NSString* OriginOf(const GURL& url);

}

#endif
