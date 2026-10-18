// Copyright 2026 Medusa. Apache-2.0.

#ifndef CHROME_BROWSER_MEDUSA_PIP_AC_PIP_MAC_H_
#define CHROME_BROWSER_MEDUSA_PIP_AC_PIP_MAC_H_

#include <optional>

#include "base/time/time.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"

std::optional<gfx::Rect> LoadMedusaPictureInPictureBounds();
void SaveMedusaPictureInPictureBounds(const gfx::Rect& bounds);

void FadeOutMedusaPictureInPicture(gfx::NativeWindow window,
                                      base::TimeDelta duration);
void ResetMedusaPictureInPictureFade(gfx::NativeWindow window);

#endif
