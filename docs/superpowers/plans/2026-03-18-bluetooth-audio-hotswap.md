# Bluetooth Audio Device Hot-Swap Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically switch to a Bluetooth headset's microphone when connected, without requiring an app restart.

**Architecture:** Register a CoreAudio property listener on `kAudioHardwarePropertyDefaultInputDevice`. When the system default input device changes (e.g., Bluetooth headset connected), stop the capture AudioUnit, rebind it to the new device with the correct sample rate and stream format, and restart capture. All within the existing `AudioIO` class — no new files needed.

**Tech Stack:** CoreAudio (`AudioObjectAddPropertyListener`, HAL AudioUnit), C++17.

---

## Root Cause

`audio_io.cpp:339-350` — the default input device is queried once in `init_core_audio()` and hard-bound to the HAL AudioUnit. No `AudioObjectAddPropertyListener` exists, so the app never learns the default input changed.

## File Structure

No new files. All changes are in two existing files:

- **Modify:** `src/audio/audio_io.h` — add member for current device ID, declare listener callback and rebind method
- **Modify:** `src/audio/audio_io.cpp` — implement listener registration, device rebind logic, and cleanup

---

### Task 1: Add device-change member state and declarations to the header

**Files:**
- Modify: `src/audio/audio_io.h:62-92`

- [ ] **Step 1: Add new members and method declarations**

In the `#if defined(__APPLE__)` private section, add:

```cpp
// Hot-swap: track current input device and listen for changes
std::atomic<AudioDeviceID> current_input_device_{0};
std::shared_ptr<std::atomic<bool>> alive_ = std::make_shared<std::atomic<bool>>(true);

static OSStatus device_changed_callback(
    AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[],
    void* inClientData);

bool rebind_capture_device(AudioDeviceID new_device);
```

Also change the existing `device_capture_rate_` member (line 91) from plain `int` to atomic:

```cpp
// Change:  int device_capture_rate_ = 0;
// To:
std::atomic<int> device_capture_rate_{0};
```

And add `#include <memory>` to `audio_io.h` if not already present (for `std::shared_ptr`).

- [ ] **Step 2: Commit**

```bash
git add src/audio/audio_io.h
git commit -m "feat(audio): add device hot-swap declarations to AudioIO header"
```

---

### Task 2: Extract device binding into `rebind_capture_device()`

**Files:**
- Modify: `src/audio/audio_io.cpp:306-418`

This refactors the existing device-bind logic out of `init_core_audio()` into a reusable method, so both init and the change listener can call it.

- [ ] **Step 1: Implement `rebind_capture_device()`**

Add this method before `init_core_audio()`:

```cpp
bool AudioIO::rebind_capture_device(AudioDeviceID new_device) {
    // Stop capture while we reconfigure
    bool was_running = running_.load(std::memory_order_acquire);
    if (was_running && capture_unit_) {
        OSStatus stop_status = AudioOutputUnitStop(capture_unit_);
        if (stop_status != noErr) {
            LOG_ERROR("Audio", "Failed to stop capture unit during rebind: %d", (int)stop_status);
        }
    }

    // Must uninitialize before changing device properties
    AudioUnitUninitialize(capture_unit_);

    // Remember old device for error recovery
    AudioDeviceID old_device = current_input_device_.load(std::memory_order_relaxed);

    // Bind new device
    OSStatus status = AudioUnitSetProperty(
        capture_unit_, kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global, 0, &new_device, sizeof(new_device));
    if (status != noErr) {
        LOG_ERROR("Audio", "Failed to set new input device %u: %d", new_device, (int)status);
        // Recover: rebind to old device before re-initializing
        if (old_device != 0) {
            AudioUnitSetProperty(capture_unit_, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &old_device, sizeof(old_device));
        }
        AudioUnitInitialize(capture_unit_);
        if (was_running) AudioOutputUnitStart(capture_unit_);
        return false;
    }

    // Query new device's sample rate
    AudioObjectPropertyAddress rateProp;
    rateProp.mSelector = kAudioDevicePropertyNominalSampleRate;
    rateProp.mScope    = kAudioObjectPropertyScopeInput;
    rateProp.mElement  = kAudioObjectPropertyElementMain;
    Float64 deviceRate = 48000.0;
    UInt32 sz = sizeof(deviceRate);
    AudioObjectGetPropertyData(new_device, &rateProp, 0, nullptr, &sz, &deviceRate);

    int new_rate = (int)deviceRate;
    device_capture_rate_.store(new_rate, std::memory_order_release);

    // Update stream format to match new device rate
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate       = new_rate;
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = 1;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerFrame    = 4;
    fmt.mBytesPerPacket   = 4;

    status = AudioUnitSetProperty(capture_unit_, kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output, 1, &fmt, sizeof(fmt));
    if (status != noErr) {
        LOG_ERROR("Audio", "Failed to set capture format for device %u: %d", new_device, (int)status);
    }

    status = AudioUnitInitialize(capture_unit_);
    if (status != noErr) {
        LOG_ERROR("Audio", "Failed to reinitialize capture unit for device %u: %d", new_device, (int)status);
        // Recover: try to rebind to old device and restore its rate
        if (old_device != 0) {
            AudioUnitSetProperty(capture_unit_, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &old_device, sizeof(old_device));
            // Query old device's sample rate to restore correct format
            Float64 oldRate = 48000.0;
            UInt32 rsz = sizeof(oldRate);
            AudioObjectGetPropertyData(old_device, &rateProp, 0, nullptr, &rsz, &oldRate);
            device_capture_rate_.store((int)oldRate, std::memory_order_release);
            fmt.mSampleRate = (int)oldRate;
            AudioUnitSetProperty(capture_unit_, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output, 1, &fmt, sizeof(fmt));
            AudioUnitInitialize(capture_unit_);
            if (was_running) AudioOutputUnitStart(capture_unit_);
        }
        return false;
    }

    current_input_device_.store(new_device, std::memory_order_release);

    if (was_running) {
        AudioOutputUnitStart(capture_unit_);
    }

    LOG_DEBUG("Audio", "Rebound capture to device %u (rate: %dHz)",
              new_device, device_capture_rate_.load(std::memory_order_relaxed));
    return true;
}
```

