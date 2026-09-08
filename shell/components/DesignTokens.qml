import QtQuick
import qs.Commons
import "../models/Responsive.js" as Responsive

// One small, host-theme-aware token surface shared by Omanome views. The
// actual palette remains Omarchy's palette; this component only adds density,
// logical-size and accessibility decisions on top of it.
QtObject {
  id: root

  property var service: null
  property real viewportWidth: 1280
  property real viewportHeight: 720
  property real viewportScale: 1
  property string transitionComponent: "settings"
  property string inputKind: service ? String(service.lastInput || "keyboard") : "keyboard"
  property string mode: service ? String(service.effectiveMode || service.detectedMode || "desktop") : "desktop"
  property bool largeUi: service ? service.cfg("general.largeUi", false) === true : false
  property string touchTargetSize: service ? String(service.cfg("accessibility.touchTargetSize", "default")) : "default"
  property real textScale: service ? Number(service.cfg("accessibility.textScale", 1)) : 1
  property bool reducedMotion: service ? (service.cfg("general.reduceMotion", false) === true || service.cfg("accessibility.reducedMotion", false) === true) : false
  property bool reduceTransparency: service ? service.cfg("accessibility.reduceTransparency", false) === true : false
  property bool highContrast: service ? service.cfg("accessibility.highContrast", false) === true : false
  readonly property var context: Responsive.context(viewportWidth, viewportHeight, viewportScale, inputKind, mode, {
    largeUi: largeUi,
    touchTargetSize: touchTargetSize,
    textScale: textScale,
    reducedMotion: reducedMotion,
    reduceTransparency: reduceTransparency,
    highContrast: highContrast
  })
  readonly property string breakpoint: String(context.breakpoint || "desktop")
  readonly property string orientation: String(context.orientation || "landscape")
  readonly property bool touchLike: context.touchLike === true
  readonly property real densityScale: Number(context.densityScale || 1)
  readonly property real targetSize: Number(context.targetSize || 44)
  readonly property var transition: service && typeof service.componentTransition === "function"
                                      ? service.componentTransition(transitionComponent) : ({ active: false, progress: 1, fromMode: mode, toMode: mode, reduceMotion: reducedMotion, reason: "not-available" })
  readonly property real transitionProgress: Math.max(0, Math.min(1, Number(transition.progress || 0)))
  readonly property real transitionedTargetSize: {
    var from = String(transition.fromMode || mode)
    var to = String(transition.toMode || mode)
    function sizeFor(value) {
      if (value === "tablet") return 52
      if (value === "hybrid") return 48
      return 40
    }
    if (!transition.active || from === to) return targetSize
    return Math.max(targetSize, sizeFor(from) + (sizeFor(to) - sizeFor(from)) * transitionProgress)
  }

  function space(value) { return Style.space(Math.max(0, Number(value || 0)) * densityScale) }
  function radius(value) { return Style.space(Math.max(0, Number(value || 0)) * Math.min(1.08, densityScale)) }
  function duration(value) {
    if (reducedMotion) return 0
    return Math.max(0, Math.round(Number(value || 0) * Number(service ? service.cfg("animations.durationScale", 1) : 1)))
  }
  function target(value) { return Style.space(Math.max(Number(value || 0), transitionedTargetSize)) }
}
