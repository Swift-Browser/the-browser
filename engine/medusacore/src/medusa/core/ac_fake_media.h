#ifndef MEDUSA_CORE_AC_FAKE_MEDIA_H_
#define MEDUSA_CORE_AC_FAKE_MEDIA_H_

namespace content {
struct MediaStreamRequest;
}

namespace medusacore {

bool UsingFakeMediaDevices();

void InstallFakeMediaDevices();

void KeepAudioCaptureFake(content::MediaStreamRequest& request);

}

#endif
