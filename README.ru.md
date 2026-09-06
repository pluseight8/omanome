# Omanome

Omanome — открытый набор улучшений рабочего стола для актуального Omarchy Quattro на Hyprland. Он добавляет GNOME-подобный интерфейс для touchscreen и стилуса, но остаётся обычным Omarchy Shell Plugin: стандартная верхняя панель не заменяется, второй Quickshell не запускается, GNOME Shell и Mutter не нужны.

Это запускаемый baseline версии 0.1.0. Реализованы возможности, для которых достаточно публичных API Omarchy/Quickshell/Hyprland. Функции, требующие ABI compositor или отдельного text-input/handwriting backend, оставлены явными безопасными точками расширения, а не подменены фальшивыми скриншотами.

## Возможности

- Manifest с `service`, `bar-widget` и `panel`; replacement-тип `bar` отсутствует.
- Компактный Omanome widget в существующей панели Omarchy.
- Единая ленивая панель: Overview, workspaces, launcher, Quick Settings, OSK, clipboard, notifications и Settings.
- Опциональный dock на нескольких мониторах и touch-кнопки активного окна.
- Определение touchscreen/stylus через Hyprland, режимы Automatic/Desktop/Tablet/Hybrid и применение touch-жестов через IPC.
- English/Русский, профили, versioned config, import/export/reset и приватная история clipboard для текста/PNG.
- Wayland-native OSK через `wtype`: English, Russian, numeric, floating, split, one-handed и handwriting-panel режимы.
- Использование нативного Omarchy notification service для DND, истории и dismiss.
- CLI для диагностики, safe mode, обновления, rollback и удаления.

## Установка

```sh
omarchy plugin add <repo-url> --enable --yes
omanome doctor
```

Для локальной разработки используйте `./cli/omanome setup` и штатный локальный механизм установки плагинов вашей версии Omarchy. Omanome не вызывает `sudo` и не изменяет `$OMARCHY_PATH`.

После установки добавьте widget `Omanome` через обычные настройки панели Omarchy. Он расширяет существующую панель и не создаёт её копию.

## Запуск

Левая кнопка на widget открывает Overview, правая — Quick Settings, средняя — OSK. Через shell API:

```sh
omarchy-shell shell summon io.omanome.shell '{"view":"overview"}'
omarchy-shell shell toggle io.omanome.shell '{"view":"quicksettings"}'
```

Можно назначить эти команды на пользовательские Hyprland keybindings. Omanome не перезаписывает занятые shortcuts молча.

Конфигурация: `~/.config/omanome/config.json` (либо `$XDG_CONFIG_HOME/omanome/config.json`). Состояние и изображения clipboard: `$XDG_STATE_HOME/omanome`. Sensitive clipboard не сохраняется при `CLIPBOARD_STATE=sensitive`, password/secret MIME hints или Private mode; содержимое не попадает в логи и аргументы команд.

## CLI

```text
omanome status
omanome doctor
omanome logs
omanome reload
omanome enable | disable
omanome safe-mode
omanome setup
omanome export-config [file]
omanome import-config <file>
omanome reset [--yes]
omanome update --check
omanome update
omanome rollback
omanome stylus-info
omanome devices
omanome uninstall [--purge-settings] [--yes]
```

`update` создаёт пользовательскую rollback-копию, вызывает штатный updater Omarchy и проверяет установленный checkout перед reload. `rollback` восстанавливает последнюю копию. `uninstall` удаляет только Omanome, его cache/state и, по выбору, settings; Omarchy, стандартная панель, другие плагины, темы и пользовательский Hyprland не затрагиваются.

## Touch и stylus

Omanome не зависит от бренда стилуса и читает inventories `touch`/`tablets` Hyprland. Нативные pressure/tilt/eraser-события приложений не заменяются synthetic mouse events. Политика pressure curve, palm rejection, monitor mapping и кнопок описана в [`stylus/README.md`](stylus/README.md). OSK работает через `wtype`; без него остальные части shell продолжают работать. Автоматическое открытие по focused text field требует отдельного text-input focus provider.

## Проверка и разработка

```sh
make check
```

Команда запускает валидатор manifest/config, shell syntax checks, Python tests, штатный Omarchy validator и Qt `qmllint` с модулями установленного Omarchy. Предупреждения про динамически инжектируемые свойства Omarchy допустимы; синтаксические и фатальные ошибки — нет.

Подробности: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) и [`docs/TESTING.md`](docs/TESTING.md).

## Ограничения

Публичные API текущих Omarchy/Hyprland не дают безопасного portable backend для настоящего compositor-level wobbly windows и 3D workspace cube. Omanome оставляет их выключенными и показывает причину, не загружая неприкреплённый Hyprland `.so`. Live thumbnails, автоматическое обнаружение focused text field, sensor rotation, handwriting recognition и полная persistence drag-and-drop app grid также ожидают отдельного backend. Весь основной shell при этом остаётся работоспособным.

## Лицензия

MIT. См. [`LICENSE`](LICENSE).