- [ ] **Step 2: Refactor `init_core_audio()` to use `rebind_capture_device()`**

Replace lines 339–392 (from the "Look up the default input device" comment through `AudioUnitInitialize`) with:

```cpp
    // Look up the default input device and bind it
    AudioObjectPropertyAddress devProp;
    devProp.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    devProp.mScope    = kAudioObjectPropertyScopeGlobal;
    devProp.mElement  = kAudioObjectPropertyElementMain;
    AudioDeviceID inputDevId = 0;
    UInt32 devSz = sizeof(inputDevId);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &devProp, 0, nullptr, &devSz, &inputDevId);

    if (!rebind_capture_device(inputDevId)) {
        LOG_ERROR("Audio", "Failed initial capture device binding");
        return false;
    }
```

Remove the now-redundant stream format setup, `AudioUnitInitialize`, and sample rate query that were previously inline — `rebind_capture_device()` handles all of that.

The `init_core_audio()` callback setup (lines 382-386) must stay **before** the `rebind_capture_device()` call, since the callback struct needs to be set before `AudioUnitInitialize` runs inside rebind. Move the callback registration to right after the `AudioUnitSetProperty` that disables output IO (line 337), before the device lookup.

- [ ] **Step 3: Update `capture_callback` to use explicit atomic load**

In `capture_callback` (line 248 of the current source), change:
```cpp
    int dev_rate = self->device_capture_rate_;
```
to:
```cpp
    int dev_rate = self->device_capture_rate_.load(std::memory_order_relaxed);
```

This is required because `device_capture_rate_` is now `std::atomic<int>`. The implicit conversion works but an explicit `.load()` is clearer and consistent with the codebase's use of atomics.

- [ ] **Step 4: Verify build compiles**

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -20
```

Expected: clean build, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/audio/audio_io.cpp
git commit -m "refactor(audio): extract rebind_capture_device() for device hot-swap"
```

---

### Task 3: Implement the device-change listener

**Files:**
- Modify: `src/audio/audio_io.cpp`

- [ ] **Step 1: Implement the static callback**

Add above `rebind_capture_device()`:

```cpp
OSStatus AudioIO::device_changed_callback(
    AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[],
    void* inClientData) {
    auto* self = static_cast<AudioIO*>(inClientData);

    // Query the new default input device
    AudioObjectPropertyAddress devProp;
    devProp.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    devProp.mScope    = kAudioObjectPropertyScopeGlobal;
    devProp.mElement  = kAudioObjectPropertyElementMain;
    AudioDeviceID newDevId = 0;
    UInt32 sz = sizeof(newDevId);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &devProp, 0, nullptr, &sz, &newDevId);

    // Skip if device hasn't actually changed
    AudioDeviceID current = self->current_input_device_.load(std::memory_order_acquire);
    if (newDevId == current) {
        return noErr;
    }

    LOG_DEBUG("Audio", "Default input device changed: %u -> %u", current, newDevId);

    // Capture alive flag by shared_ptr — prevents use-after-free if AudioIO
    // is destroyed during the 200ms debounce window.
    auto alive = self->alive_;

    // Debounce: CoreAudio can fire multiple times during BT negotiation.
    // Dispatch with a short delay so only the final device wins.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            // Check if AudioIO is still alive
            if (!alive->load(std::memory_order_acquire)) {
                return;
            }
            // Re-check after debounce — device may have changed again
            AudioDeviceID latestDevId = 0;
            UInt32 sz2 = sizeof(latestDevId);
            AudioObjectGetPropertyData(kAudioObjectSystemObject, &devProp, 0, nullptr, &sz2, &latestDevId);
            AudioDeviceID cur = self->current_input_device_.load(std::memory_order_acquire);
            if (latestDevId != cur && latestDevId != 0) {
                self->rebind_capture_device(latestDevId);
            }
        });
    return noErr;
}
```

