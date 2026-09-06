// SPDX-License-Identifier: MIT
// Optional Omanome compositor companion. The module intentionally starts with
// a compatibility handshake only; an unloaded/unsupported renderer is safer
// than an ABI guess inside the Hyprland process.
#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>

#include <stdexcept>
#include <string>

namespace {
HANDLE g_pluginHandle = nullptr;

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

    return {
        "omanome-hypr",
        "Version-aware optional compositor capability companion for Omanome",
        "Omanome contributors",
        "0.4.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pluginHandle = nullptr;
}
