// Copyright 2026 Medusa. Apache-2.0.

#ifndef CHROME_BROWSER_MEDUSA_PIP_AC_PIP_WINDOW_H_
#define CHROME_BROWSER_MEDUSA_PIP_AC_PIP_WINDOW_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/views/overlay/video_overlay_window_views.h"

class MedusaProgressBar;

namespace content {
class VideoPictureInPictureWindowController;
}

class MedusaVideoOverlayWindow : public VideoOverlayWindowViews {
 public:
  explicit MedusaVideoOverlayWindow(
      content::VideoPictureInPictureWindowController* controller);
  MedusaVideoOverlayWindow(const MedusaVideoOverlayWindow&) = delete;
  MedusaVideoOverlayWindow& operator=(const MedusaVideoOverlayWindow&) =
      delete;
  ~MedusaVideoOverlayWindow() override;

  void ShowInactive() override;
  void Hide() override;
  void SetMediaPosition(const media_session::MediaPosition& position) override;
  void OnNativeWidgetMove() override;
  void OnNativeWidgetDestroyed() override;
  void OnNativeWidgetSizeChanged(const gfx::Size& new_size) override;
  void OnUpdateControlsBounds() override;
  void UpdateControlsVisibility(bool is_visible, bool should_animate) override;
  gfx::Rect GetProgressViewBounds() override;

 private:
  gfx::Rect CalculateAndUpdateWindowBounds() override;
  void SetUpViews() override;

  void OnCloseButtonPressed();
  void MaybeSaveBounds();
  void FinishHide();

  raw_ptr<MedusaProgressBar> ac_progress_bar_ = nullptr;
  base::TimeDelta ac_hide_fade_;
  base::OneShotTimer ac_hide_timer_;
};

std::unique_ptr<VideoOverlayWindowViews> NewMedusaVideoOverlayWindow(
    content::VideoPictureInPictureWindowController* controller);

#endif
