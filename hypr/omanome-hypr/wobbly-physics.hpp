// SPDX-License-Identifier: MIT
// Pure, bounded wobbly mesh physics. This header deliberately has no
// compositor or graphics dependency so it can be tested outside Hyprland.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>

namespace omanome::wobbly {

struct Vec2 {
    float x = 0.F;
    float y = 0.F;
};

struct Config {
    int gridX = 8;
    int gridY = 8;
    int maxVertices = 1024;
    float stiffness = 0.72F;
    float friction = 0.78F;
    float damping = 0.62F;
    float mass = 1.F;
    float maxDeformation = 0.035F;
    float velocityInfluence = 0.45F;
};

struct Vertex {
    float x = 0.F;
    float y = 0.F;
    float u = 0.F;
    float v = 0.F;
};

inline float finiteOr(float value, float fallback) {
    return std::isfinite(value) ? value : fallback;
}

inline float clampFinite(float value, float low, float high, float fallback) {
    return std::clamp(finiteOr(value, fallback), low, high);
}

inline Config sanitize(Config value) {
    value.gridX = std::clamp(value.gridX, 2, 32);
    value.gridY = std::clamp(value.gridY, 2, 32);
    value.maxVertices = std::clamp(value.maxVertices, 4, 4096);
    while (value.gridX * value.gridY > value.maxVertices) {
        if (value.gridX >= value.gridY && value.gridX > 2)
            --value.gridX;
        else if (value.gridY > 2)
            --value.gridY;
        else
            break;
    }
    value.stiffness = clampFinite(value.stiffness, 0.01F, 32.F, 0.72F);
    value.friction = clampFinite(value.friction, 0.F, 32.F, 0.78F);
    value.damping = clampFinite(value.damping, 0.F, 32.F, 0.62F);
    value.mass = clampFinite(value.mass, 0.05F, 32.F, 1.F);
    value.maxDeformation = clampFinite(value.maxDeformation, 0.F, 0.25F, 0.035F);
    value.velocityInfluence = clampFinite(value.velocityInfluence, 0.F, 4.F, 0.45F);
    return value;
}

class MeshPhysics {
  public:
    explicit MeshPhysics(Config config = {}) : m_config(sanitize(config)) { rebuild(); }

    void configure(Config config) {
        m_config = sanitize(config);
        rebuild();
    }

    const Config& config() const { return m_config; }

    void resize(float width, float height) {
        m_width = std::max(1.F, finiteOr(width, 1.F));
        m_height = std::max(1.F, finiteOr(height, 1.F));
        rebuild();
    }

    void impulse(Vec2 delta) {
        delta.x = finiteOr(delta.x, 0.F);
        delta.y = finiteOr(delta.y, 0.F);
        const float maxAxis = std::max(m_width, m_height);
        const float scale = std::max(1.F, maxAxis) * m_config.velocityInfluence;
        for (auto& node : m_nodes) {
            const float edgeX = std::abs(node.u - 0.5F) * 2.F;
            const float edgeY = std::abs(node.v - 0.5F) * 2.F;
            const float edge = std::clamp(std::max(edgeX, edgeY), 0.F, 1.F);
            const float edgeEase = edge * edge * (3.F - 2.F * edge);
            node.target.x = std::clamp(-delta.x * edgeEase * m_config.velocityInfluence, -scale, scale);
            node.target.y = std::clamp(-delta.y * edgeEase * m_config.velocityInfluence, -scale, scale);
            node.velocity.x += node.target.x * 0.015F;
            node.velocity.y += node.target.y * 0.015F;
        }
    }

    void step(float seconds) {
        float dt = clampFinite(seconds, 0.F, 0.05F, 0.016F);
        if (dt <= 0.F)
            return;
        const float mass = std::max(0.05F, m_config.mass);
        const float damping = std::max(0.F, m_config.damping + m_config.friction);
        const float maxX = m_width * m_config.maxDeformation;
        const float maxY = m_height * m_config.maxDeformation;
        for (auto& node : m_nodes) {
            const Vec2 force{
                (node.target.x - node.offset.x) * m_config.stiffness,
                (node.target.y - node.offset.y) * m_config.stiffness,
            };
            node.velocity.x += force.x / mass * dt;
            node.velocity.y += force.y / mass * dt;
            const float drag = std::exp(-damping * dt);
            node.velocity.x *= drag;
            node.velocity.y *= drag;
            node.offset.x = std::clamp(node.offset.x + node.velocity.x * dt, -maxX, maxX);
            node.offset.y = std::clamp(node.offset.y + node.velocity.y * dt, -maxY, maxY);
            node.target.x *= std::exp(-m_config.friction * dt);
            node.target.y *= std::exp(-m_config.friction * dt);
            if (std::abs(node.offset.x) < 0.0001F && std::abs(node.velocity.x) < 0.0001F) {
                node.offset.x = 0.F;
                node.velocity.x = 0.F;
            }
            if (std::abs(node.offset.y) < 0.0001F && std::abs(node.velocity.y) < 0.0001F) {
                node.offset.y = 0.F;
                node.velocity.y = 0.F;
            }
        }
    }

    std::vector<Vertex> vertices() const {
        std::vector<Vertex> result;
        result.reserve(m_nodes.size());
        for (const auto& node : m_nodes) {
            result.push_back({
                node.u * m_width + node.offset.x,
                node.v * m_height + node.offset.y,
                node.u,
                node.v,
            });
        }
        return result;
    }

    std::size_t vertexCount() const { return m_nodes.size(); }

    bool finiteAndBounded() const {
        const float maxX = m_width * m_config.maxDeformation + 0.001F;
        const float maxY = m_height * m_config.maxDeformation + 0.001F;
        for (const auto& node : m_nodes) {
            if (!std::isfinite(node.offset.x) || !std::isfinite(node.offset.y) || !std::isfinite(node.velocity.x) || !std::isfinite(node.velocity.y))
                return false;
            if (std::abs(node.offset.x) > maxX || std::abs(node.offset.y) > maxY)
                return false;
        }
        return true;
    }

  private:
    struct Node {
        float u = 0.F;
        float v = 0.F;
        Vec2 offset;
        Vec2 velocity;
        Vec2 target;
    };

    void rebuild() {
        m_nodes.clear();
        m_nodes.reserve(static_cast<std::size_t>(m_config.gridX * m_config.gridY));
        for (int y = 0; y < m_config.gridY; ++y) {
            for (int x = 0; x < m_config.gridX; ++x) {
                const float u = static_cast<float>(x) / static_cast<float>(m_config.gridX - 1);
                const float v = static_cast<float>(y) / static_cast<float>(m_config.gridY - 1);
                m_nodes.push_back(Node{u, v, {}, {}, {}});
            }
        }
    }

    Config m_config;
    float m_width = 1.F;
    float m_height = 1.F;
    std::vector<Node> m_nodes;
};

} // namespace omanome::wobbly
