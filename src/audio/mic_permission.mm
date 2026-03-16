#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>
#include "mic_permission.h"

MicPermissionStatus check_mic_permission(void) {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    switch (status) {
        case AVAuthorizationStatusAuthorized:    return MIC_PERM_AUTHORIZED;
        case AVAuthorizationStatusDenied:        return MIC_PERM_DENIED;
        case AVAuthorizationStatusRestricted:    return MIC_PERM_RESTRICTED;
        case AVAuthorizationStatusNotDetermined: return MIC_PERM_NOT_DETERMINED;
    }
    return MIC_PERM_NOT_DETERMINED;
}

int request_mic_permission(void) {
    __block int granted = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL g) {
        granted = g ? 1 : 0;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return granted;
}

int request_mic_permission_timeout(int timeout_secs) {
    __block int granted = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL g) {
        granted = g ? 1 : 0;
        dispatch_semaphore_signal(sem);
    }];

    int64_t ns = (int64_t)timeout_secs * NSEC_PER_SEC;
    long result = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, ns));
    if (result != 0) return 0; // timed out
    return granted;
}
