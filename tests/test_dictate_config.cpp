#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include "dictate/dictate_config.h"

static void test_default_config() {
    rcli::DictateConfig cfg;
    assert(cfg.hotkey == "cmd+j");
    assert(cfg.paste == true);
    assert(cfg.notification == true);
    assert(cfg.language == "en");
    printf("  PASS: test_default_config\n");
}

static void test_load_config() {
    const char* path = "/tmp/test_rcli_dictate_config";
    {
        std::ofstream f(path);
        f << "engine=metalrt\n";
        f << "dictate_hotkey=cmd+shift+d\n";
        f << "dictate_paste=false\n";
        f << "dictate_notification=true\n";
        f << "dictate_language=es\n";
    }

    rcli::DictateConfig cfg = rcli::load_dictate_config(path);
    assert(cfg.hotkey == "cmd+shift+d");
    assert(cfg.paste == false);
    assert(cfg.notification == true);
    assert(cfg.language == "es");
    std::remove(path);
    printf("  PASS: test_load_config\n");
}

static void test_load_config_missing_keys() {
    const char* path = "/tmp/test_rcli_dictate_config2";
    {
        std::ofstream f(path);
        f << "engine=metalrt\n";
    }

    rcli::DictateConfig cfg = rcli::load_dictate_config(path);
    assert(cfg.hotkey == "cmd+j");
    assert(cfg.paste == true);
    assert(cfg.notification == true);
    assert(cfg.language == "en");
    std::remove(path);
    printf("  PASS: test_load_config_missing_keys\n");
}

static void test_save_config() {
    const char* path = "/tmp/test_rcli_dictate_config3";
    {
        std::ofstream f(path);
        f << "engine=metalrt\n";
        f << "dictate_hotkey=cmd+j\n";
    }

    rcli::DictateConfig cfg;
    cfg.hotkey = "cmd+k";
    cfg.paste = false;
    cfg.notification = false;
    cfg.language = "fr";
    rcli::save_dictate_config(path, cfg);

    rcli::DictateConfig loaded = rcli::load_dictate_config(path);
    assert(loaded.hotkey == "cmd+k");
    assert(loaded.paste == false);
    assert(loaded.notification == false);
    assert(loaded.language == "fr");

    std::ifstream f(path);
    std::string content((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());
    assert(content.find("engine=metalrt") != std::string::npos);
    std::remove(path);
    printf("  PASS: test_save_config\n");
}

int main() {
    printf("dictate_config tests:\n");
    test_default_config();
    test_load_config();
    test_load_config_missing_keys();
    test_save_config();
    printf("All dictate_config tests passed.\n");
    return 0;
}
