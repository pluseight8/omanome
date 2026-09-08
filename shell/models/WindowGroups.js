// Bounded metadata for Omanome-managed window groups.  A group remembers
// applications, layout intent, and user preferences; compositor identities
// live only in the runtime field and are never part of persistent metadata.

var GROUPS_SCHEMA_VERSION = 1
var MAX_GROUPS = 32
var MAX_MEMBERS = 4
var MAX_TEXT = 96
var TYPES = ["split-pair", "workspace-group", "app-pair"]
var RESTORE_POLICIES = ["off", "ask", "automatic"]
var MONITOR_POLICIES = ["active", "original", "ask", "per-app"]
var WORKSPACE_POLICIES = ["active", "original", "ask"]
var CLOSE_POLICIES = ["keep", "expand", "ask"]
var DUPLICATE_POLICIES = ["ask", "first"]

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {}
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function text(value, fallback, limit) {
  var result = String(value === undefined || value === null ? (fallback || "") : value).trim()
  return result.slice(0, Math.max(1, Number(limit || MAX_TEXT)))
}

function number(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : Number(fallback || 0)
}

function boundedTime(value) {
  var result = Math.round(number(value, 0))
  return result > 0 ? result : 0
}

function list(value) {
  return Array.isArray(value) ? value : []
}

function unique(values, limit) {
  var seen = {}
  var result = []
  var source = list(values)
  var max = Math.max(0, Number(limit || MAX_MEMBERS))
  for (var i = 0; i < source.length && result.length < max; i++) {
    var value = text(source[i], "", MAX_TEXT)
    if (!value || seen[value]) continue
    seen[value] = true
    result.push(value)
  }
  return result
}

function normalizeAppId(value) {
  var result = text(value, "", 256)
  if (result.slice(-8) === ".desktop") result = result.slice(0, -8)
  return result
}

function appId(window) {
  if (typeof window === "string") return normalizeAppId(window)
  var item = object(window && window.wayland ? window.wayland : window)
  return normalizeAppId(item.appId || item.app_id || item.desktopId || item.desktopFile || item.class || item.initialClass || item.windowClass)
}

function runtimeIdentity(window) {
  if (typeof window === "string") {
    var value = text(window, "", MAX_TEXT)
    return value.indexOf("address:") === 0 || value.indexOf("pid:") === 0 ? value : ""
  }
  var item = object(window && window.wayland ? window.wayland : window)
  var identity = text(item.identity, "", MAX_TEXT)
  if (identity.indexOf("address:") === 0 || identity.indexOf("pid:") === 0) return identity
  var address = text(item.address, "", MAX_TEXT)
  if (/^[0-9a-fA-Fx]+$/.test(address)) return "address:" + address
  var pid = Math.round(number(item.pid, 0))
  return pid > 0 ? "pid:" + pid : ""
}

function workspaceId(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  var workspace = item.workspace
  if (workspace && typeof workspace === "object") workspace = workspace.id !== undefined ? workspace.id : workspace.name
  if (workspace === undefined || workspace === null || workspace === "") workspace = item.workspaceId
  return text(workspace, "", 64)
}

function monitorName(window) {
  var item = object(window && window.wayland ? window.wayland : window)
  return text(item.monitorName || item.monitor || item.output, "", 128)
}

function normalizeType(value) {
  var result = text(value, "split-pair", 32).toLowerCase()
  if (result === "split" || result === "split_pair") result = "split-pair"
  if (result === "workspace" || result === "workspace_group") result = "workspace-group"
  if (result === "pair") result = "app-pair"
  return TYPES.indexOf(result) >= 0 ? result : "split-pair"
}

function normalizeChoice(value, values, fallback) {
  var result = text(value, fallback, 32).toLowerCase()
  return values.indexOf(result) >= 0 ? result : fallback
}

function normalizeRatio(value) {
  var result = text(value, "50/50", 16).replace(/\s+/g, "")
  if (["50/50", "40/60", "60/40", "33/67", "67/33"].indexOf(result) >= 0) return result
  var numeric = Number(value)
  if (isFinite(numeric)) {
    numeric = Math.max(0.25, Math.min(0.75, numeric))
    return Math.round(numeric * 100) + "/" + Math.round((1 - numeric) * 100)
  }
  return "50/50"
}

function normalizeSlot(value, index, fallbackApp) {
  var source = object(value)
  var application = normalizeAppId(source.appId || source.application || source.desktopId || fallbackApp)
  return {
    id: text(source.id, "slot-" + (index + 1), 64),
    appId: application,
    zoneId: text(source.zoneId || source.zone || source.layoutZone, "", 64),
    order: Math.max(0, Math.min(MAX_MEMBERS - 1, Math.round(number(source.order, index))))
  }
}

