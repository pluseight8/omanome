var modes = [
  "standard",
  "floating",
  "split",
  "thumb",
  "one-handed-left",
  "one-handed-right",
  "numeric",
  "symbols",
  "emoji",
  "handwriting"
]

var english = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["Caps", "Shift", "z", "x", "c", "v", "b", "n", "m", "Backspace"],
  ["123", "@", "#", "Space", ".", ",", "Enter"]
]

var russian = [
  ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
  ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
  ["Caps", "Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "Backspace"],
  ["123", "@", "№", "Space", ".", ",", "Enter"]
]

var numeric = [
  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
  ["-", "/", ":", ";", "(", ")", "$", "&", "\""],
  ["ABC", "'", "?", "!", "#", "%", "Backspace"],
  ["ABC", "Space", ".", ",", "Enter"]
]

var symbols = [
  ["~", "`", "|", "•", "√", "π", "÷", "×", "¶", "∆"],
  ["°", "€", "£", "¥", "₽", "¢", "©", "®", "™", "✓"],
  ["ABC", "[", "]", "{", "}", "<", ">", "\\", "Backspace"],
  ["123", "Space", ".", ",", "Enter"]
]

var functionKeys = [
  ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
  ["←", "↑", "↓", "→", "Home", "End", "PageUp", "PageDown"],
  ["ABC", "Tab", "Space", "Enter"]
]

var editing = [
  ["←", "→", "↑", "↓"],
  ["Home", "End", "SelectAll", "Copy", "Cut", "Paste"],
  ["Undo", "Redo", "Backspace", "Enter"]
]

var emojiGroups = [
  {
    id: "recent",
    label: "Recent",
    items: ["😀", "😂", "😊", "😍", "🤔", "👍", "👎", "🙏", "🎉", "❤️", "🔥", "✅"]
  },
  {
    id: "smileys",
    label: "Smileys",
    items: ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "🤗", "🤔", "🤐", "🤨", "😐", "😑", "😶", "🙄", "😏", "😣", "😥", "😮", "🤐", "😯", "😪", "😫", "🥱", "😴", "😌", "🤓", "😎", "🥳", "🤩", "😭", "😡", "🤯"]
  },
  {
    id: "people",
    label: "People",
    items: ["👍", "👎", "👌", "✌️", "🤞", "🤟", "🤘", "👏", "🙌", "👐", "🤲", "🙏", "💪", "👀", "👋", "🤝", "💅", "👑", "💄", "🎓"]
  },
  {
    id: "nature",
    label: "Nature",
    items: ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐔", "🐧", "🐦", "🦄", "🐝", "🦋", "🌸", "🌻", "🌈", "☀️", "🌙", "⭐"]
  },
  {
    id: "food",
    label: "Food",
    items: ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🍑", "🍍", "🥝", "🍅", "🥑", "🍞", "🧀", "🍔", "🍕", "🍟", "🌭", "🍿", "🍣", "🍦", "🍪", "🎂", "☕"]
  },
  {
    id: "activity",
    label: "Activity",
    items: ["⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏆", "🎮", "🎲", "🎵", "🎶", "🎨", "🚗", "✈️", "🚀", "🏠", "💡", "📱", "💻", "⌚"]
  },
  {
    id: "symbols",
    label: "Symbols",
    items: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💯", "💢", "💥", "💫", "💦", "💨", "✨", "⭐", "✅", "❌", "❗", "❓", "‼️", "⁉️", "⚠️", "🔒", "🔑", "♻️"]
  }
]

