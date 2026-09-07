// SPDX-License-Identifier: MIT
// Real Wobbly rendering through Hyprland's public IWindowTransformer boundary.
#define WLR_USE_UNSTABLE

#include "wobbly-effect.hpp"

#include "wobbly-physics.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/transformer/Transformer.hpp>

#include <GLES3/gl32.h>
#include <drm_fourcc.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace omanome::hypr::detail {

namespace {

constexpr char kWobblyVertexShader[] = R"GLSL(
#version 300 es
precision highp float;

in vec2 pos;
in vec2 texcoord;
out vec2 uv;
uniform vec2 fbSize;

void main() {
    vec2 ndc = vec2((pos.x / fbSize.x) * 2.0 - 1.0, 1.0 - (pos.y / fbSize.y) * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    uv = texcoord;
}
)GLSL";

constexpr char kWobblyFragmentShader[] = R"GLSL(
#version 300 es
precision highp float;

in vec2 uv;
out vec4 color;
uniform sampler2D tex;

void main() {
    color = texture(tex, uv);
}
)GLSL";

struct GpuVertex {
    float x;
    float y;
    float u;
    float v;
};

bool finiteBox(const CBox& box) {
    return std::isfinite(box.x) && std::isfinite(box.y) && std::isfinite(box.w) && std::isfinite(box.h) && box.w > 1.0 && box.h > 1.0;
}

std::optional<CBox> pixelWindowBox(const PHLWINDOW& window, const PHLMONITOR& monitor) {
    if (!window || !monitor || !window->m_isMapped || window->m_isX11 || monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
        return std::nullopt;

    auto box = window->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    box.translate(-monitor->m_position);
    box.scale(monitor->m_scale);
    box.round();
    if (!finiteBox(box))
        return std::nullopt;
    return box;
}

struct GLStateGuard {
    GLint program = 0;
    GLint vao = 0;
    GLint arrayBuffer = 0;
    GLint elementBuffer = 0;
    GLint activeTexture = GL_TEXTURE0;
    GLint texture0 = 0;
    GLint viewport[4] = {};
    GLint scissor[4] = {};
    GLint blendSrcRGB = GL_ONE;
    GLint blendDstRGB = GL_ZERO;
    GLint blendSrcAlpha = GL_ONE;
    GLint blendDstAlpha = GL_ZERO;
    GLint blendEquationRGB = GL_FUNC_ADD;
    GLint blendEquationAlpha = GL_FUNC_ADD;
    GLfloat clearColor[4] = {};
    GLboolean colorMask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
    GLboolean blend = GL_FALSE;
    GLboolean depth = GL_FALSE;
    GLboolean cull = GL_FALSE;
    GLboolean scissorTest = GL_FALSE;

    GLStateGuard() {
        glGetIntegerv(GL_CURRENT_PROGRAM, &program);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer);
        glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &elementBuffer);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
        glGetIntegerv(GL_VIEWPORT, viewport);
        glGetIntegerv(GL_SCISSOR_BOX, scissor);
        glGetIntegerv(GL_BLEND_SRC_RGB, &blendSrcRGB);
        glGetIntegerv(GL_BLEND_DST_RGB, &blendDstRGB);
        glGetIntegerv(GL_BLEND_SRC_ALPHA, &blendSrcAlpha);
        glGetIntegerv(GL_BLEND_DST_ALPHA, &blendDstAlpha);
        glGetIntegerv(GL_BLEND_EQUATION_RGB, &blendEquationRGB);
        glGetIntegerv(GL_BLEND_EQUATION_ALPHA, &blendEquationAlpha);
        glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor);
        glGetBooleanv(GL_COLOR_WRITEMASK, colorMask);
        blend = glIsEnabled(GL_BLEND);
        depth = glIsEnabled(GL_DEPTH_TEST);
        cull = glIsEnabled(GL_CULL_FACE);
        scissorTest = glIsEnabled(GL_SCISSOR_TEST);

        glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture0);
        glActiveTexture(static_cast<GLenum>(activeTexture));
    }

    ~GLStateGuard() {
        glUseProgram(static_cast<GLuint>(program));
        glBindVertexArray(static_cast<GLuint>(vao));
        glBindBuffer(GL_ARRAY_BUFFER, static_cast<GLuint>(arrayBuffer));
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLuint>(elementBuffer));
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(texture0));
        glActiveTexture(static_cast<GLenum>(activeTexture));

        glBlendFuncSeparate(static_cast<GLenum>(blendSrcRGB), static_cast<GLenum>(blendDstRGB), static_cast<GLenum>(blendSrcAlpha),
                            static_cast<GLenum>(blendDstAlpha));
        glBlendEquationSeparate(static_cast<GLenum>(blendEquationRGB), static_cast<GLenum>(blendEquationAlpha));
        glBlendColor(0.F, 0.F, 0.F, 0.F);
        glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
        glScissor(scissor[0], scissor[1], scissor[2], scissor[3]);
        glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
        glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);

        if (blend)
            glEnable(GL_BLEND);
        else
            glDisable(GL_BLEND);
        if (depth)
            glEnable(GL_DEPTH_TEST);
        else
            glDisable(GL_DEPTH_TEST);
        if (cull)
            glEnable(GL_CULL_FACE);
        else
            glDisable(GL_CULL_FACE);
        if (scissorTest)
            glEnable(GL_SCISSOR_TEST);
        else
            glDisable(GL_SCISSOR_TEST);
    }
};

} // namespace

