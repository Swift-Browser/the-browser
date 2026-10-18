#pragma once

#import <AppKit/AppKit.h>

@class MedusaCoreWebView;

namespace medusacore_pip {

void WatchZoom();

void VideoChanged(MedusaCoreWebView *view, NSString *host, NSString *frameId, bool active);

void TabRequestedActivation(MedusaCoreWebView *view);

}