var alternateMap = {
  a: ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
  c: ["ç", "ć", "č"],
  e: ["è", "é", "ê", "ë", "ē", "ė", "ę"],
  i: ["ì", "í", "î", "ï", "ī", "į"],
  l: ["ł"],
  n: ["ñ", "ń", "ň"],
  o: ["ò", "ó", "ô", "ö", "õ", "ø", "ō"],
  r: ["ŕ", "ř"],
  s: ["ß", "ś", "š"],
  u: ["ù", "ú", "û", "ü", "ū", "ů"],
  y: ["ý", "ÿ"],
  z: ["ź", "ž", "ż"],
  "1": ["¹", "½", "⅓"],
  "2": ["²", "⅔"],
  "3": ["³", "¾"],
  ".": ["…", "。", "·"],
  "?": ["¿"],
  "!": ["¡"]
}

function cloneRows(value) {
  return value.map(function(row) { return row.slice() })
}

function normalizeMode(value) {
  var mode = String(value || "standard").toLowerCase().replace(/_/g, "-")
  if (mode === "one-handed") return "one-handed-right"
  if (mode === "one-handed-left" || mode === "one-handed-right") return mode
  return modes.indexOf(mode) >= 0 ? mode : "standard"
}

function modeProfile(value) {
  var mode = normalizeMode(value)
  var profile = { mode: mode, width: 1.0, scale: 1.0, anchor: "center", split: false, floating: false }
  if (mode === "floating") {
    profile.width = 0.82
    profile.floating = true
  } else if (mode === "split") {
    profile.width = 1.0
    profile.split = true
  } else if (mode === "thumb") {
    profile.width = 0.72
    profile.scale = 0.92
  } else if (mode === "one-handed-left") {
    profile.width = 0.72
    profile.scale = 0.92
    profile.anchor = "left"
  } else if (mode === "one-handed-right") {
    profile.width = 0.72
    profile.scale = 0.92
    profile.anchor = "right"
  }
  return profile
}

function rows(language, numberRow) {
  var selected
  if (language === "numeric") selected = numeric
  else if (language === "symbols") selected = symbols
  else if (language === "function") selected = functionKeys
  else if (language === "editing") selected = editing
  else selected = language === "ru" ? russian : english
  var result = cloneRows(selected)
  if (numberRow && language !== "numeric" && language !== "symbols" && language !== "function" && language !== "editing")
    result = [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]].concat(result)
  return result
}

function editingRows() {
  return cloneRows(editing)
}

function splitRows(language, numberRow) {
  var source = rows(language, numberRow)
  return source.map(function(row) {
    var point = Math.ceil(row.length / 2)
    return { left: row.slice(0, point), right: row.slice(point) }
  })
}

function emojiCategories() {
  return emojiGroups.map(function(group) {
    return { id: group.id, label: group.label, items: group.items.slice() }
  })
}

function emojiItems(category, query) {
  var wanted = String(category || "recent")
  var group = emojiGroups[0]
  for (var i = 0; i < emojiGroups.length; i++) {
    if (emojiGroups[i].id === wanted) { group = emojiGroups[i]; break }
  }
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return group.items.slice()
  // Search remains local and deterministic. Unicode names are not guessed
  // without a bundled local dictionary.
  return group.id.toLowerCase().indexOf(needle) >= 0 ? group.items.slice() : []
}

function alternateKeys(key, language) {
  var value = String(key || "")
  var lower = value.toLowerCase()
  var result = (alternateMap[lower] || []).slice()
  if (language === "ru" && lower === "е") result = ["ё"]
  if (value.length === 1 && value === value.toUpperCase())
    result = result.map(function(item) { return item.toUpperCase() })
  return result
}

function toolbarItems() {
  return ["suggestions", "clipboard", "emoji", "handwriting", "editing", "language", "mode", "settings", "hide", "more"]
}

