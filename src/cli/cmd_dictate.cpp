#include "cmd_dictate.h"
#include "../dictate/dictate_config.h"
#include "../dictate/hotkey_listener.h"
#include "../dictate/overlay.h"
#include "../dictate/caret_position.h"
#include "../dictate/paste_engine.h"
#include "../dictate/daemon.h"
#include "../api/rcli_api.h"
#include "../audio/mic_permission.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

static RCLIHandle g_dictate_engine = nullptr;
static bool g_dictate_recording = false;
static rcli::DictateConfig g_dictate_config;

static void cleanup() {
    rcli::overlay_cleanup();
    rcli::hotkey_stop();
    rcli::daemon_remove_pid();
    if (g_dictate_engine) {
        rcli_destroy(g_dictate_engine);
        g_dictate_engine = nullptr;
    }
}

static void on_hotkey() {
    if (!g_dictate_recording) {
        g_dictate_recording = true;
        rcli::hotkey_set_active(true);
        auto caret = rcli::get_caret_screen_position();
        rcli::overlay_show(rcli::OverlayState::Recording, caret);
        rcli_start_capture(g_dictate_engine);
    } else {
        g_dictate_recording = false;
        rcli::hotkey_set_active(false);
        rcli::overlay_set_state(rcli::OverlayState::Transcribing);
        // Transcription is CPU-intensive — run on background queue to keep overlay animating
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            const char* transcript = rcli_stop_capture_and_transcribe(g_dictate_engine);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (transcript && strlen(transcript) > 0) {
                    rcli::dictation_output(transcript, g_dictate_config.paste, g_dictate_config.notification);
                }
                rcli::overlay_dismiss();
            });
        });
    }
}

static int run_foreground(const Args& args) {
    if (!rcli::hotkey_check_accessibility()) {
        rcli::hotkey_request_accessibility();
        fprintf(stderr, "Please grant Accessibility permission and restart.\n");
        return 1;
    }
    if (check_mic_permission() != MIC_PERM_AUTHORIZED) {
        request_mic_permission();
    }

    std::string config_path = std::string(getenv("HOME") ? getenv("HOME") : "/tmp") + "/Library/RCLI/config";
    g_dictate_config = rcli::load_dictate_config(config_path);

    g_dictate_engine = rcli_create(nullptr);
    if (!g_dictate_engine) {
        fprintf(stderr, "Failed to create engine.\n");
        return 1;
    }
    if (rcli_init_stt_only(g_dictate_engine, args.models_dir.c_str(), args.gpu_layers) != 0) {
        fprintf(stderr, "Failed to initialize STT engine.\n");
        rcli_destroy(g_dictate_engine);
        return 1;
    }

    rcli::daemon_register_signal_handler(nullptr);
    rcli::daemon_write_pid();

    rcli::overlay_init();
    if (!rcli::hotkey_start(g_dictate_config.hotkey, on_hotkey)) {
        fprintf(stderr, "Failed to register hotkey. Check Accessibility permissions.\n");
        cleanup();
        return 1;
    }

    printf("rcli dictate running. Hotkey: %s. Press Ctrl+C to stop.\n", g_dictate_config.hotkey.c_str());

    // Run the event loop. Signal handler sets flag and calls CFRunLoopStop.
    CFRunLoopRun();

    // Cleanup runs here on the main thread (async-signal-safe pattern)
    cleanup();
    return 0;
}

int cmd_dictate(const Args& args) {
    if (args.arg1 == "start") {
        if (args.foreground) {
            return run_foreground(args);
        }
        if (rcli::daemon_is_running()) {
            printf("Dictation daemon is already running.\n");
            return 0;
        }
        printf("Starting dictation daemon...\n");
        return rcli::daemon_start_background(args.argv0.c_str());
    }
    if (args.arg1 == "stop") {
        if (!rcli::daemon_is_running()) {
            printf("Dictation daemon is not running.\n");
            return 0;
        }
        printf("Stopping dictation daemon...\n");
        return rcli::daemon_stop();
    }
    if (args.arg1 == "status") {
        if (rcli::daemon_is_running()) {
            printf("Dictation daemon is running (PID %d).\n", rcli::daemon_read_pid());
        } else {
            printf("Dictation daemon is not running.\n");
        }
        return 0;
    }
    if (args.arg1 == "install") {
        printf("Installing dictation daemon for auto-start at login...\n");
        return rcli::daemon_install_launchd(args.argv0.c_str());
    }
    if (args.arg1 == "uninstall") {
        printf("Removing dictation daemon from login items...\n");
        return rcli::daemon_uninstall_launchd();
    }
    if (args.arg1 == "config") {
        std::string config_path = std::string(getenv("HOME") ? getenv("HOME") : "/tmp") + "/Library/RCLI/config";
        auto cfg = rcli::load_dictate_config(config_path);
        printf("Current dictation config:\n");
        printf("  hotkey:       %s\n", cfg.hotkey.c_str());
        printf("  paste:        %s\n", cfg.paste ? "true" : "false");
        printf("  notification: %s\n", cfg.notification ? "true" : "false");
        printf("  language:     %s\n", cfg.language.c_str());

        // Open /dev/tty for interactive input so it works even when stdin is redirected
        FILE* tty = fopen("/dev/tty", "r");
        if (!tty) {
            printf("\nEdit ~/Library/RCLI/config to change settings.\n");
            return 0;
        }

        printf("\nEdit settings (press Enter to keep current value):\n");

        char buf[256];

        // hotkey
        printf("  hotkey [%s]: ", cfg.hotkey.c_str());
        fflush(stdout);
        if (fgets(buf, sizeof(buf), tty)) {
            std::string val(buf);
            if (!val.empty() && val.back() == '\n') val.pop_back();
            if (!val.empty()) cfg.hotkey = val;
        }

        // paste
        printf("  paste (true/false) [%s]: ", cfg.paste ? "true" : "false");
        fflush(stdout);
        if (fgets(buf, sizeof(buf), tty)) {
            std::string val(buf);
            if (!val.empty() && val.back() == '\n') val.pop_back();
            if (!val.empty()) cfg.paste = (val == "true");
        }

        // notification
        printf("  notification (true/false) [%s]: ", cfg.notification ? "true" : "false");
        fflush(stdout);
        if (fgets(buf, sizeof(buf), tty)) {
            std::string val(buf);
            if (!val.empty() && val.back() == '\n') val.pop_back();
            if (!val.empty()) cfg.notification = (val == "true");
        }

        // language
        printf("  language [%s]: ", cfg.language.c_str());
        fflush(stdout);
        if (fgets(buf, sizeof(buf), tty)) {
            std::string val(buf);
            if (!val.empty() && val.back() == '\n') val.pop_back();
            if (!val.empty()) cfg.language = val;
        }

        fclose(tty);

        rcli::save_dictate_config(config_path, cfg);
        printf("\nConfig saved.\n");
        return 0;
    }

    printf("Usage: rcli dictate <command>\n\n");
    printf("Commands:\n");
    printf("  start             Start dictation daemon\n");
    printf("  start --foreground  Run in foreground (for debugging)\n");
    printf("  stop              Stop dictation daemon\n");
    printf("  status            Check daemon status\n");
    printf("  install           Auto-start at login\n");
    printf("  uninstall         Remove from login items\n");
    printf("  config            Show current configuration\n");
    return 0;
}
