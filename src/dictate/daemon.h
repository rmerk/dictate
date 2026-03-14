#pragma once
#include <string>

namespace rcli {

// Get the path to the PID file: ~/Library/RCLI/dictate.pid
std::string daemon_pid_path();

// Get the path to the launchd plist: ~/Library/LaunchAgents/ai.runanywhere.rcli.dictate.plist
std::string daemon_plist_path();

// Write current PID to pid file. Returns true on success.
bool daemon_write_pid();

// Remove the PID file.
void daemon_remove_pid();

// Read PID from file. Returns -1 if not found or invalid.
pid_t daemon_read_pid();

// Check if the daemon process is running.
bool daemon_is_running();

// Start daemon in background via posix_spawn (re-execs with --foreground).
// Returns 0 on success, -1 on error.
int daemon_start_background(const char* argv0);

// Stop running daemon by sending SIGTERM.
// Returns 0 on success, -1 if not running.
int daemon_stop();

// Install launchd plist for auto-start at login.
// Returns 0 on success, -1 on error.
int daemon_install_launchd(const char* rcli_path);

// Remove launchd plist and stop daemon.
// Returns 0 on success, -1 on error.
int daemon_uninstall_launchd();

// Register SIGTERM handler for graceful shutdown.
// cleanup_fn is called before exit.
void daemon_register_signal_handler(void (*cleanup_fn)());

} // namespace rcli
