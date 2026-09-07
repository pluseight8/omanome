# Omanome

Omanome — открытый набор улучшений рабочего стола для актуального Omarchy Quattro на Hyprland. Он добавляет GNOME-подобный интерфейс для touchscreen и стилуса, но остаётся обычным Omarchy Shell Plugin: стандартная верхняя панель не заменяется, второй Quickshell не запускается, GNOME Shell и Mutter не нужны.

Это запускаемая фаза версии 0.9.0. Ядро использует публичные API Omarchy/Quickshell/Hyprland, а дополнительные compositor-возможности подключаются только через явные version-aware companion boundaries. Нативный Wayland input helper держит одно bounded-соединение с seat/keyboard/tablet, использует xkbcommon EN/RU и честно сообщает недоступные протоколы. Если настоящего backend нет, функция остаётся явно недоступной, а не подменяется декоративной имитацией.

## Возможности

- Manifest с `service`, `bar-widget` и `panel`; replacement-тип `bar` отсутствует.
- Компактный Omanome widget в существующей панели Omarchy.
- Единая ленивая панель: Overview, workspaces, launcher, Quick Settings, OSK, clipboard, notifications и Settings.
- GNOME-подобный Overview с mosaic реальных окон, текущим workspace первым,
  dynamic/fixed strip и поиском по приложениям, окнам, настройкам и actions.
- Полноценная адаптивная App Grid с настоящими desktop icons, общим с Dock
  избранным, категориями, recent ordering, folders, drag reorder и context menu.
- First-run onboarding: input mode, позиция Dock, Overview, OSK, stylus,
  rotation и privacy; при обновлении со старой версии setup не повторяется.
- Settings 2.0: поиск категорий, deep links, portrait navigation, причины
  недоступности backend, accessibility, безопасная Copy diagnostics и встроенный
  запуск `omanome doctor`.
- Tablet Mode 2.0 с Auto/Desktop/Tablet/Hybrid и несколькими сигналами:
  touchscreen, stylus, физическая клавиатура, ориентация, recent input и switch;
  переходы меняют targets, Dock, controls и density без reload shell.
- Quick Settings получает живое состояние Wi-Fi/Bluetooth/PipeWire, яркости,
  профиля питания и батареи; отсутствующие backend явно отключаются, а не
  заменяются локальными фиктивными переключателями.
- Нативное определение возможностей планшета, annotation overlay с undo/redo,
  screenshot/copy и динамическими Hyprland transform для touch/tablet/output;
  автоматический поворот подключается только при наличии sensor backend.
- Опциональный dock в стиле Dash-to-Dock на нескольких мониторах: избранное, running indicators, контекстные действия, configurable position/mode и intelligent autohide.
- Определение touchscreen/stylus через Hyprland, hysteresis ввода, logical-size responsive breakpoints, режимы Automatic/Desktop/Tablet/Hybrid и применение touch-жестов через IPC.
- English/Русский, профили, versioned config, import/export/reset и приватная история clipboard для текста/PNG.
- Настоящий compositor-backed blur Omanome layer surfaces через Hyprland layer rules, с per-surface settings, adaptive quality и app-rule exclusions; стандартная панель Omarchy по умолчанию не изменяется.
- Native foreign-toplevel Coverflow Alt-Tab с grouping/scope, общими animations и capability-gated live preview; в текущем окружении preview недоступен, потому что Quickshell не предоставляет texture provider.
- Безопасный Force Quit: native close, PID-scoped TERM/KILL fallback, защита session-процессов и отмена без `pkill` по имени.
- Clipboard 2.0: pin/search/text edit/tags/image preview/retention/max storage/per-app exclusions/clear-unpinned, password/secret MIME filtering и передача payload только через stdin.
- Notification center с grouping, timestamps, actions, touch/stylus swipe dismiss, per-app mute и clear group/all на базе нативного Omarchy notification service.
- Wobbly companion выполняет настоящую bounded mesh-деформацию compositor-owned workbuffer через публичный Hyprland `IWindowTransformer`; exact API hash, GL backend, shader/buffer и lifecycle checks остаются обязательными, иначе capability закрывается.
- Real Desktop Cube backend интегрируется через внешний `omarchy-desktop-cube`, если он загружен; Omanome не дублирует его renderer.
- Wayland-native OSK через `wtype`: English/Russian QWERTY, standard/floating/split/thumb/one-handed left/right, numeric/symbols/emoji/editing и handwriting canvas; есть toolbar, long-press alternates, key popup и configurable repeat.
- Постоянный native `omanome-input` transport с bounded JSON IPC, authoritative xkbcommon EN/RU, event-driven hotplug input/display, capability-based identity клавиатур, распознаванием detachable/Bluetooth и explainable posture hysteresis. `omanome input-info` показывает фактические native/fallback capability.
- Использование нативного Omarchy notification service для DND, истории и dismiss.
- CLI для диагностики, включая capabilities, hardware-test, redacted support bundle, `stylus-info`, `touch-info`, `sensor-info`, установку из GitHub, safe mode, транзакционные обновления/recovery, rollback и ownership-safe удаление.

