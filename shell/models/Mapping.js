// Device/output mapping is pure state preparation. The service applies the
// returned plan as one compositor transaction and can roll it back safely.

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function array(value) {
  return Array.isArray(value) ? value : []
}

function text(value) {
  return String(value === undefined || value === null ? "" : value)
}

function safeName(value) {
  return text(value).replace(/[;,\n\r]/g, "").trim()
}

function stableId(device) {
  var item = object(device)
  return safeName(item.id || item.identifier || item.path || item.name || "unknown-device")
}

function outputId(output) {
  var item = object(output)
  return safeName(item.name || item.id || item.identifier || output)
}

function availableOutputs(outputs) {
  var list = array(outputs)
  var result = []
  for (var i = 0; i < list.length; i++) {
    var id = outputId(list[i])
    if (id && result.indexOf(id) < 0) result.push(id)
  }
  return result
}

function chooseOutput(device, outputs, configured, fallback) {
  var item = object(device)
  var available = availableOutputs(outputs)
  var wanted = safeName(configured || item.output || item.mappedOutput || item.mapped_output || "")
  if (wanted && available.indexOf(wanted) >= 0) return { output: wanted, reason: "configured" }
  if (wanted && available.length > 0) return { output: available[0], reason: "configured-output-disconnected" }
  var preferred = safeName(fallback || "")
  if (preferred && available.indexOf(preferred) >= 0) return { output: preferred, reason: "fallback" }
  if (available.length > 0) return { output: available[0], reason: "first-available-output" }
  return { output: "", reason: "no-output" }
}

function normalizeDevice(device, outputs, configured, fallback) {
  var item = object(device)
  var selected = chooseOutput(item, outputs, configured, fallback)
  return {
    id: stableId(item),
    role: safeName(item.role || item.type || "input"),
    output: selected.output,
    reason: selected.reason,
    present: item.present !== false,
    transform: Math.max(0, Math.min(3, Math.floor(Number(item.transform || 0))))
  }
}

function plan(devices, outputs, mappings, fallback) {
  var configured = object(mappings)
  var list = array(devices)
  var result = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}
    var id = stableId(item)
    var value = configured[id]
    if (value && typeof value === "object") value = value.output || value.monitor
    result.push(normalizeDevice(item, outputs, value, fallback))
  }
  return result
}

function rotation(value) {
  var number = Number(value)
  return isFinite(number) ? Math.max(0, Math.min(3, Math.floor(number))) : 0
}

function transaction(previous, requested, devices, monitors) {
  var old = object(previous)
  return {
    schemaVersion: 1,
    phase: "prepared",
    requested: rotation(requested),
    previous: rotation(old.transform),
    devices: array(devices).slice(),
    monitors: array(monitors).slice(),
    rollbackAvailable: true,
    error: ""
  }
}

function apply(transactionState, success, error) {
  var source = object(transactionState)
  if (success !== true) {
    return {
      schemaVersion: 1,
      phase: "rollback-required",
      requested: rotation(source.requested),
      previous: rotation(source.previous),
      devices: array(source.devices).slice(),
      monitors: array(source.monitors).slice(),
      rollbackAvailable: true,
      error: text(error || "mapping-apply-failed")
    }
  }
  var next = Object.assign({}, source)
  next.phase = "applied"
  next.error = ""
  return next
}

function commit(transactionState) {
  var source = object(transactionState)
  if (source.phase !== "applied") return Object.assign({}, source, { phase: "commit-rejected", error: "mapping-not-applied" })
  return Object.assign({}, source, { phase: "committed", rollbackAvailable: false, error: "" })
}

function rollback(transactionState, error) {
  var source = object(transactionState)
  return Object.assign({}, source, {
    phase: "rolled-back",
    requested: rotation(source.previous),
    rollbackAvailable: false,
    error: text(error || source.error || "mapping-rolled-back")
  })
}

function explain(rows) {
  var list = array(rows)
  return list.map(function(item) {
    var row = object(item)
    return safeName(row.id) + " -> " + (safeName(row.output) || "automatic") + " (" + safeName(row.reason || "unresolved") + ")"
  })
}

var api = {
  stableId: stableId,
  availableOutputs: availableOutputs,
  chooseOutput: chooseOutput,
  normalizeDevice: normalizeDevice,
  plan: plan,
  transaction: transaction,
  apply: apply,
  commit: commit,
  rollback: rollback,
  explain: explain
}
if (typeof module !== "undefined") module.exports = api