function normalizeLayout(value, apps) {
  var source = object(value)
  var applications = unique(list(apps).map(normalizeAppId), MAX_MEMBERS)
  var slots = []
  var sourceSlots = list(source.slots)
  for (var i = 0; i < sourceSlots.length && slots.length < MAX_MEMBERS; i++) {
    var slot = normalizeSlot(sourceSlots[i], i, applications[i] || "")
    if (!slot.appId && applications[i]) slot.appId = applications[i]
    slots.push(slot)
  }
  for (var appIndex = slots.length; appIndex < applications.length && slots.length < MAX_MEMBERS; appIndex++)
    slots.push(normalizeSlot({}, slots.length, applications[appIndex]))
  return {
    type: text(source.type, "split", 32).toLowerCase() || "split",
    id: text(source.id || source.layoutId, "split", 64),
    orientation: normalizeChoice(source.orientation, ["auto", "landscape", "portrait"], "auto"),
    ratio: normalizeRatio(source.ratio || source.ratioName),
    slots: slots
  }
}

function normalizePreferences(value) {
  var source = object(value)
  return {
    workspacePolicy: normalizeChoice(source.workspacePolicy, WORKSPACE_POLICIES, "active"),
    monitorPolicy: normalizeChoice(source.monitorPolicy, MONITOR_POLICIES, "active"),
    closePolicy: normalizeChoice(source.closePolicy, CLOSE_POLICIES, "keep"),
    duplicatePolicy: normalizeChoice(source.duplicatePolicy, DUPLICATE_POLICIES, "ask"),
    autoLaunch: source.autoLaunch === true,
    enabled: source.enabled !== false,
    targetWorkspace: text(source.targetWorkspace || source.workspaceId, "", 64),
    originalMonitor: text(source.originalMonitor || source.monitorName, "", 128)
  }
}

function normalizeRuntime(value) {
  var source = object(value)
  var members = []
  var seen = {}
  var sourceMembers = list(source.members)
  for (var i = 0; i < sourceMembers.length && members.length < MAX_MEMBERS; i++) {
    var item = object(sourceMembers[i])
    var identity = runtimeIdentity(item)
    if (!identity || seen[identity]) continue
    seen[identity] = true
    members.push({
      identity: identity,
      appId: appId(item),
      workspaceId: workspaceId(item),
      monitorName: monitorName(item)
    })
  }
  var ids = unique(list(source.memberIds).filter(function(value) {
    var id = runtimeIdentity(String(value))
    return id !== ""
  }).map(function(value) { return runtimeIdentity(String(value)) }), MAX_MEMBERS)
  for (var idIndex = 0; idIndex < ids.length && members.length < MAX_MEMBERS; idIndex++) {
    var known = members.some(function(item) { return item.identity === ids[idIndex] })
    if (!known) members.push({ identity: ids[idIndex], appId: "", workspaceId: "", monitorName: "" })
  }
  return {
    status: text(source.status, "idle", 32),
    memberIds: members.map(function(item) { return item.identity }),
    members: members,
    lastReconciledAt: boundedTime(source.lastReconciledAt),
    lastEvent: text(source.lastEvent, "", 64)
  }
}

function groupName(type, apps) {
  if (type === "app-pair" && apps.length >= 2) return apps[0] + " + " + apps[1]
  if (type === "workspace-group") return "Workspace group"
  return "Split pair"
}

function normalizeGroup(value, index) {
  var source = object(value)
  var type = normalizeType(source.type)
  var runtime = normalizeRuntime(source.runtime)
  var configuredApps = Array.isArray(source.apps) && source.apps.length > 0 ? source.apps : source.appIds
  var apps = unique(list(configuredApps).concat(runtime.members.map(function(item) { return item.appId })).concat(list(source.layout && source.layout.slots).map(function(item) { return item && item.appId })), MAX_MEMBERS)
  var layout = normalizeLayout(source.layout, apps)
  apps = unique(apps.concat(layout.slots.map(function(item) { return item.appId })), MAX_MEMBERS)
  var id = text(source.id, "group-" + (Number(index || 0) + 1), MAX_TEXT)
  return {
    schemaVersion: GROUPS_SCHEMA_VERSION,
    id: id,
    type: type,
    name: text(source.name, groupName(type, apps), MAX_TEXT),
    apps: apps,
    layout: layout,
    preferences: normalizePreferences(source.preferences || source),
    createdAt: boundedTime(source.createdAt),
    updatedAt: boundedTime(source.updatedAt),
    order: Math.max(0, Math.min(MAX_GROUPS - 1, Math.round(number(source.order, index || 0)))),
    persistent: source.persistent !== false,
    runtime: runtime
  }
}

