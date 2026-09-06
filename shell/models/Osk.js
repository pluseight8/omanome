function rows(language, numberRow) {
  var english = [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["Shift", "z", "x", "c", "v", "b", "n", "m", "Backspace"],
    ["123", "@", "#", "Space", ".", ",", "Enter"]
  ]
  var russian = [
    ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
    ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
    ["Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "Backspace"],
    ["123", "@", "№", "Space", ".", ",", "Enter"]
  ]
  var numeric = [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["-", "/", ":", ";", "(", ")", "$", "&", "\""],
    ["ABC", "'", "?", "!", "#", "%", "Backspace"],
    ["ABC", "Space", ".", ",", "Enter"]
  ]
  return language === "numeric" ? numeric : (language === "ru" ? russian : english)
}

function isControl(key) {
  return ["Shift", "Backspace", "Space", "Enter", "123", "ABC", "Caps"].indexOf(key) >= 0
}
