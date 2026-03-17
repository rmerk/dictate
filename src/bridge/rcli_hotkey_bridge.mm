#include "bridge/rcli_hotkey_bridge.h"
#include "dictate/hotkey_listener.h"
#include <string>

static RCLIHotkeyCallback g_bridge_callback = nullptr;
static void* g_bridge_user_data = nullptr;

extern "C" {

int rcli_hotkey_start(const char* hotkey_str, RCLIHotkeyCallback callback, void* user_data) {
    if (!hotkey_str || !callback) return 0;
    g_bridge_callback = callback;
    g_bridge_user_data = user_data;
    bool ok = rcli::hotkey_start(std::string(hotkey_str), []{
        if (g_bridge_callback) {
            g_bridge_callback(g_bridge_user_data);
        }
    });
    return ok ? 1 : 0;
}

void rcli_hotkey_stop(void) {
    rcli::hotkey_stop();
    g_bridge_callback = nullptr;
    g_bridge_user_data = nullptr;
}

void rcli_hotkey_set_active(int active) {
    rcli::hotkey_set_active(active != 0);
}

int rcli_hotkey_check_accessibility(void) {
    return rcli::hotkey_check_accessibility() ? 1 : 0;
}

} // extern "C"
