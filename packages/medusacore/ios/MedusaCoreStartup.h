#import <Foundation/Foundation.h>

#include <string>
#include <vector>

namespace medusacore_host {

void PrepareStartup(NSString *userDataDir, std::vector<std::string> &switches);

}
