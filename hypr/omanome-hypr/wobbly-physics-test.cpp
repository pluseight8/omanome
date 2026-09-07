// SPDX-License-Identifier: MIT
#include "wobbly-physics.hpp"

#include <cassert>
#include <cmath>

int main() {
    using omanome::wobbly::Config;
    using omanome::wobbly::MeshPhysics;

    Config unsafe;
    unsafe.gridX = 100;
    unsafe.gridY = 100;
    unsafe.maxVertices = 64;
    unsafe.maxDeformation = 100.F;
    MeshPhysics physics(unsafe);
    physics.resize(1920.F, 1080.F);
    assert(physics.vertexCount() <= 64);
    assert(physics.config().maxDeformation <= 0.25F);

    physics.impulse({1000000.F, -1000000.F});
    for (int i = 0; i < 2000; ++i) {
        physics.step(0.016F);
        assert(physics.finiteAndBounded());
    }
    for (const auto& vertex : physics.vertices()) {
        assert(std::isfinite(vertex.x));
        assert(std::isfinite(vertex.y));
        assert(std::abs(vertex.x - vertex.u * 1920.F) <= 1920.F * physics.config().maxDeformation + 0.001F);
        assert(std::abs(vertex.y - vertex.v * 1080.F) <= 1080.F * physics.config().maxDeformation + 0.001F);
    }

    physics.step(std::numeric_limits<float>::quiet_NaN());
    assert(physics.finiteAndBounded());
    return 0;
}