function metadata(group, index) {
  var source = normalizeGroup(group, index || 0)
  return {
    schemaVersion: GROUPS_SCHEMA_VERSION,
    id: source.id,
    type: source.type,
    name: source.name,
    apps: source.apps.slice(0, MAX_MEMBERS),
    layout: clone(source.layout),
    preferences: clone(source.preferences),
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
    order: source.order,
    persistent: source.persistent !== false
  }
}

function normalizeList(values) {
  var source = Array.isArray(values) ? values : []
  var result = []
  var seen = {}
  for (var i = 0; i < source.length && result.length < MAX_GROUPS; i++) {
    var item = normalizeGroup(source[i], i)
    if (!item.id || seen[item.id]) continue
    seen[item.id] = true
    result.push(item)
  }
  return result
}

function createGroup(type, windows, options, now) {
  var settings = object(options)
  var normalizedType = normalizeType(type || settings.type)
  var rows = list(windows)
  var members = []
  var identities = {}
  for (var i = 0; i < rows.length && members.length < MAX_MEMBERS; i++) {
    var identity = runtimeIdentity(rows[i])
    if (!identity || identities[identity]) continue
    identities[identity] = true
    members.push({ identity: identity, appId: appId(rows[i]), workspaceId: workspaceId(rows[i]), monitorName: monitorName(rows[i]) })
  }
  var apps = unique(list(settings.apps || settings.appIds).concat(members.map(function(item) { return item.appId })), MAX_MEMBERS)
  if (normalizedType === "app-pair" && apps.length < 2)
    return { ok: false, reason: "two-application-identities-required" }
  if (normalizedType !== "app-pair" && members.length < 2)
    return { ok: false, reason: "two-window-identities-required" }
  var timestamp = boundedTime(now === undefined ? settings.now : now)
  var id = text(settings.id, "group-" + (timestamp || 0) + "-" + (members.length || apps.length), MAX_TEXT)
  var preferences = normalizePreferences(settings.preferences || settings)
  var layout = normalizeLayout(settings.layout || {
    id: settings.layoutId,
    type: settings.layoutType,
    orientation: settings.orientation,
    ratio: settings.ratio || settings.ratioName
  }, apps)
  var group = normalizeGroup({
    id: id,
    type: normalizedType,
    name: settings.name,
    apps: apps,
    layout: layout,
    preferences: preferences,
    createdAt: timestamp,
    updatedAt: timestamp,
    order: settings.order,
    runtime: { status: members.length > 0 ? "active" : "idle", members: members, lastReconciledAt: timestamp }
  }, 0)
  return { ok: true, group: group, metadata: metadata(group, 0) }
}

function snapshot(group, index) {
  return metadata(group, index || 0)
}

function metadataList(values) {
  return normalizeList(values).map(function(item, index) { return metadata(item, index) })
}

function serialize(values) {
  var groups = metadataList(values)
  return JSON.stringify({ schemaVersion: GROUPS_SCHEMA_VERSION, groups: groups })
}

function restore(raw) {
  var parsed = raw
  if (typeof raw === "string") {
    try { parsed = JSON.parse(raw) } catch (error) { return { ok: false, reason: "invalid-json", groups: [] } }
  }
  if (Array.isArray(parsed)) parsed = { schemaVersion: GROUPS_SCHEMA_VERSION, groups: parsed }
  if (!object(parsed).groups || !Array.isArray(parsed.groups)) return { ok: false, reason: "invalid-groups-root", groups: [] }
  var version = Number(parsed.schemaVersion === undefined ? GROUPS_SCHEMA_VERSION : parsed.schemaVersion)
  if (!isFinite(version) || version < 1 || version > GROUPS_SCHEMA_VERSION)
    return { ok: false, reason: version > GROUPS_SCHEMA_VERSION ? "future-schema" : "invalid-schema-version", groups: [] }
  var groups = normalizeList(parsed.groups).map(function(item, index) { return metadata(item, index) })
  return { ok: true, schemaVersion: GROUPS_SCHEMA_VERSION, groups: groups, discarded: Math.max(0, parsed.groups.length - groups.length) }
}

function indexWindows(windows) {
  var byIdentity = {}
  var byApp = {}
  var rows = list(windows)
  for (var i = 0; i < rows.length; i++) {
    var identity = runtimeIdentity(rows[i])
    var application = appId(rows[i])
    if (identity) byIdentity[identity] = { identity: identity, appId: application, workspaceId: workspaceId(rows[i]), monitorName: monitorName(rows[i]) }
    if (application) {
      if (!byApp[application]) byApp[application] = []
      byApp[application].push({ identity: identity, appId: application, workspaceId: workspaceId(rows[i]), monitorName: monitorName(rows[i]) })
    }
  }
  return { byIdentity: byIdentity, byApp: byApp }
}

