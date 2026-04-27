# BrainRot Maze

Roblox Studio игра. Игрок собирает брейнротов в лабиринтах, приносит на свою базу — они дают пассивный доход.

Дизайн-доки: [Game Design/](Game Design/Main Game Design.md) • Канбан-доска: [.kanbn/](.kanbn/index.md) • Спеки задач: [Tasks/](Tasks/)

---

## Структура

```
.
├── default.project.json   # Rojo: маппинг диск → Studio services
├── src/                   # Lua-скрипты (синхронизируются с Studio через Rojo)
│   ├── ServerScriptService/   *.server.lua → Script
│   ├── ServerStorage/         *.lua → ModuleScript
│   ├── ReplicatedStorage/     *.lua → ModuleScript
│   └── StarterPlayerScripts/  *.client.lua → LocalScript
├── Game Design/           # Дизайн-доки (markdown)
├── Tasks/                 # Детальные спецификации задач
├── .kanbn/                # Канбан-доска (kanbn CLI формат)
└── .claude/               # Сессии Claude Code (gitignored)
```

**Большие модели** (мазы с мешами, брейнрот-модели, базы) хранятся **в `.rbxl` Studio-файла**, не в git. Они меняются редко, диффы для бинарников бесполезны. Скрипты — да, в git.

---

## Workflow

### Первый раз на машине

1. **Установить Rojo CLI**: положить [rojo.exe v7.6.1](https://github.com/rojo-rbx/rojo/releases) в `C:\Users\<user>\bin\` и добавить в PATH.
2. **Установить Rojo Studio plugin**: скачать `Rojo.rbxm` из того же релиза, положить в `%LOCALAPPDATA%\Roblox\Plugins\`. Перезапустить Studio.
3. **Клонировать репо**: `git clone <url>` в любую папку.

### Каждый раз когда работаешь с кодом

1. Открыть Studio с местом (`File > Open` → нужный `.rbxl`).
2. В терминале: `cd` в папку проекта → `rojo serve`.
3. В Studio: верхняя панель → Plugins → Rojo → **Connect** (порт 34872).
4. Теперь любое сохранение `.lua` файла на диске → Studio мгновенно подхватывает.
5. Закончил — Ctrl+C в терминале (закрыть Rojo serve), сохранить Studio (Ctrl+S).
6. `git add . && git commit -m "..."` → `git push`.

---

## Список скриптов в git

| Файл | Тип | Что делает |
|---|---|---|
| `BrainrotPickup.server.lua` | Script | Подбор/дроп/уничтожение брейнротов через ProximityPrompt |
| `BrainrotDelivery.server.lua` | Script | Доставка на базу + leaderstats Coins + income tick |
| `BrainrotSpawner.server.lua` | Script | Спавн на BrainrotSpawnPad-ах раз в 30–90с |
| `BrainrotTagger.server.lua` | Script | Авто-тег моделей с "brainrot" в имени |
| `MazeTrapsServer.server.lua` | Script | Циклы ловушек on/off + дебаунс + tier-множитель |
| `BrainrotState.lua` | ModuleScript | Общий state "кто что несёт" |
| `Util.lua` | ModuleScript | `Util.locationOf(player)` для логов |
| `BrainrotConfig.lua` | ModuleScript | Rarity → income/sec |
| `BrainrotInput.client.lua` | LocalScript | E-key drop + HUD-хинт |

---

## Что НЕ в git (живёт в .rbxl)

- `Workspace` — лабиринты, базы, spawn platforms, Spawn Pads, ловушки (с их атрибутами)
- `ServerStorage.BrainrotEvents` — папка с BindableEvent (создаётся скриптами при первом запуске)
- `ServerStorage.BrainrotTemplates` — модели брейнротов с мешами
- `ServerStorage.TrapTemplates` — модели ловушек (генерируются скриптом)
- `ReplicatedStorage` RemoteEvent'ы — создаются скриптами при первом запуске

---

## Полезные команды

```bash
rojo --version              # проверить установку
rojo serve                  # запустить sync-сервер (порт 34872)
rojo build -o build.rbxlx   # экспортировать src/ в .rbxlx (для CI / без Studio)
git status                  # что изменилось с последнего коммита
git log --oneline           # история коммитов
```