struct WobblyRuntime {
    bool                         available = false;
    bool                         enabled = false;
    bool                         failed = false;
    std::string                  reason = "public GL IWindowTransformer boundary is unavailable";
    omanome::wobbly::Config      config;
    std::unique_ptr<CShader>     shader;
    std::vector<CHyprSignalListener> listeners;
};

void failRuntime(WobblyRuntime& runtime, std::string reason) {
    runtime.available = false;
    runtime.failed = true;
    runtime.reason = std::move(reason);
}

bool rendererAvailable() {
    return g_pHyprRenderer && g_pHyprRenderer->type() == Render::IHyprRenderer::RT_GL && Render::GL::g_pHyprOpenGL;
}

bool ensureShader(WobblyRuntime& runtime) {
    if (!runtime.available || runtime.failed)
        return false;
    if (runtime.shader)
        return true;

    auto shader = std::make_unique<CShader>();
    if (!shader->createProgram(kWobblyVertexShader, kWobblyFragmentShader, true, true)) {
        failRuntime(runtime, "Wobbly mesh shader compilation failed; renderer disabled");
        return false;
    }
    shader->setUsesCustomUV(true);
    runtime.shader = std::move(shader);
    return true;
}

class OmanomeWobblyTransformer final : public Render::IWindowTransformer {
  public:
    OmanomeWobblyTransformer(WobblyRuntime* runtime, PHLWINDOWREF window) : m_runtime(runtime), m_window(std::move(window)), m_physics(runtime->config) {}

    ~OmanomeWobblyTransformer() override {
        if (m_ebo)
            glDeleteBuffers(1, &m_ebo);
        if (m_vbo)
            glDeleteBuffers(1, &m_vbo);
        if (m_vao)
            glDeleteVertexArrays(1, &m_vao);
    }

    void preWindowRender(CSurfacePassElement::SRenderData* data) override {
        if (!m_runtime || !m_runtime->available || !m_runtime->enabled || !data)
            return;

        const auto window = m_window.lock();
        const auto monitor = data->pMonitor.lock();
        const auto box = pixelWindowBox(window, monitor);
        if (!box) {
            m_ready = false;
            return;
        }

        const auto now = std::chrono::steady_clock::now();
        if (!m_ready) {
            m_box = *box;
            m_physics.resize(static_cast<float>(m_box.w), static_cast<float>(m_box.h));
            m_lastTick = now;
            m_ready = true;
            return;
        }

        const auto seconds = std::chrono::duration<float>(now - m_lastTick).count();
        m_lastTick = now;
        const bool resized = std::abs(m_box.w - box->w) > 0.5 || std::abs(m_box.h - box->h) > 0.5;
        const omanome::wobbly::Vec2 delta{
            static_cast<float>((box->x - m_box.x) + (box->w - m_box.w) * 0.35),
            static_cast<float>((box->y - m_box.y) + (box->h - m_box.h) * 0.35),
        };
        if (resized)
            m_physics.resize(static_cast<float>(box->w), static_cast<float>(box->h));
        if (std::abs(delta.x) > 0.01F || std::abs(delta.y) > 0.01F)
            m_physics.impulse(delta);
        m_physics.step(seconds);
        m_box = *box;
    }