- [ ] **Step 2: Register the listener in `init_core_audio()`**

At the end of `init_core_audio()`, just before the final `LOG_DEBUG` and `return true`, add:

```cpp
    // Listen for default input device changes (Bluetooth connect/disconnect, etc.)
    AudioObjectPropertyAddress listenProp;
    listenProp.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    listenProp.mScope    = kAudioObjectPropertyScopeGlobal;
    listenProp.mElement  = kAudioObjectPropertyElementMain;
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &listenProp,
                                   device_changed_callback, this);
```

- [ ] **Step 3: Remove the listener in `shutdown_core_audio()`**

At the top of `shutdown_core_audio()`, before disposing units:

```cpp
    // Invalidate alive flag so any in-flight debounce blocks are no-ops
    alive_->store(false, std::memory_order_release);

    // Remove device-change listener (prevents new callbacks)
    AudioObjectPropertyAddress listenProp;
    listenProp.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    listenProp.mScope    = kAudioObjectPropertyScopeGlobal;
    listenProp.mElement  = kAudioObjectPropertyElementMain;
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &listenProp,
                                      device_changed_callback, this);
```

- [ ] **Step 4: Verify build compiles**

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -20
```

Expected: clean build, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/audio/audio_io.cpp
git commit -m "feat(audio): listen for default input device changes and auto-rebind capture"
```

---

### Task 4: Manual integration test

**Files:** None (testing only)

- [ ] **Step 1: Build and run**

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) && ./rcli
```

- [ ] **Step 2: Test Bluetooth hot-swap**

1. Start `rcli` (or the Robin app) with built-in mic active
2. Connect a Bluetooth headset
3. Watch logs for: `Default input device changed: <old> -> <new>` and `Rebound capture to device <new>`
4. Speak into Bluetooth headset mic — verify STT recognizes speech
5. Disconnect Bluetooth headset
6. Watch logs for device change back to built-in mic
7. Speak into built-in mic — verify STT still works

- [ ] **Step 3: Test edge cases**

1. Connect Bluetooth headset **before** starting app — verify it picks up BT mic from the start
2. Connect/disconnect rapidly — verify no crash
3. Connect BT headset while app is mid-speech-recognition — verify graceful transition

---

## Notes

- **Thread safety:** `current_input_device_` and `device_capture_rate_` are both `std::atomic` to prevent data races between the CoreAudio render thread (`capture_callback`), the property listener thread (`device_changed_callback`), and the GCD debounce block. `rebind_capture_device()` calls `AudioOutputUnitStop` which waits for the current render cycle to finish before reconfiguring, preventing races with `capture_callback`.
- **Lifetime safety:** The `dispatch_after` debounce block captures `alive_` (a `shared_ptr<atomic<bool>>`) by value. On shutdown, `alive_` is set to `false` before removing the listener. Any in-flight GCD block checks this flag and becomes a no-op, preventing use-after-free.
- **Debounce:** The `device_changed_callback` uses a 200ms `dispatch_after` to coalesce rapid-fire notifications during Bluetooth negotiation. After the delay, it re-queries the current default device to ensure we bind to the final settled device.
- **Error recovery:** On failure to bind a new device, `rebind_capture_device()` explicitly rebinds to the previous device (with its correct sample rate) before re-initializing, avoiding undefined state. Both failure paths (device bind failure + AudioUnit init failure) have recovery logic.
- **Bluetooth SCO vs A2DP:** When macOS selects a Bluetooth headset as input, it may use the SCO profile (8/16kHz). The resampling logic in `capture_callback` (lines 251-267) already handles rate mismatches, so this works automatically.
- **No API surface change:** This is entirely internal to `AudioIO`. The Robin app and C API need no changes.
- **Include needed:** Add `#include <dispatch/dispatch.h>` at the top of `audio_io.cpp` for `dispatch_after`. (On macOS this is available without additional linking.)
- **Atomic reads in capture_callback:** The existing line `int dev_rate = self->device_capture_rate_;` (line 248) becomes `int dev_rate = self->device_capture_rate_.load(std::memory_order_relaxed);` — this is a minor change needed after making the member atomic.
