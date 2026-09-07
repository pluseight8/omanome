// SPDX-License-Identifier: MIT
// Public-API-only Wobbly window renderer for the optional Hyprland companion.
#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <string_view>

namespace omanome::hypr {

namespace detail {
struct WobblyRuntime;
}

class WobblyManager {
  public:
    WobblyManager();
    ~WobblyManager();

    WobblyManager(const WobblyManager&) = delete;
    WobblyManager& operator=(const WobblyManager&) = delete;

    bool              available() const;
    bool              enabled() const;
    bool              enable();
    bool              disable();
    bool              configure(std::string_view arguments);
    void              shutdown();
    std::size_t       attachedWindows() const;
    std::string       configJson() const;
    const std::string& reason() const;

  private:
    std::unique_ptr<detail::WobblyRuntime> m_runtime;
};

} // namespace omanome::hypr