    SP<Render::IFramebuffer> transform(SP<Render::IFramebuffer> in) override {
        if (!m_runtime || !m_runtime->available || !m_runtime->enabled || !m_ready || !in || !in->isAllocated())
            return in;

        const auto input = in->getTexture();
        if (!input || !input->ok() || input->m_texID == 0 || input->m_type != Render::TEXTURE_RGBA)
            return in;
        if (!rendererAvailable() || !ensureShader(*m_runtime))
            return in;

        const int width = static_cast<int>(std::round(in->m_size.x));
        const int height = static_cast<int>(std::round(in->m_size.y));
        if (width <= 1 || height <= 1 || !std::isfinite(in->m_size.x) || !std::isfinite(in->m_size.y))
            return in;

        auto output = g_pHyprRenderer->createFB("omanome-wobbly");
        if (!output || !output->alloc(width, height, in->m_drmFormat == DRM_FORMAT_INVALID ? DRM_FORMAT_ARGB8888 : in->m_drmFormat))
            return in;

        if (!ensureBuffers())
            return in;

        const auto vertices = makeVertices(static_cast<float>(width), static_cast<float>(height));
        const auto indices = makeIndices();
        if (vertices.empty() || indices.empty())
            return in;

        auto framebufferGuard = g_pHyprRenderer->bindTempFB(output);
        bool drawFailed = false;
        {
            GLStateGuard state;
            const GLuint program = m_runtime->shader->program();
            const GLint posLocation = glGetAttribLocation(program, "pos");
            const GLint uvLocation = glGetAttribLocation(program, "texcoord");
            const GLint fbSizeLocation = glGetUniformLocation(program, "fbSize");
            const GLint textureLocation = glGetUniformLocation(program, "tex");
            if (posLocation < 0 || uvLocation < 0 || fbSizeLocation < 0 || textureLocation < 0) {
                drawFailed = true;
            } else {
                glBindVertexArray(m_vao);
                glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
                glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertices.size() * sizeof(GpuVertex)), vertices.data(), GL_STREAM_DRAW);
                glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ebo);
                glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(indices.size() * sizeof(uint32_t)), indices.data(), GL_STREAM_DRAW);
                glEnableVertexAttribArray(static_cast<GLuint>(posLocation));
                glVertexAttribPointer(static_cast<GLuint>(posLocation), 2, GL_FLOAT, GL_FALSE, sizeof(GpuVertex), nullptr);
                glEnableVertexAttribArray(static_cast<GLuint>(uvLocation));
                glVertexAttribPointer(static_cast<GLuint>(uvLocation), 2, GL_FLOAT, GL_FALSE, sizeof(GpuVertex), reinterpret_cast<void*>(sizeof(float) * 2));

                glUseProgram(program);
                glUniform2f(fbSizeLocation, static_cast<float>(width), static_cast<float>(height));
                glUniform1i(textureLocation, 0);
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, input->m_texID);

                glDisable(GL_SCISSOR_TEST);
                glDisable(GL_DEPTH_TEST);
                glDisable(GL_CULL_FACE);
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
                glClearColor(0.F, 0.F, 0.F, 0.F);
                glClear(GL_COLOR_BUFFER_BIT);
                glEnable(GL_BLEND);
                glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
                glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
                glViewport(0, 0, width, height);
                glDrawElements(GL_TRIANGLES, static_cast<GLsizei>(indices.size()), GL_UNSIGNED_INT, nullptr);
                drawFailed = glGetError() != GL_NO_ERROR;
            }
        }

        if (drawFailed) {
            failRuntime(*m_runtime, "Wobbly mesh draw failed; renderer disabled and original framebuffer retained");
            return in;
        }

        if (m_physics.moving())
            g_pHyprRenderer->damageWindow(m_window.lock(), true);
        return output;
    }

    void amendTransformedRenderData(const CBox&, SMotionBlurData*) override {}

  private:
    bool ensureBuffers() {
        if (m_vao && m_vbo && m_ebo)
            return true;
        glGenVertexArrays(1, &m_vao);
        glGenBuffers(1, &m_vbo);
        glGenBuffers(1, &m_ebo);
        if (!m_vao || !m_vbo || !m_ebo) {
            if (m_ebo)
                glDeleteBuffers(1, &m_ebo);
            if (m_vbo)
                glDeleteBuffers(1, &m_vbo);
            if (m_vao)
                glDeleteVertexArrays(1, &m_vao);
            m_vao = m_vbo = m_ebo = 0;
            failRuntime(*m_runtime, "Wobbly mesh buffer allocation failed; renderer disabled");
            return false;
        }
        return true;
    }

    std::vector<GpuVertex> makeVertices(float framebufferWidth, float framebufferHeight) const {
        const auto width = static_cast<float>(m_box.w);
        const auto height = static_cast<float>(m_box.h);
        if (width <= 1.F || height <= 1.F || framebufferWidth <= 1.F || framebufferHeight <= 1.F)
            return {};

        const auto physicsVertices = m_physics.vertices();
        std::vector<GpuVertex> vertices;
        vertices.reserve(physicsVertices.size());
        for (const auto& vertex : physicsVertices) {
            const float baseX = vertex.u * width;
            const float baseY = vertex.v * height;
            vertices.push_back({
                static_cast<float>(m_box.x) + vertex.x,
                static_cast<float>(m_box.y) + vertex.y,
                (static_cast<float>(m_box.x) + baseX) / framebufferWidth,
                (static_cast<float>(m_box.y) + baseY) / framebufferHeight,
            });
        }
        return vertices;
    }

    std::vector<uint32_t> makeIndices() const {
        const auto& config = m_physics.config();
        std::vector<uint32_t> indices;
        indices.reserve(static_cast<std::size_t>((config.gridX - 1) * (config.gridY - 1) * 6));
        for (int y = 0; y < config.gridY - 1; ++y) {
            for (int x = 0; x < config.gridX - 1; ++x) {
                const auto topLeft = static_cast<uint32_t>(y * config.gridX + x);
                const auto topRight = topLeft + 1;
                const auto bottomLeft = topLeft + static_cast<uint32_t>(config.gridX);
                const auto bottomRight = bottomLeft + 1;
                indices.insert(indices.end(), {topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight});
            }
        }
        return indices;
    }

    WobblyRuntime*                                  m_runtime = nullptr;
    PHLWINDOWREF                                    m_window;
    omanome::wobbly::MeshPhysics                    m_physics;
    CBox                                             m_box;
    std::chrono::steady_clock::time_point            m_lastTick{};
    GLuint                                           m_vao = 0;
    GLuint                                           m_vbo = 0;
    GLuint                                           m_ebo = 0;
    bool                                             m_ready = false;
};

