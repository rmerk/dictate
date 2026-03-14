#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>
#include "dictate/paste_engine.h"

static void test_clipboard_copy() {
    std::string test_text = "rcli_test_clipboard_" + std::to_string(getpid());
    assert(rcli::clipboard_copy(test_text));

    FILE* pipe = popen("pbpaste", "r");
    assert(pipe);
    char buf[1024];
    std::string result;
    while (fgets(buf, sizeof(buf), pipe)) result += buf;
    pclose(pipe);

    assert(result == test_text);
    printf("  PASS: test_clipboard_copy\n");
}

int main() {
    printf("paste_engine tests:\n");
    test_clipboard_copy();
    printf("All paste_engine tests passed.\n");
    return 0;
}
