function numericIds(values) {
  var seen = {}
  var result = []
  var list = Array.isArray(values) ? values : []
  for (var i = 0; i < list.length; i++) {
    var id = Number(list[i] && list[i].id !== undefined ? list[i].id : list[i])
    if (!isFinite(id) || id <= 0 || seen[id]) continue
    seen[id] = true
    result.push(Math.floor(id))
  }
  result.sort(function(left, right) { return left - right })
  return result
}

function occupied(workspace) {
  if (!workspace) return false
  if (workspace.toplevels && Array.isArray(workspace.toplevels.values)) return workspace.toplevels.values.length > 0
  if (Array.isArray(workspace.windows)) return workspace.windows.length > 0
  return Number(workspace.windows || workspace.toplevelCount || 0) > 0
}

function ids(values, mode, fixedCount) {
  var list = Array.isArray(values) ? values : []
  var result = numericIds(list)
  var requested = Math.max(1, Number(fixedCount || 5))
  if (String(mode || "dynamic") === "fixed") {
    result = []
    for (var fixed = 1; fixed <= requested; fixed++) result.push(fixed)
    return result
  }

  if (result.length === 0) result.push(1)
  var byId = {}
  for (var i = 0; i < list.length; i++) {
    var id = Number(list[i] && list[i].id !== undefined ? list[i].id : list[i])
    if (isFinite(id)) byId[Math.floor(id)] = list[i]
  }
  var highestOccupied = 0
  for (var r = 0; r < result.length; r++) {
    if (occupied(byId[result[r]])) highestOccupied = Math.max(highestOccupied, result[r])
  }
  if (highestOccupied === 0) return [1]

  // Keep existing ids through the last occupied workspace and exactly one
  // empty workspace after it, matching GNOME's dynamic-workspace invariant.
  var dynamic = []
  var boundary = highestOccupied + 1
  for (var d = 0; d < result.length; d++) if (result[d] <= boundary) dynamic.push(result[d])
  if (dynamic.indexOf(boundary) < 0) dynamic.push(boundary)
  return dynamic
}

function focusCommand(id) {
  var value = Math.max(1, Math.floor(Number(id || 1)))
  return "workspace " + value
}

function moveCommand(id) {
  var value = Math.max(1, Math.floor(Number(id || 1)))
  return "movetoworkspace " + value
}

function adjacent(id, direction, available) {
  var current = Math.floor(Number(id || 1))
  var step = String(direction || "right") === "left" ? -1 : 1
  var list = numericIds(available)
  var index = list.indexOf(current)
  if (index < 0) return Math.max(1, current + step)
  return list[Math.max(0, Math.min(list.length - 1, index + step))]
}

var api = { numericIds: numericIds, ids: ids, focusCommand: focusCommand, moveCommand: moveCommand, adjacent: adjacent }
if (typeof module !== "undefined") module.exports = api