function expectedApps(group) {
  var source = normalizeGroup(group, 0)
  var slots = source.layout.slots
  var apps = slots.map(function(item) { return item.appId }).filter(Boolean)
  return apps.length > 0 ? apps : source.apps.slice()
}

function reconcileGroup(group, windows, now, options) {
  var source = normalizeGroup(group, 0)
  var settings = object(options)
  var indexes = indexWindows(windows)
  var bound = []
  var missing = []
  var ambiguous = []
  var used = {}
  var runtimeMembers = source.runtime.members
  var hasRuntime = runtimeMembers.length > 0
  var duplicatePolicy = normalizeChoice(settings.duplicatePolicy || source.preferences.duplicatePolicy, DUPLICATE_POLICIES, "ask")

  function addBound(item) {
    if (!item || !item.identity || used[item.identity]) return
    used[item.identity] = true
    bound.push(item)
  }

  function chooseCandidates(application, required, label) {
    var candidates = (indexes.byApp[application] || []).filter(function(item) { return item.identity && !used[item.identity] })
    if (candidates.length === 0) { missing.push({ key: label || application, appId: application, required: required || 1 }); return }
    if (candidates.length > 1 && duplicatePolicy !== "first") {
      ambiguous.push({ key: label || application, appId: application, count: candidates.length, required: required || 1 })
      return
    }
    addBound(candidates[0])
  }

  if (hasRuntime) {
    for (var i = 0; i < runtimeMembers.length; i++) {
      var member = runtimeMembers[i]
      var exact = indexes.byIdentity[member.identity]
      if (exact) { addBound(exact); continue }
      if (member.appId) chooseCandidates(member.appId, 1, member.identity)
      else missing.push({ key: member.identity, appId: "", required: 1 })
    }
  } else {
    var apps = expectedApps(source)
    for (var appIndex = 0; appIndex < apps.length; appIndex++) chooseCandidates(apps[appIndex], 1, "app:" + apps[appIndex])
  }

  var expectedCount = hasRuntime ? runtimeMembers.length : expectedApps(source).length
  var status = "idle"
  if (ambiguous.length > 0) status = "ambiguous"
  else if (missing.length > 0) status = hasRuntime && source.type !== "app-pair" ? "broken" : "partial"
  else if (bound.length > 0 && bound.length >= expectedCount) status = "active"
  var next = clone(source)
  next.runtime = {
    status: status,
    memberIds: bound.map(function(item) { return item.identity }).slice(0, MAX_MEMBERS),
    members: bound.slice(0, MAX_MEMBERS),
    lastReconciledAt: boundedTime(now),
    lastEvent: status === "broken" ? "member-closed" : (status === "ambiguous" ? "duplicate-window-choice-required" : "reconciled")
  }
  var event = null
  if (status === "broken") event = { type: "break", groupId: source.id, reason: "member-closed", closePolicy: source.preferences.closePolicy, remaining: bound.map(function(item) { return item.identity }) }
  if (status === "partial" && source.type === "app-pair") event = { type: "partial", groupId: source.id, reason: "application-missing", missing: missing.map(function(item) { return item.appId || item.key }) }
  return { ok: true, group: next, status: status, bound: bound, missing: missing, ambiguous: ambiguous, event: event }
}

function reconcile(groups, windows, now, options) {
  var source = normalizeList(groups)
  var events = []
  var changed = false
  var result = source.map(function(group) {
    var outcome = reconcileGroup(group, windows, now, options)
    if (JSON.stringify(group.runtime) !== JSON.stringify(outcome.group.runtime)) changed = true
    if (outcome.event) events.push(outcome.event)
    return outcome.group
  })
  return { ok: true, groups: result, events: events, changed: changed }
}

function breakRuntime(group, reason) {
  var source = normalizeGroup(group, 0)
  source.runtime = { status: "broken", memberIds: [], members: [], lastReconciledAt: 0, lastEvent: text(reason, "manual-break", 64) }
  return source
}

function removeGroup(groups, groupId) {
  var key = text(groupId, "", MAX_TEXT)
  return normalizeList(groups).filter(function(item) { return item.id !== key })
}

