// SPDX-License-Identifier: MIT
// Optional Omanome compositor companion. Every capability is behind the exact
// Hyprland API hash handshake and a versioned hyprctl status boundary. The
// core shell remains independent from this module and all unsupported effects
// fail closed instead of falling back to a visual imitation.
#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>

#include "wobbly-effect.hpp"

#include <algorithm>
#include <cctype>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
HANDLE g_pluginHandle = nullptr;
SP<SHyprCtlCommand> g_statusCommand;
std::unique_ptr<omanome::hypr::WobblyManager> g_wobblyManager;

constexpr std::string_view kPluginVersion = "1.2.0";
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
    const bool wobblyAvailable = g_wobblyManager && g_wobblyManager->available();
    const bool wobblyEnabled = g_wobblyManager && g_wobblyManager->enabled();
    const std::string wobblyReason = g_wobblyManager ? g_wobblyManager->reason() : "companion manager is not initialized";
    return "{\"protocolVersion\":" + std::to_string(kProtocolVersion) +
        ",\"pluginVersion\":" + jsonString(kPluginVersion) +
        ",\"loaded\":true,\"api\":{\"version\":" + jsonString(HYPRLAND_API_VERSION) +
        ",\"runtimeHash\":" + jsonString(runtimeHash) +
        ",\"headerHash\":" + jsonString(headerHash) +
        ",\"hashMatch\":" + std::string(runtimeHash == headerHash ? "true" : "false") +
        ",\"hyprlandCommit\":" + jsonString(version.hash) + "}," 
        "\"capabilities\":{\"blur\":false,\"livePreview\":false,\"wobblyWindows\":" + std::string(wobblyAvailable ? "true" : "false") + ",\"desktopCube\":false},"
        "\"wobbly\":{\"available\":" + std::string(wobblyAvailable ? "true" : "false") + ",\"enabled\":" +
        std::string(wobblyEnabled ? "true" : "false") + ",\"attachedWindows\":" +
        std::to_string(g_wobblyManager ? g_wobblyManager->attachedWindows() : 0) + ",\"config\":" +
        (g_wobblyManager ? g_wobblyManager->configJson() : "{}") + ",\"reason\":" + jsonString(wobblyReason) + "},"
        "\"renderer\":{\"windowTransformer\":" + jsonString(wobblyAvailable ? "ready" : "unavailable") + ",\"desktopCube3d\":\"unavailable\"},"
        "\"reason\":" + jsonString(wobblyReason) + "}";
}

std::string statusCommand(eHyprCtlOutputFormat format, std::string arguments) {
    const auto request = trim(std::move(arguments));
    if (request == "wobbly enable") {
        if (!g_wobblyManager || !g_wobblyManager->enable()) {
            if (format == FORMAT_JSON)
                return "{\"protocolVersion\":2,\"error\":\"wobbly enable failed\",\"status\":" + statusJson() + "}";
            return "omanome-effects: wobbly enable failed; " + (g_wobblyManager ? g_wobblyManager->reason() : "manager unavailable");
        }
    } else if (request == "wobbly disable") {
        if (g_wobblyManager)
            (void)g_wobblyManager->disable();
    } else if (request.rfind("wobbly config ", 0) == 0) {
        const auto arguments = request.substr(std::string("wobbly config ").size());
        if (!g_wobblyManager || !g_wobblyManager->configure(arguments)) {
            if (format == FORMAT_JSON)
                return "{\"protocolVersion\":2,\"error\":\"invalid wobbly config\",\"status\":" + statusJson() + "}";
            return "omanome-effects: invalid wobbly config";
        }
    } else if (!request.empty() && request != "status") {
        if (format == FORMAT_JSON)
            return "{\"protocolVersion\":2,\"error\":\"unsupported request\",\"supported\":[\"status\",\"wobbly enable\",\"wobbly disable\",\"wobbly config key=value ...\"]}";
        return "omanome-effects: unsupported request; supported: status, wobbly enable, wobbly disable, wobbly config key=value ...";
    }
    if (format == FORMAT_JSON) {
        return statusJson();
    }
        return "omanome-effects protocol=2 version=1.2.0 wobbly=" + std::string(g_wobblyManager && g_wobblyManager->available() ?
                                                                                      (g_wobblyManager->enabled() ? "enabled" : "available") :
                                                                                      "unavailable") +
            " cube3d=unavailable";
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

    g_wobblyManager = std::make_unique<omanome::hypr::WobblyManager>();

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
        "1.2.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (g_wobblyManager)
        g_wobblyManager->shutdown();
    g_wobblyManager.reset();
    g_statusCommand = {};
    g_pluginHandle = nullptr;
}
