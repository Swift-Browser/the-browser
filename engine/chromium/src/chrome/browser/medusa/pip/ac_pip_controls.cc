// Copyright 2026 Medusa. Apache-2.0.

#include "chrome/browser/medusa/pip/ac_pip_controls.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "cc/paint/paint_flags.h"
#include "chrome/browser/ui/views/overlay/video_overlay_window_views.h"
#include "third_party/skia/include/core/SkPath.h"
#include "third_party/skia/include/core/SkPathBuilder.h"
#include "ui/base/cursor/cursor.h"
#include "ui/base/cursor/mojom/cursor_type.mojom-shared.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/events/event.h"
#include "ui/gfx/animation/tween.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/views/animation/ink_drop.h"

namespace {

void PaintCornerButtonBackground(const views::Button& button,
                                 gfx::Canvas* canvas) {
  const bool active = button.GetState() == views::Button::STATE_HOVERED ||
                      button.GetState() == views::Button::STATE_PRESSED;
  cc::PaintFlags flags;
  flags.setAntiAlias(true);
  flags.setColor(SkColorSetA(SK_ColorWHITE, active ? 0x21 : 0x17));
  canvas->DrawRoundRect(gfx::RectF(button.GetLocalBounds()), 6, flags);
}

cc::PaintFlags GlyphFlags() {
  cc::PaintFlags flags;
  flags.setAntiAlias(true);
  flags.setColor(SK_ColorWHITE);
  flags.setStyle(cc::PaintFlags::kStroke_Style);
  flags.setStrokeWidth(1);
  return flags;
}

void TurnOffInkDrop(views::Button* button) {
  views::InkDrop::Get(button)->SetMode(views::InkDropHost::InkDropMode::OFF);
}

}

MedusaBackToTabButton::MedusaBackToTabButton(PressedCallback callback)
    : OverlayWindowBackToTabButton(std::move(callback)) {
  SetSize(gfx::Size(kMedusaPipButtonSize, kMedusaPipButtonSize));
  TurnOffInkDrop(this);
}

MedusaBackToTabButton::~MedusaBackToTabButton() = default;

void MedusaBackToTabButton::Place(const gfx::Size& window_size) {
  views::View::SetPosition(
      gfx::Point(kMedusaPipButtonMargin, kMedusaPipButtonMargin));
}

void MedusaBackToTabButton::OnPaintBackground(gfx::Canvas* canvas) {
  PaintCornerButtonBackground(*this, canvas);
}

void MedusaBackToTabButton::PaintButtonContents(gfx::Canvas* canvas) {
  const cc::PaintFlags flags = GlyphFlags();
  const gfx::PointF corner(11, 11);
  canvas->DrawLine(gfx::PointF(10.5f, 11), gfx::PointF(18.3f, 11), flags);
  canvas->DrawLine(gfx::PointF(11, 10.5f), gfx::PointF(11, 18.3f), flags);
  canvas->DrawLine(corner, gfx::PointF(18.3f, 18.3f), flags);
}

BEGIN_METADATA(MedusaBackToTabButton)
END_METADATA

MedusaCloseButton::MedusaCloseButton(PressedCallback callback)
    : CloseImageButton(std::move(callback)) {
  SetSize(gfx::Size(kWidth, kMedusaPipButtonSize));
  TurnOffInkDrop(this);
}

MedusaCloseButton::~MedusaCloseButton() = default;

void MedusaCloseButton::Place(const gfx::Size& window_size) {
  views::View::SetPosition(
      gfx::Point(window_size.width() - kWidth - kMedusaPipButtonMargin,
                 kMedusaPipButtonMargin));
}

void MedusaCloseButton::OnPaintBackground(gfx::Canvas* canvas) {
  PaintCornerButtonBackground(*this, canvas);
}

void MedusaCloseButton::PaintButtonContents(gfx::Canvas* canvas) {
  const cc::PaintFlags flags = GlyphFlags();
  canvas->DrawLine(gfx::PointF(9.85f, 9.85f), gfx::PointF(18.65f, 18.65f),
                   flags);
  canvas->DrawLine(gfx::PointF(18.65f, 9.85f), gfx::PointF(9.85f, 18.65f),
                   flags);
}

BEGIN_METADATA(MedusaCloseButton)
END_METADATA

MedusaPlaybackButton::MedusaPlaybackButton(PressedCallback callback)
    : PlaybackImageButton(std::move(callback)) {
  TurnOffInkDrop(this);
  const ui::VectorIconModel replay = replay_image_.GetVectorIcon();
  replay_image_ = ui::ImageModel::FromVectorIcon(*replay.vector_icon(),
                                                 replay.color(), 36);
  UpdateImageAndText();
}

MedusaPlaybackButton::~MedusaPlaybackButton() = default;

void MedusaPlaybackButton::OnPaintBackground(gfx::Canvas* canvas) {}