function detachMember(group, identity, reason) {
  var source = normalizeGroup(group, 0)
  var key = runtimeIdentity(String(identity || ""))
  var members = source.runtime.members.filter(function(item) { return item.identity !== key })
  var next = clone(source)
  next.runtime = {
    status: members.length >= 2 ? "active" : "broken",
    memberIds: members.map(function(item) { return item.identity }),
    members: members,
    lastReconciledAt: source.runtime.lastReconciledAt,
    lastEvent: text(reason, "member-detached", 64)
  }
  return { ok: source.runtime.members.length !== members.length, group: next, broken: members.length < 2, remaining: members }
}

function movePlan(group, workspace, monitor) {
  var source = normalizeGroup(group, 0)
  var workspaceValue = text(workspace, "", 64)
  var monitorValue = text(monitor, "", 128)
  if (!workspaceValue && !monitorValue) return { ok: false, reason: "move-target-required" }
  if (source.runtime.memberIds.length === 0) return { ok: false, reason: "runtime-members-unavailable" }
  return {
    ok: true,
    groupId: source.id,
    memberIds: source.runtime.memberIds.slice(),
    workspaceId: workspaceValue,
    monitorName: monitorValue,
    closePolicy: source.preferences.closePolicy
  }
}

function updatePlacement(group, workspace, monitor, now) {
  var source = normalizeGroup(group, 0)
  var next = clone(source)
  var workspaceValue = text(workspace, "", 64)
  var monitorValue = text(monitor, "", 128)
  next.preferences.targetWorkspace = workspaceValue || next.preferences.targetWorkspace
  if (monitorValue) next.preferences.originalMonitor = monitorValue
  next.updatedAt = boundedTime(now)
  next.runtime.members = next.runtime.members.map(function(item) {
    var value = clone(item)
    if (workspaceValue) value.workspaceId = workspaceValue
    if (monitorValue) value.monitorName = monitorValue
    return value
  })
  return next
}

function restorePolicy(value) {
  return normalizeChoice(value, RESTORE_POLICIES, "ask")
}

function restoreDecision(policy, context) {
  var value = restorePolicy(policy)
  var state = object(context)
  if (state.safeMode === true) return { policy: value, allowed: false, requiresConfirmation: false, autoLaunch: false, reason: "safe-mode" }
  if (value === "off") return { policy: value, allowed: false, requiresConfirmation: false, autoLaunch: false, reason: "disabled" }
  if (value === "ask") return { policy: value, allowed: false, requiresConfirmation: true, autoLaunch: false, reason: "confirmation-required" }
  return { policy: value, allowed: true, requiresConfirmation: false, autoLaunch: true, reason: "automatic-policy" }
}

function restorePlan(groups, windows, policy, now, context) {
  var decision = restoreDecision(policy, context)
  var reconciled = reconcile(groups, windows, now, context)
  var plans = []
  for (var i = 0; i < reconciled.groups.length; i++) {
    var group = reconciled.groups[i]
    var state = reconcileGroup(group, windows, now, context)
    if (state.status === "active") continue
    var missingApps = state.missing.map(function(item) { return item.appId }).filter(Boolean)
    if (!decision.allowed) {
      plans.push({ groupId: group.id, status: decision.requiresConfirmation ? "awaiting-confirmation" : "skipped", missingApps: unique(missingApps, MAX_MEMBERS), reason: decision.reason })
      continue
    }
    plans.push({ groupId: group.id, status: "ready", missingApps: unique(missingApps, MAX_MEMBERS), reason: state.status })
  }
  return { ok: true, decision: decision, groups: reconciled.groups, events: reconciled.events, plans: plans.slice(0, MAX_GROUPS) }
}

var api = {
  GROUPS_SCHEMA_VERSION: GROUPS_SCHEMA_VERSION,
  MAX_GROUPS: MAX_GROUPS,
  MAX_MEMBERS: MAX_MEMBERS,
  TYPES: TYPES,
  RESTORE_POLICIES: RESTORE_POLICIES,
  normalizeAppId: normalizeAppId,
  appId: appId,
  runtimeIdentity: runtimeIdentity,
  normalizeGroup: normalizeGroup,
  normalizeList: normalizeList,
  createGroup: createGroup,
  snapshot: snapshot,
  metadataList: metadataList,
  serialize: serialize,
  restore: restore,
  expectedApps: expectedApps,
  reconcileGroup: reconcileGroup,
  reconcile: reconcile,
  breakRuntime: breakRuntime,
  removeGroup: removeGroup,
  detachMember: detachMember,
  movePlan: movePlan,
  updatePlacement: updatePlacement,
  restorePolicy: restorePolicy,
  restoreDecision: restoreDecision,
  restorePlan: restorePlan
}
if (typeof module !== "undefined") module.exports = api
