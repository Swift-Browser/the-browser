// Copyright 2026 Medusa. Apache-2.0.

#ifndef CHROME_BROWSER_MEDUSA_PIP_AC_PIP_CONTROLS_H_
#define CHROME_BROWSER_MEDUSA_PIP_AC_PIP_CONTROLS_H_

#include <optional>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/views/overlay/back_to_tab_button.h"
#include "chrome/browser/ui/views/overlay/close_image_button.h"
#include "chrome/browser/ui/views/overlay/overlay_controls_fade_animation.h"
#include "chrome/browser/ui/views/overlay/playback_image_button.h"
#include "services/media_session/public/cpp/media_position.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/view.h"

namespace gfx {
class Canvas;
}

inline constexpr int kMedusaPipButtonMargin = 12;
inline constexpr int kMedusaPipButtonSize = 28;

class MedusaBackToTabButton : public OverlayWindowBackToTabButton {
  METADATA_HEADER(MedusaBackToTabButton, OverlayWindowBackToTabButton)

 public:
  explicit MedusaBackToTabButton(PressedCallback callback);
  MedusaBackToTabButton(const MedusaBackToTabButton&) = delete;
  MedusaBackToTabButton& operator=(const MedusaBackToTabButton&) = delete;
  ~MedusaBackToTabButton() override;

  void Place(const gfx::Size& window_size);

 protected:
  void OnPaintBackground(gfx::Canvas* canvas) override;
  void PaintButtonContents(gfx::Canvas* canvas) override;
};

class MedusaCloseButton : public CloseImageButton {
  METADATA_HEADER(MedusaCloseButton, CloseImageButton)

 public:
  static constexpr int kWidth = 29;

  explicit MedusaCloseButton(PressedCallback callback);
  MedusaCloseButton(const MedusaCloseButton&) = delete;
  MedusaCloseButton& operator=(const MedusaCloseButton&) = delete;
  ~MedusaCloseButton() override;

  void Place(const gfx::Size& window_size);

 protected:
  void OnPaintBackground(gfx::Canvas* canvas) override;
  void PaintButtonContents(gfx::Canvas* canvas) override;
};

class MedusaPlaybackButton : public PlaybackImageButton {
  METADATA_HEADER(MedusaPlaybackButton, PlaybackImageButton)

 public:
  explicit MedusaPlaybackButton(PressedCallback callback);
  MedusaPlaybackButton(const MedusaPlaybackButton&) = delete;
  MedusaPlaybackButton& operator=(const MedusaPlaybackButton&) = delete;
  ~MedusaPlaybackButton() override;

 protected:
  void OnPaintBackground(gfx::Canvas* canvas) override;
  void PaintButtonContents(gfx::Canvas* canvas) override;
};

class MedusaProgressBar : public views::View {
  METADATA_HEADER(MedusaProgressBar, views::View)

 public:
  static constexpr int kSlopX = 4;
  static constexpr int kSlopY = 6;
  static constexpr float kBarHeight = 5;

  explicit MedusaProgressBar(base::RepeatingCallback<void(double)> seek);
  MedusaProgressBar(const MedusaProgressBar&) = delete;
  MedusaProgressBar& operator=(const MedusaProgressBar&) = delete;
  ~MedusaProgressBar() override;

  void SetMediaPosition(const media_session::MediaPosition& position);

  void Place(const gfx::Size& window_size);

  void OnPaint(gfx::Canvas* canvas) override;
  bool OnMousePressed(const ui::MouseEvent& event) override;
  bool OnMouseDragged(const ui::MouseEvent& event) override;
  void OnMouseReleased(const ui::MouseEvent& event) override;
  void OnMouseCaptureLost() override;
  ui::Cursor GetCursor(const ui::MouseEvent& event) override;

 private:
  double FractionAt(int x) const;
  void RepaintIfDrawn();

  base::RepeatingCallback<void(double)> seek_;
  media_session::MediaPosition position_;
  std::optional<double> drag_fraction_;
  bool dragging_ = false;
  base::RepeatingTimer timer_;
};

class MedusaControlsFadeAnimation : public OverlayControlsFadeAnimation {
 public:
  MedusaControlsFadeAnimation(
      const std::vector<raw_ptr<views::View>>& controls,
      Type type);
  MedusaControlsFadeAnimation(const MedusaControlsFadeAnimation&) =
      delete;
  MedusaControlsFadeAnimation& operator=(
      const MedusaControlsFadeAnimation&) = delete;
  ~MedusaControlsFadeAnimation() override;

  void AnimateToState(double state) override;
};

#endif
