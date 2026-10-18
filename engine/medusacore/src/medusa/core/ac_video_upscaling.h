// Copyright 2026 Medusa. Apache-2.0.

#ifndef MEDUSA_CORE_AC_VIDEO_UPSCALING_H_
#define MEDUSA_CORE_AC_VIDEO_UPSCALING_H_

#include <optional>

@class NSDictionary;

namespace medusacore {

void StartVideoUpscaling();

void SetVideoUpscalingEnabled(bool enabled);

void SetVideoUpscalingTestConditions(std::optional<bool> low_power,
                                     std::optional<bool> thermal_pressure);

void VideoUpscalingInputsChanged();

NSDictionary* VideoUpscalingState();

}

#endif
