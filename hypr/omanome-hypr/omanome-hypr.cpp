// SPDX-License-Identifier: MIT
// Optional Omanome compositor companion. Every capability is behind the exact
// Hyprland API hash handshake and a versioned hyprctl status boundary. The
// core shell remains independent from this module and all unsupported effects
// fail closed instead of falling back to a visual imitation.
#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
HANDLE g_pluginHandle = nullptr;
SP<SHyprCtlCommand> g_statusCommand;

constexpr std::string_view kPluginVersion = "0.5.0";
constexpr int kProtocolVersion = 2;

std::string jsonString(std::string_view value) {
    std::string result;
    result.reserve(value.size() + 2);
    result.push_back('"');
    for (const unsigned char character : value) {
        switch (character) {
            case '"': result += "\\\""; break;
            case '\\': result += "\\\\"; break;
            case '\n': result += "\\n"; break;
            case '\r': result += "\\r"; break;
            case '\t': result += "\\t"; break;
            default:
                if (character < 0x20)
                    result += "?";
                else
                    result.push_back(static_cast<char>(character));
        }
    }
    result.push_back('"');
    return result;
}

std::string trim(std::string value) {
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char character) { return !std::isspace(character); }));
    value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char character) { return !std::isspace(character); }).base(), value.end());
    return value;
}

std::string statusJson() {
    const auto version = HyprlandAPI::getHyprlandVersion(g_pluginHandle);
    const std::string runtimeHash = __hyprland_api_get_hash();
    const std::string headerHash = __hyprland_api_get_client_hash();
    return "{\"protocolVersion\":" + std::to_string(kProtocolVersion) +
        ",\"pluginVersion\":" + jsonString(kPluginVersion) +
        ",\"loaded\":true,\"api\":{\"version\":" + jsonString(HYPRLAND_API_VERSION) +
        ",\"runtimeHash\":" + jsonString(runtimeHash) +
        ",\"headerHash\":" + jsonString(headerHash) +
        ",\"hashMatch\":" + std::string(runtimeHash == headerHash ? "true" : "false") +
        ",\"hyprlandCommit\":" + jsonString(version.hash) + "}," 
        "\"capabilities\":{\"blur\":false,\"livePreview\":false,\"wobblyWindows\":false,\"desktopCube\":false},"
        "\"renderer\":{\"windowTransformer\":\"available\",\"desktopCube3d\":\"unavailable\"},"
        "\"reason\":\"0.5 renderer capability slices are loaded only when their public API boundary is implemented\"}";
}

std::string statusCommand(eHyprCtlOutputFormat format, std::string arguments) {
    const auto request = trim(std::move(arguments));
    if (!request.empty() && request != "status") {
        if (format == FORMAT_JSON)
            return "{\"protocolVersion\":2,\"error\":\"unsupported request\",\"supported\":[\"status\"]}";
        return "omanome-effects: unsupported request; supported: status";
    }
    if (format == FORMAT_JSON)
        return statusJson();
    return "omanome-effects protocol=2 version=0.5.0 wobbly=unavailable cube3d=unavailable";
}

void rejectVersion(const std::string& reason) {
    HyprlandAPI::addNotification(g_pluginHandle, "[omanome-hypr] " + reason, CHyprColor{1.0F, 0.25F, 0.25F, 1.0F}, 5000.F);
    throw std::runtime_error("omanome-hypr: " + reason);
}
}

// Do not change this function. Hyprland calls it before pluginInit.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_pluginHandle = handle;

    const std::string runtimeHash = __hyprland_api_get_hash();
    const std::string headerHash = __hyprland_api_get_client_hash();
    if (runtimeHash != headerHash)
        rejectVersion("Hyprland API hash mismatch; companion stayed disabled");

    const auto version = HyprlandAPI::getHyprlandVersion(g_pluginHandle);
    if (version.hash != runtimeHash)
        rejectVersion("Hyprland version metadata mismatch; companion stayed disabled");

    g_statusCommand = HyprlandAPI::registerHyprCtlCommand(g_pluginHandle, {
        .name = "omanome-effects",
        .exact = true,
        .fn = statusCommand,
    });
    if (!g_statusCommand)
        rejectVersion("stable status IPC registration failed; companion stayed disabled");

    return {
        "omanome-hypr",
        "Version-aware optional compositor capability companion for Omanome",
        "Omanome contributors",
        "0.5.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_statusCommand = {};
    g_pluginHandle = nullptr;
}
