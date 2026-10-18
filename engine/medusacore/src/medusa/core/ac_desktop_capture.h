// Copyright 2026 Medusa. Apache-2.0.

#ifndef MEDUSA_CORE_AC_DESKTOP_CAPTURE_H_
#define MEDUSA_CORE_AC_DESKTOP_CAPTURE_H_

#include <string>

namespace content {
struct MediaStreamRequest;
class WebContents;
}

namespace medusacore {

void AllowDesktopCapture(content::WebContents* contents,
                         const std::string& source,
                         const std::string& frame_id,
                         const std::string& origin);

void ApplyDesktopCaptureGrant(content::WebContents* contents,
                              content::MediaStreamRequest& request);

}

#endif
