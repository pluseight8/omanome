// Semantic icon names for Omanome surfaces.
//
// The glyphs intentionally stay in the host's text/icon font vocabulary. The
// adapter removes per-view Unicode decisions while keeping a readable fallback
// when a future theme does not ship the preferred icon font.

var GLYPHS = {
  overview: "▦",
  launcher: "⌘",
  quickSettings: "☷",
  keyboard: "⌨",
  clipboard: "▣",
  notifications: "◌",
  switcher: "⇄",
  settings: "⚙",
  devices: "⌁",
  close: "×",
  refresh: "↻",
  expand: "+",
  collapse: "−",
  confirm: "✓",
  cancel: "×",
  play: "▶",
  pause: "Ⅱ",
  back: "‹",
  forward: "›",
  open: "↗",
  minimize: "—",
  maximize: "□",
  fullscreen: "⛶",
  snap: "⌗",
  split: "⧉",
  touch: "●",
  desktop: "○",
  stylus: "✎",
  power: "⏻",
  warning: "!"
}

function glyph(name, fallback) {
  var key = String(name || "")
  return GLYPHS[key] || String(fallback || "•")
}

var api = { GLYPHS: GLYPHS, glyph: glyph }
if (typeof module !== "undefined") module.exports = api
