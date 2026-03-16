#include "dictate/daemon.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <spawn.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <CoreFoundation/CoreFoundation.h>

extern char** environ;

namespace rcli {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static std::string home_dir() {
    const char* h = getenv("HOME");
    return h ? std::string(h) : "/tmp";
}

static bool ensure_directory(const std::string& dir) {
    struct stat st{};
    if (stat(dir.c_str(), &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    return mkdir(dir.c_str(), 0755) == 0;
}

// ---------------------------------------------------------------------------
// PID file management
// ---------------------------------------------------------------------------

std::string daemon_pid_path() {
    return home_dir() + "/Library/RCLI/dictate.pid";
}

std::string daemon_plist_path() {
    return home_dir() + "/Library/LaunchAgents/ai.runanywhere.rcli.dictate.plist";
}

bool daemon_write_pid() {
    std::string dir = home_dir() + "/Library/RCLI";
    if (!ensure_directory(dir)) {
        return false;
    }
    std::ofstream ofs(daemon_pid_path());
    if (!ofs) return false;
    ofs << getpid() << "\n";
    return ofs.good();
}

void daemon_remove_pid() {
    unlink(daemon_pid_path().c_str());
}

pid_t daemon_read_pid() {
    std::ifstream ifs(daemon_pid_path());
    if (!ifs) return -1;
    pid_t pid = -1;
    ifs >> pid;
    if (ifs.fail() || pid <= 0) return -1;
    return pid;
}

bool daemon_is_running() {
    pid_t pid = daemon_read_pid();
    if (pid <= 0) return false;
    // kill with signal 0 checks if process exists without sending a signal
    return kill(pid, 0) == 0;
}

// ---------------------------------------------------------------------------
// Start / Stop
// ---------------------------------------------------------------------------

int daemon_start_background(const char* argv0) {
    if (daemon_is_running()) {
        fprintf(stderr, "daemon: already running (pid %d)\n", daemon_read_pid());
        return -1;
    }

    // Build argv: argv0 dictate start --foreground
    const char* child_argv[] = {argv0, "dictate", "start", "--foreground", nullptr};

    posix_spawn_file_actions_t file_actions;
    posix_spawn_file_actions_init(&file_actions);

    // Redirect stdin/stdout/stderr to /dev/null
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        posix_spawn_file_actions_adddup2(&file_actions, devnull, STDIN_FILENO);
        posix_spawn_file_actions_adddup2(&file_actions, devnull, STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(&file_actions, devnull, STDERR_FILENO);
        posix_spawn_file_actions_addclose(&file_actions, devnull);
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Set new process group so child is detached from terminal
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);

    pid_t child_pid = 0;
    int err = posix_spawn(&child_pid, argv0, &file_actions, &attr,
                          const_cast<char* const*>(child_argv), environ);

    posix_spawn_file_actions_destroy(&file_actions);
    posix_spawnattr_destroy(&attr);

    if (devnull >= 0) close(devnull);

    if (err != 0) {
        fprintf(stderr, "daemon: posix_spawn failed: %s\n", strerror(err));
        return -1;
    }

    fprintf(stderr, "daemon: started (pid %d)\n", child_pid);
    return 0;
}

int daemon_stop() {
    pid_t pid = daemon_read_pid();
    if (pid <= 0 || kill(pid, 0) != 0) {
        daemon_remove_pid();
        return -1; // not running
    }

    // Send SIGTERM first
    kill(pid, SIGTERM);

    // Wait up to 5 seconds for graceful shutdown
    for (int i = 0; i < 50; ++i) {
        usleep(100000); // 100ms
        if (kill(pid, 0) != 0) {
            daemon_remove_pid();
            return 0;
        }
    }

    // Force kill if still alive
    kill(pid, SIGKILL);
    usleep(200000);
    daemon_remove_pid();
    return 0;
}

// ---------------------------------------------------------------------------
// launchd integration
// ---------------------------------------------------------------------------

int daemon_install_launchd(const char* rcli_path) {
    // Stop any running daemon and unload existing plist first
    if (daemon_is_running()) {
        daemon_stop();
    }
    {
        std::string old_plist = daemon_plist_path();
        struct stat st{};
        if (stat(old_plist.c_str(), &st) == 0) {
            const char* lctl_argv[] = {"/bin/launchctl", "unload", old_plist.c_str(), nullptr};
            pid_t lctl_pid = 0;
            int err = posix_spawn(&lctl_pid, "/bin/launchctl", nullptr, nullptr,
                                  const_cast<char* const*>(lctl_argv), environ);
            if (err == 0) {
                int status = 0;
                waitpid(lctl_pid, &status, 0);
            }
        }
    }

    // Resolve to absolute path so launchd can find the binary
    char abs_path[PATH_MAX];
    if (!realpath(rcli_path, abs_path)) {
        fprintf(stderr, "daemon: failed to resolve path: %s\n", rcli_path);
        return -1;
    }
    static const char* plist_template = R"(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.runanywhere.rcli.dictate</string>
    <key>ProgramArguments</key>
    <array>
        <string>__RCLI_PATH__</string>
        <string>dictate</string>
        <string>start</string>
        <string>--foreground</string>
    </array>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/tmp/rcli-dictate.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/rcli-dictate.log</string>
</dict>
</plist>
)";

    // Replace __RCLI_PATH__ with actual path
    std::string plist(plist_template);
    std::string placeholder = "__RCLI_PATH__";
    auto pos = plist.find(placeholder);
    if (pos != std::string::npos) {
        plist.replace(pos, placeholder.size(), abs_path);
    }

    // Ensure LaunchAgents directory exists
    std::string agents_dir = home_dir() + "/Library/LaunchAgents";
    ensure_directory(agents_dir);

    // Write the plist
    std::string plist_path = daemon_plist_path();
    std::ofstream ofs(plist_path);
    if (!ofs) {
        fprintf(stderr, "daemon: failed to write plist to %s\n", plist_path.c_str());
        return -1;
    }
    ofs << plist;
    ofs.close();

    // Load via launchctl (using posix_spawn to avoid shell injection)
    {
        const char* lctl_argv[] = {"/bin/launchctl", "load", plist_path.c_str(), nullptr};
        pid_t lctl_pid = 0;
        int err = posix_spawn(&lctl_pid, "/bin/launchctl", nullptr, nullptr,
                              const_cast<char* const*>(lctl_argv), environ);
        if (err != 0) {
            fprintf(stderr, "daemon: launchctl load failed: %s\n", strerror(err));
            return -1;
        }
        int status = 0;
        waitpid(lctl_pid, &status, 0);
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            fprintf(stderr, "daemon: launchctl load exited with error\n");
            return -1;
        }
    }

    // Kickstart ensures the daemon actually starts even if launchd thinks
    // a previous run exited successfully (KeepAlive SuccessfulExit=false).
    {
        char uid_str[32];
        snprintf(uid_str, sizeof(uid_str), "gui/%d/ai.runanywhere.rcli.dictate", getuid());
        const char* kick_argv[] = {"/bin/launchctl", "kickstart", uid_str, nullptr};
        pid_t kick_pid = 0;
        posix_spawn(&kick_pid, "/bin/launchctl", nullptr, nullptr,
                    const_cast<char* const*>(kick_argv), environ);
        if (kick_pid > 0) {
            int status = 0;
            waitpid(kick_pid, &status, 0);
        }
    }

    return 0;
}

int daemon_uninstall_launchd() {
    std::string plist_path = daemon_plist_path();

    // Unload from launchd (ignore errors if not loaded)
    {
        const char* lctl_argv[] = {"/bin/launchctl", "unload", plist_path.c_str(), nullptr};
        pid_t lctl_pid = 0;
        int err = posix_spawn(&lctl_pid, "/bin/launchctl", nullptr, nullptr,
                              const_cast<char* const*>(lctl_argv), environ);
        if (err == 0) {
            int status = 0;
            waitpid(lctl_pid, &status, 0);
        }
    }

    // Remove plist file
    unlink(plist_path.c_str());

    // Stop daemon if still running
    if (daemon_is_running()) {
        daemon_stop();
    }

    return 0;
}

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------

static volatile sig_atomic_t g_should_quit = 0;

static void signal_handler(int /*sig*/) {
    g_should_quit = 1;
    // CFRunLoopStop is documented as safe to call from a signal handler
    CFRunLoopStop(CFRunLoopGetMain());
}

int daemon_should_quit() {
    return g_should_quit;
}

void daemon_register_signal_handler(void (*/*cleanup_fn*/)()) {
    // cleanup_fn is no longer called from the signal handler (not async-signal-safe).
    // Instead, the run loop checks daemon_should_quit() and calls cleanup normally.
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
}

} // namespace rcli
