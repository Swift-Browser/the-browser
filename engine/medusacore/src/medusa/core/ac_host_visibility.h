// Copyright 2026 Medusa. Apache-2.0.

#ifndef MEDUSA_CORE_AC_HOST_VISIBILITY_H_
#define MEDUSA_CORE_AC_HOST_VISIBILITY_H_

#include <optional>

namespace content {
class WebContents;
}

namespace medusacore {

void NoteTabShownByHost(content::WebContents* contents, bool shown);

std::optional<bool> ShownByHost(content::WebContents* contents);

void StartHostVisibility();

}

#endif
