function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function clamp(value, minimum, maximum) {
  return Math.max(Number(minimum), Math.min(Number(maximum), Number(value)))
}

function aspect(window) {
  var item = window || {}
  var size = item.size || item.geometry || {}
  var width = number(size.width || item.width, 16)
  var height = number(size.height || item.height, 9)
  return clamp(width / Math.max(1, height), 0.55, 2.4)
}

function fit(cellX, cellY, cellWidth, cellHeight, ratio) {
  var width = Math.min(cellWidth, cellHeight * ratio)
  var height = Math.min(cellHeight, width / ratio)
  return {
    x: Math.round(cellX + (cellWidth - width) / 2),
    y: Math.round(cellY + (cellHeight - height) / 2),
    width: Math.max(1, Math.round(width)),
    height: Math.max(1, Math.round(height))
  }
}

// Deterministic mosaic: cards receive stable row-major cells, while their
// inner rectangle keeps the window aspect ratio instead of stretching every
// client into an identical poster tile.
function rects(windows, width, height, gap) {
  var list = Array.isArray(windows) ? windows : []
  var availableWidth = Math.max(1, number(width, 1))
  var availableHeight = Math.max(1, number(height, 1))
  var spacing = Math.max(6, number(gap, 14))
  var count = list.length
  if (count === 0) return []
  var columns = count === 1 ? 1 : Math.max(1, Math.ceil(Math.sqrt(count * availableWidth / availableHeight)))
  columns = Math.min(columns, count)
  var rows = Math.max(1, Math.ceil(count / columns))
  var cellWidth = (availableWidth - spacing * (columns - 1)) / columns
  var cellHeight = (availableHeight - spacing * (rows - 1)) / rows
  var result = []
  for (var i = 0; i < count; i++) {
    var column = i % columns
    var row = Math.floor(i / columns)
    var x = column * (cellWidth + spacing)
    var y = row * (cellHeight + spacing)
    result.push(fit(x, y, cellWidth, cellHeight, aspect(list[i])))
  }
  return result
}

var api = { aspect: aspect, fit: fit, rects: rects }
if (typeof module !== "undefined") module.exports = api