template <typename Pointer>
bool isOmanomeTransformer(const Pointer& transformer) {
    return transformer && dynamic_cast<OmanomeWobblyTransformer*>(transformer.get()) != nullptr;
}

void removeTransformers() {
    if (!Desktop::windowState())
        return;
    for (const auto& window : Desktop::windowState()->windows()) {
        if (!window)
            continue;
        auto& transformers = window->m_transformers;
        transformers.erase(std::remove_if(transformers.begin(), transformers.end(), [](const auto& transformer) {
                               return isOmanomeTransformer(transformer);
                           }),
                           transformers.end());
    }
}

void attachTransformer(WobblyRuntime& runtime, const PHLWINDOW& window) {
    if (!runtime.enabled || !runtime.available || !window || !window->m_isMapped || window->m_isX11)
        return;
    const auto alreadyAttached = std::any_of(window->m_transformers.begin(), window->m_transformers.end(), [](const auto& transformer) {
        return isOmanomeTransformer(transformer);
    });
    if (!alreadyAttached)
        window->m_transformers.emplace_back(makeUnique<OmanomeWobblyTransformer>(&runtime, window));
}

} // namespace omanome::hypr::detail

namespace omanome::hypr {

WobblyManager::WobblyManager() : m_runtime(std::make_unique<detail::WobblyRuntime>()) {
    m_runtime->available = detail::rendererAvailable();
    if (m_runtime->available)
        m_runtime->reason = "public GL IWindowTransformer renderer is available; Wobbly is disabled until explicitly enabled";
}

WobblyManager::~WobblyManager() {
    shutdown();
}

bool WobblyManager::available() const {
    return m_runtime && m_runtime->available && !m_runtime->failed;
}

bool WobblyManager::enabled() const {
    return m_runtime && m_runtime->enabled;
}

bool WobblyManager::enable() {
    if (!m_runtime)
        return false;
    if (m_runtime->enabled)
        return available();
    if (!detail::rendererAvailable()) {
        m_runtime->available = false;
        m_runtime->reason = "Hyprland is not using the supported public GL renderer";
        return false;
    }

    m_runtime->failed = false;
    m_runtime->available = true;
    m_runtime->reason = "public GL IWindowTransformer renderer enabled";
    m_runtime->enabled = true;
    if (Event::bus()) {
        m_runtime->listeners.emplace_back(Event::bus()->m_events.window.open.listen([runtime = m_runtime.get()](PHLWINDOW window) {
            detail::attachTransformer(*runtime, window);
        }));
        m_runtime->listeners.emplace_back(Event::bus()->m_events.window.create.listen([runtime = m_runtime.get()](PHLWINDOW window) {
            detail::attachTransformer(*runtime, window);
        }));
    }
    if (Desktop::windowState()) {
        for (const auto& window : Desktop::windowState()->windows())
            detail::attachTransformer(*m_runtime, window);
    }
    return true;
}

bool WobblyManager::disable() {
    if (!m_runtime)
        return true;
    m_runtime->enabled = false;
    m_runtime->listeners.clear();
    detail::removeTransformers();
    m_runtime->shader.reset();
    return true;
}

void WobblyManager::shutdown() {
    (void)disable();
}

std::size_t WobblyManager::attachedWindows() const {
    if (!m_runtime || !Desktop::windowState())
        return 0;
    std::size_t count = 0;
    for (const auto& window : Desktop::windowState()->windows()) {
        if (!window)
            continue;
        count += static_cast<std::size_t>(std::count_if(window->m_transformers.begin(), window->m_transformers.end(), [](const auto& transformer) {
            return detail::isOmanomeTransformer(transformer);
        }));
    }
    return count;
}

const std::string& WobblyManager::reason() const {
    static const std::string unavailable = "companion runtime is unavailable";
    return m_runtime ? m_runtime->reason : unavailable;
}

} // namespace omanome::hypr
