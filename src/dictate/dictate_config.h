#pragma once
#include <string>
#include <fstream>
#include <sstream>
#include <map>

namespace rcli {

struct DictateConfig {
    std::string hotkey = "cmd+j";
    bool paste = true;
    bool notification = true;
    std::string language = "en";
};

inline std::map<std::string, std::string> parse_config_file(const std::string& path) {
    std::map<std::string, std::string> kv;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        auto eq = line.find('=');
        if (eq != std::string::npos) {
            std::string key = line.substr(0, eq);
            std::string val = line.substr(eq + 1);
            kv[key] = val;
        }
    }
    return kv;
}

inline DictateConfig load_dictate_config(const std::string& path) {
    auto kv = parse_config_file(path);
    DictateConfig cfg;
    if (kv.count("dictate_hotkey"))       cfg.hotkey = kv["dictate_hotkey"];
    if (kv.count("dictate_paste"))        cfg.paste = (kv["dictate_paste"] == "true");
    if (kv.count("dictate_notification")) cfg.notification = (kv["dictate_notification"] == "true");
    if (kv.count("dictate_language"))     cfg.language = kv["dictate_language"];
    return cfg;
}

inline void save_dictate_config(const std::string& path, const DictateConfig& cfg) {
    auto kv = parse_config_file(path);
    kv["dictate_hotkey"] = cfg.hotkey;
    kv["dictate_paste"] = cfg.paste ? "true" : "false";
    kv["dictate_notification"] = cfg.notification ? "true" : "false";
    kv["dictate_language"] = cfg.language;

    std::ofstream f(path);
    for (auto& [k, v] : kv) {
        f << k << "=" << v << "\n";
    }
}

} // namespace rcli
