// Copyright 2026 Medusa. Apache-2.0.

#ifndef MEDUSA_CORE_AC_PICTURE_IN_PICTURE_H_
#define MEDUSA_CORE_AC_PICTURE_IN_PICTURE_H_

#include <string>

namespace content {
class WebContents;
}

namespace medusacore {

void StartPictureInPictureObserver();

bool PictureInPictureTracing();
void TracePictureInPicture(const std::string& line);

void TraceAutoPictureInPictureInputs(content::WebContents* contents, const char* when);

}

#endif
