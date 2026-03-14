#include <cassert>
#include <cstdio>
#include <fstream>
#include <string>
#include <unistd.h>
#include "dictate/daemon.h"

static void test_pid_write_read() {
    assert(rcli::daemon_write_pid());
    pid_t read_pid = rcli::daemon_read_pid();
    assert(read_pid == getpid());
    rcli::daemon_remove_pid();
    printf("  PASS: test_pid_write_read\n");
}

static void test_pid_read_missing() {
    rcli::daemon_remove_pid();
    pid_t read_pid = rcli::daemon_read_pid();
    assert(read_pid == -1);
    printf("  PASS: test_pid_read_missing\n");
}

static void test_is_running_self() {
    rcli::daemon_write_pid();
    assert(rcli::daemon_is_running());
    rcli::daemon_remove_pid();
    printf("  PASS: test_is_running_self\n");
}

static void test_is_running_dead() {
    std::string path = rcli::daemon_pid_path();
    {
        std::ofstream f(path);
        f << "999999\n";
    }
    assert(!rcli::daemon_is_running());
    rcli::daemon_remove_pid();
    printf("  PASS: test_is_running_dead\n");
}

int main() {
    printf("daemon tests:\n");
    test_pid_write_read();
    test_pid_read_missing();
    test_is_running_self();
    test_is_running_dead();
    printf("All daemon tests passed.\n");
    return 0;
}