void MedusaPlaybackButton::PaintButtonContents(gfx::Canvas* canvas) {
  if (playback_state_ == VideoOverlayWindowViews::kEndOfVideo) {
    views::ImageButton::PaintButtonContents(canvas);
    return;
  }
  cc::PaintFlags flags;
  flags.setAntiAlias(true);
  flags.setColor(SK_ColorWHITE);
  const gfx::PointF center = gfx::RectF(GetLocalBounds()).CenterPoint();
  if (playback_state_ == VideoOverlayWindowViews::kPlaying) {
    for (float x : {center.x() - 12, center.x() + 5}) {
      canvas->DrawRoundRect(gfx::RectF(x, center.y() - 21, 7, 42), 3.5f,
                            flags);
    }
    return;
  }
  const float left = center.x() - 12, top = center.y() - 18.5f;
  const SkPath triangle = SkPathBuilder()
                              .moveTo(left, top)
                              .lineTo(left + 31, center.y())
                              .lineTo(left, top + 37)
                              .close()
                              .detach();
  canvas->DrawPath(triangle, flags);
  flags.setStyle(cc::PaintFlags::kStroke_Style);
  flags.setStrokeWidth(5);
  flags.setStrokeJoin(cc::PaintFlags::kRound_Join);
  canvas->DrawPath(triangle, flags);
}

BEGIN_METADATA(MedusaPlaybackButton)
END_METADATA

MedusaProgressBar::MedusaProgressBar(
    base::RepeatingCallback<void(double)> seek)
    : seek_(std::move(seek)) {}

MedusaProgressBar::~MedusaProgressBar() = default;

void MedusaProgressBar::SetMediaPosition(
    const media_session::MediaPosition& position) {
  position_ = position;
  if (!dragging_) {
    drag_fraction_.reset();
  }
  SchedulePaint();
  if (position_.playback_rate() == 0 || position_.duration().is_zero()) {
    timer_.Stop();
  } else if (!timer_.IsRunning()) {
    timer_.Start(FROM_HERE, base::Milliseconds(100),
                 base::BindRepeating(&MedusaProgressBar::RepaintIfDrawn,
                                     base::Unretained(this)));
  }
}

void MedusaProgressBar::Place(const gfx::Size& window_size) {
  constexpr int kBottomMargin = 9;
  constexpr int kInset = kMedusaPipButtonMargin - kSlopX;
  constexpr int kHeight = static_cast<int>(kBarHeight);
  SetBoundsRect({kInset, window_size.height() - kBottomMargin - kHeight - kSlopY,
                 std::max(0, window_size.width() - 2 * kInset),
                 kHeight + 2 * kSlopY});
}

void MedusaProgressBar::RepaintIfDrawn() {
  if (IsDrawn()) {
    SchedulePaint();
  }
}

void MedusaProgressBar::OnPaint(gfx::Canvas* canvas) {
  const base::TimeDelta duration = position_.duration();
  if (!duration.is_positive() || duration.is_max()) {
    return;
  }
  const gfx::RectF track(kSlopX, kSlopY, width() - 2 * kSlopX, kBarHeight);
  cc::PaintFlags flags;
  flags.setAntiAlias(true);
  flags.setColor(SkColorSetA(SK_ColorWHITE, 0x44));
  canvas->DrawRoundRect(track, kBarHeight / 2, flags);
  const double fraction = std::clamp(
      drag_fraction_.value_or(position_.GetPosition() / duration), 0.0, 1.0);
  if (fraction <= 0) {
    return;
  }
  gfx::RectF played = track;
  played.set_width(
      std::max(kBarHeight, static_cast<float>(track.width() * fraction)));
  flags.setColor(SK_ColorWHITE);
  canvas->DrawRoundRect(played, kBarHeight / 2, flags);
}

bool MedusaProgressBar::OnMousePressed(const ui::MouseEvent& event) {
  if (!event.IsOnlyLeftMouseButton()) {
    return false;
  }
  dragging_ = true;
  drag_fraction_ = FractionAt(event.x());
  SchedulePaint();
  return true;
}

bool MedusaProgressBar::OnMouseDragged(const ui::MouseEvent& event) {
  drag_fraction_ = FractionAt(event.x());
  SchedulePaint();
  return true;
}

void MedusaProgressBar::OnMouseReleased(const ui::MouseEvent& event) {
  dragging_ = false;
  if (drag_fraction_) {
    seek_.Run(*drag_fraction_);
  }
}

void MedusaProgressBar::OnMouseCaptureLost() {
  dragging_ = false;
  drag_fraction_.reset();
  SchedulePaint();
}

ui::Cursor MedusaProgressBar::GetCursor(const ui::MouseEvent& event) {
  return ui::mojom::CursorType::kHand;
}

double MedusaProgressBar::FractionAt(int x) const {
  return std::clamp((x - kSlopX) / std::max(1.0, width() - 2.0 * kSlopX), 0.0,
                    1.0);
}

BEGIN_METADATA(MedusaProgressBar)
END_METADATA

MedusaControlsFadeAnimation::MedusaControlsFadeAnimation(
    const std::vector<raw_ptr<views::View>>& controls,
    Type type)
    : OverlayControlsFadeAnimation(controls, type) {
  SetDuration(base::Milliseconds(200));
}

MedusaControlsFadeAnimation::~MedusaControlsFadeAnimation() = default;

void MedusaControlsFadeAnimation::AnimateToState(double state) {
  OverlayControlsFadeAnimation::AnimateToState(
      gfx::Tween::CalculateValue(gfx::Tween::EASE_IN_OUT, state));
}