## Установка из GitHub

```sh
omarchy plugin add https://github.com/pluseight8/omanome.git --enable --yes
omanome doctor
```

Или используй удобную команду Omanome:

```sh
omanome install
```

В графическом Omarchy Plugin Manager открой `Setup → Plugins → Add`, вставь
`https://github.com/pluseight8/omanome.git`, проверь manifest и включи
`io.omanome.shell`. Omanome не заменяет стандартную верхнюю панель: при
необходимости добавь его widget через обычные настройки bar.

Для локальной разработки используйте `./cli/omanome setup` и штатный локальный механизм установки плагинов вашей версии Omarchy. Omanome не вызывает `sudo` и не изменяет `$OMARCHY_PATH`.

После установки добавьте widget `Omanome` через обычные настройки панели Omarchy. Он расширяет существующую панель и не создаёт её копию.

## Запуск

Левая кнопка на widget открывает Overview, правая — Quick Settings, средняя — OSK. Через shell API:

```sh
omarchy-shell shell summon io.omanome.shell '{"view":"overview"}'
omarchy-shell shell toggle io.omanome.shell '{"view":"quicksettings"}'
```

Можно назначить эти команды на пользовательские Hyprland keybindings. Omanome не перезаписывает занятые shortcuts молча.

Конфигурация: `~/.config/omanome/config.json` (либо `$XDG_CONFIG_HOME/omanome/config.json`). Состояние и изображения clipboard: `$XDG_STATE_HOME/omanome`. Sensitive/private clipboard не сохраняется при MIME hints `password`, `secret`, `credential`, `token`, `private-key`; содержимое не попадает в логи и аргументы команд.

## CLI

```text
omanome status
omanome doctor
omanome logs
omanome reload
omanome enable | disable
omanome safe-mode
omanome setup
omanome install
omanome export-config [file]
omanome import-config <file>
omanome reset [--yes]
omanome update --check
omanome update
omanome update --dry-run --json
omanome rollback --list --json
omanome recover --json
omanome capabilities
omanome input-info
omanome hardware-test --fixture tests/fixtures/hardware-tablet.json --json
omanome diagnostics bundle [output.tar.gz]
omanome stylus-info
omanome touch-info
omanome sensor-info
omanome devices
omanome effects
omanome benchmark
omanome processes [--json]
omanome profiler [--json] [--interval 1]
omanome watchdog [--watch] [--json]
omanome performance reset|check [--json]
omanome companion status|doctor|build|install|rebuild|enable|disable
omanome uninstall [--purge-settings] [--yes]
```

`update --check` показывает установленную и последнюю версии репозитория,
текущий и удалённый commit, канал обновлений и наличие обновления. `update`
проверяет официальный GitHub origin, журналирует фазы, создаёт rollback-копию,
вызывает штатный Omarchy updater и автоматически восстанавливает предыдущую
версию, если новая не проходит validation. Незавершённый журнал восстанавливается
перед новым update или uninstall. `rollback --list --json` только показывает
snapshot. `uninstall --dry-run --json` показывает точные принадлежащие пути;
ownership manifest и проверки symlink запрещают широкое удаление.
`uninstall --yes` удаляет только Omanome, companion data, cache, state и, по
выбору, настройки; Omarchy, стандартная панель, другие плагины, темы и
пользовательский Hyprland не затрагиваются.

## Производительность, ownership и high-CPU triage

У Omanome есть одна явная граница владения: собственные helper-процессы
получают `OMANOME_OWNER=io.omanome.shell` и регистрируются вместе с PID и
временем запуска. `omanome processes` и страница Performance в Settings
смотрят только эту границу. Чужие процессы с похожим именем, включая
немаркированный `lua`, исключаются и не приписываются Omanome.

Для диагностики используйте:

```sh
omanome processes --json
omanome benchmark --json
omanome watchdog --watch --json
omanome profiler [--json] [--interval 1]
```