// This is deliberately a small, bundled, offline lexicon.  It gives the OSK
// a useful deterministic baseline without sending keystrokes to a service or
// persisting a user's vocabulary.  A future local provider can extend this
// contract without changing the keyboard surface.
var localWords = {
  en: ["a", "about", "after", "all", "and", "are", "back", "be", "can", "for", "from", "good", "hello", "help", "home", "how", "in", "is", "it", "keyboard", "language", "local", "me", "my", "no", "not", "now", "of", "on", "open", "or", "please", "quick", "safe", "settings", "text", "that", "the", "this", "to", "today", "up", "use", "wayland", "we", "with", "yes", "you"],
  ru: ["а", "авто", "без", "быть", "в", "вас", "ввод", "все", "вы", "да", "для", "домой", "еще", "есть", "здесь", "и", "из", "как", "клавиатура", "локально", "мне", "мой", "мы", "на", "нет", "не", "новый", "о", "он", "открыть", "пожалуйста", "привет", "работает", "русский", "с", "система", "текст", "то", "это", "я"]
}

var typoMap = {
  en: { teh: "the", adn: "and", thsi: "this", recieve: "receive", dont: "don't", cant: "can't" },
  ru: { превет: "привет", севодня: "сегодня", пожалуста: "пожалуйста", клавиатураа: "клавиатура" }
}

function languageKey(language) {
  return String(language || "en").toLowerCase().indexOf("ru") === 0 ? "ru" : "en"
}

function suggestions(prefix, language, limit) {
  var needle = String(prefix || "").trim().toLowerCase()
  if (!needle) return []
  var words = localWords[languageKey(language)] || []
  var result = []
  for (var i = 0; i < words.length; i++) {
    var word = String(words[i]).trim()
    if (word.indexOf(needle) === 0 && word !== needle && result.indexOf(word) < 0) result.push(word)
  }
  result.sort(function(a, b) { return a.length - b.length || a.localeCompare(b) })
  return result.slice(0, Math.max(1, Number(limit) || 3))
}

function autocorrect(word, language) {
  var value = String(word || "")
  if (!value) return ""
  var corrected = (typoMap[languageKey(language)] || {})[value.toLowerCase()]
  if (!corrected) return value
  if (value.charAt(0) === value.charAt(0).toUpperCase()) return corrected.charAt(0).toUpperCase() + corrected.slice(1)
  return corrected
}

function isControl(key) {
  return [
    "Shift", "Caps", "Control", "Alt", "Super", "Tab", "Esc", "Backspace", "Space", "Enter", "123", "ABC",
    "Fn", "SelectAll", "Copy", "Cut", "Paste", "Undo", "Redo", "Home", "End", "PageUp", "PageDown",
    "←", "↑", "↓", "→"
  ].indexOf(key) >= 0
}

function isRepeatable(key) {
  return ["Backspace", "←", "↑", "↓", "→", "Home", "End", "PageUp", "PageDown"].indexOf(String(key || "")) >= 0
}

function isTextKey(key) {
  var value = String(key || "")
  return value.length > 0 && !isControl(value) && value !== "123" && value !== "ABC"
}

function keyAction(key) {
  var value = String(key || "")
  var actions = {
    SelectAll: "select-all",
    Copy: "copy",
    Cut: "cut",
    Paste: "paste",
    Undo: "undo",
    Redo: "redo"
  }
  return actions[value] || "key"
}

var buttonActions = ["right-click", "middle-click", "back", "forward", "eraser", "screenshot", "annotation", "overview", "launcher", "quicksettings", "clipboard", "keyboard", "handwriting", "undo", "redo", "copy", "paste", "disabled"]

var api = {
  modes: modes,
  rows: rows,
  editingRows: editingRows,
  splitRows: splitRows,
  normalizeMode: normalizeMode,
  modeProfile: modeProfile,
  emojiCategories: emojiCategories,
  emojiItems: emojiItems,
  alternateKeys: alternateKeys,
  suggestions: suggestions,
  autocorrect: autocorrect,
  toolbarItems: toolbarItems,
  isControl: isControl,
  isRepeatable: isRepeatable,
  isTextKey: isTextKey,
  keyAction: keyAction,
  buttonActions: buttonActions
}
if (typeof module !== "undefined") module.exports = api
