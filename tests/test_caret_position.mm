#include <cassert>
#include <cstdio>
#include "dictate/caret_position.h"

static void test_returns_optional() {
    auto pos = rcli::get_caret_screen_position();
    if (pos) {
        printf("  PASS: test_returns_optional (got position: %.0f, %.0f)\n", pos->x, pos->y);
    } else {
        printf("  PASS: test_returns_optional (nullopt — no focused text field)\n");
    }
}

int main() {
    printf("caret_position tests:\n");
    test_returns_optional();
    printf("All caret_position tests passed.\n");
    return 0;
}
