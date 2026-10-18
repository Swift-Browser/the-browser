#pragma once

#import <AppKit/AppKit.h>

@class ArdiaCoreWebView;

namespace ardiacore_pip {

void WatchZoom();

void VideoChanged(ArdiaCoreWebView *view, NSString *host, NSString *frameId, bool active);

void TabRequestedActivation(ArdiaCoreWebView *view);

}