Snapshot разделяет CPU Omanome и CPU всей системы. Deterministic benchmark
измеряет projection config и JSON round-trip, а не FPS и не idle CPU.
Watchdog только уведомляет: порог должен держаться заданное время, сигналы не
посылаются и процессы не завершаются. Для чужого процесса с высоким CPU нужно
проверять executable, command line и parent chain и обращаться к владельцу
пакета/сервиса. Не используйте команды по имени вроде `pkill lua`.

Режимы производительности: `automatic`, `quality`, `balanced`, `performance` и
`battery-saver`. Automatic использует доступные сигналы питания, температуры,
fullscreen и GPU; отсутствие telemetry не превращается в фиктивную метрику.
Preview streams ограничены budget, panel views загружаются лениво, поиск имеет
debounce, а закрытая панель освобождает live-preview ресурсы. Старое поле
schema-2 `performance.qualityPreset` мигрирует в `performance.mode`.

## Touch и stylus

Omanome не зависит от бренда стилуса: discovery использует типы и capabilities, а не vendor-name substring. Diagnostics показывают pressure, tilt X/Y, rotation, distance, proximity, eraser, buttons, serial, backend и mapped output только когда их сообщает backend. Нативные pressure/tilt/eraser-события приложений не заменяются synthetic mouse events. Политика pressure curve, palm rejection, monitor mapping и кнопок описана в [`stylus/README.md`](stylus/README.md). OSK работает через `wtype`; auto-show focused text field и persistent cursor input требуют optional native companion. Auto-rotation предпочитает `monitor-sensor`, затем iio-sensor-proxy D-Bus; manual rotation работает без sensor.

## Проверка и разработка

```sh
make check
```

Команда запускает валидатор manifest/config, shell syntax checks, Python tests, штатный Omarchy validator и Qt `qmllint` с модулями установленного Omarchy. Предупреждения про динамически инжектируемые свойства Omarchy допустимы; синтаксические и фатальные ошибки — нет.

Подробности: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/TESTING.md`](docs/TESTING.md) и [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md).

## Границы 0.9 native input, stylus, lifecycle и safety

Blur применяется через Hyprland layer-rule IPC к namespace Omanome, а не рисуется как прозрачный прямоугольник. Coverflow работает с реальными Hyprland foreign-toplevel объектами и native activation. Live preview остаётся выключенным, пока активный Quickshell/companion не даст настоящий texture provider. Force Quit сначала вызывает native close выбранного окна и только затем использует выбранный numeric PID; session-процессы защищены, broadcast по имени не используется.

Настоящий Wobbly подключается через optional `omanome-hypr`: он получает compositor-owned workbuffer, рисует ограниченный mesh через публичный `IWindowTransformer` и возвращает framebuffer в обычный Hyprland pass. Включение выполняется через `hyprctl -j omanome-effects wobbly enable`, а bounded physics/mesh — через `wobbly config key=value ...`; QML Settings отправляет тот же IPC с debounce. Master-toggle advanced effects и battery/fullscreen policy отключают дорогой render path fail-closed. При несовпадении API/ABI, X11/rotated output, ошибке shader/buffer, crash-marker или недоступном GL renderer эффект остаётся выключенным, а исходный framebuffer сохраняется. Настоящий Desktop Cube подключается через отдельно сопровождаемый version-matched `omarchy-desktop-cube`, если он загружен; без него cube недоступен. Omanome не анимирует screenshots и не загружает неприкреплённый Hyprland `.so`.

В 0.9 сохранены lifecycle-инварианты 0.8: bounded backoff для subprocess, подавление crash loop,
единая command lane, debounce persistence, медленные/event-driven fallback,
owner-only snapshots и явное освобождение preview delegates при закрытии panel.
Нативный `omanome-input` использует `zwp_virtual_keyboard_v1`, когда compositor
его предоставляет, реальный text-focus protocol при наличии и явный `wtype`
fallback только при включённой политике. OSK 3.0 держит prediction и
autocorrect локальными и bounded; surrounding/password text не сохраняется и не
логируется. Tablet-v2 capability path покрывает pressure, tilt, distance,
rotation, eraser, buttons, proximity, output mapping, suspend/resume и rollback;
handwriting ink остаётся локальным, а recognition честно unavailable до выбора
provider. OSK repeat останавливается на release, rotation и clipboard watchers не входят в
tight loop, а optional wobbly control fail-closed без companion. Избранное
и folders App Grid сохраняются локально; compositor drag semantics не
имитируются. Весь основной shell остаётся работоспособным без companion.

## Лицензия

MIT. См. [`LICENSE`](LICENSE).
