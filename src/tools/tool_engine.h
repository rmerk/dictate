#pragma once

#include "core/types.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <functional>

namespace rastack {

class ToolEngine {
public:
    using ToolFunction = std::function<std::string(const std::string& args_json)>;

    ToolEngine();
    ~ToolEngine() = default;

    void register_tool(const std::string& name, ToolFunction fn);
    void register_defaults();

    // Returns external definitions if set, otherwise the built-in defaults.
    std::string get_tool_definitions_json() const;

    // Set external tool definitions JSON (e.g., from ActionRegistry).
    void set_external_tool_definitions(const std::string& json);

    std::vector<ToolCall> parse_tool_calls(const std::string& llm_output) const;
    ToolResult execute(const ToolCall& call);
    std::vector<ToolResult> execute_all(const std::vector<ToolCall>& calls);
    std::string format_results(const std::vector<ToolResult>& results) const;

    int num_tools() const { return static_cast<int>(tools_.size()); }
    bool has_tool(const std::string& name) const { return tools_.count(name) > 0; }
    std::vector<std::string> list_tool_names() const {
        std::vector<std::string> names;
        for (auto& [n, _] : tools_) names.push_back(n);
        return names;
    }

private:
    std::unordered_map<std::string, ToolFunction> tools_;
    std::string external_tool_defs_;
};

} // namespace rastack
