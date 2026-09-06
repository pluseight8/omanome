function rows(language, numberRow) {
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
  var functionKeys = [
    ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
    ["←", "↑", "↓", "→", "Home", "End", "PageUp", "PageDown"],
    ["ABC", "Tab", "Space", "Enter"]
  ]
  if (language === "numeric") return numeric
  if (language === "function") return functionKeys
  var result = language === "ru" ? russian : english
  if (numberRow) result = [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]].concat(result)
  return result
}

function isControl(key) {
  return ["Shift", "Caps", "Control", "Alt", "Super", "Tab", "Esc", "Backspace", "Space", "Enter", "123", "ABC"].indexOf(key) >= 0
}

var api = { rows: rows, isControl: isControl }
if (typeof module !== "undefined") module.exports = api
