#include "bridge/rcli_paste_bridge.h"
#include "dictate/paste_engine.h"
#include <string>

extern "C" {

int rcli_paste_text(const char* text) {
    if (!text) return -1;
    std::string str(text);
    if (!rcli::clipboard_copy(str)) return -1;
    rcli::simulate_paste();
    return 0;
}

void rcli_send_notification(const char* title, const char* body) {
    if (!title || !body) return;
    rcli::send_notification(std::string(title), std::string(body));
}

} // extern "C"
