---
created: 2026-04-27T07:06:06.450Z
started: 2026-04-27T13:20:11.958Z
updated: 2026-04-27T13:59:17.166Z
completed: 2026-04-27T13:59:17.166Z
---

# Перевести разработку в Git

Все Lua-скрипты теперь на диске + в git, Rojo синхронизирует с Studio в обе стороны.

**Репо:** https://github.com/Kraftsmith/BrainrotMaze (private)

## Что сделано

- Установлен Rojo CLI 7.6.1 (`C:\Users\User\bin\rojo.exe`, в PATH)
- Установлен Rojo Studio plugin (через `rojo plugin install`)
- Создан `default.project.json` с `$ignoreUnknownInstances: true` (чтоб не затёр существующее в Studio)
- 9 скриптов выгружены в `src/` по сервисам (5 server / 2 module ServerStorage / 1 module ReplicatedStorage / 1 client)
- `.gitignore` (исключает .claude, .vscode, build/, sourcemap.json, OS junk)
- `git init` + initial commit (41 файл, 2579 строк) + push на GitHub

## Workflow с этого момента

- **Edit на диске** (VSCode/Cursor): Rojo plugin (если Connect активен) автоматически пушит в Studio.
- **Edit в Studio**: пока не пушится обратно автоматически. Чтоб сохранить — копируешь в файл руками ИЛИ используешь "Save Place File" в плагине → пересинхронизируешь.
- **Стандартный git**: `git pull`, `git add`, `git commit`, `git push`. Бранчи: `git checkout -b feature/xyz`.

## Как тестить (для сына, на его машине)

1. Установить Git for Windows (если нет): https://git-scm.com/download/win
2. Установить Rojo CLI: скачать `rojo-7.6.1-windows-x86_64.zip` с https://github.com/rojo-rbx/rojo/releases, распаковать `rojo.exe` в `C:\Users\<имя>\bin`, добавить в PATH.
3. Установить Rojo plugin: `rojo plugin install`
4. Склонировать репо: `git clone https://github.com/Kraftsmith/BrainrotMaze.git`
5. В склонированной папке: `rojo serve`
6. Открыть Studio с Maze.rbxl, Plugins → Rojo → Connect.
7. Должен показать "in sync".

## Pending

- Сын подтверждает, что у него на машине Rojo+git работает.
- В будущем: `Brainrot Templates`, `bazapl1-4` модели, лабиринты, ловушки — это "тяжёлые" модели с мешами, не выгружены в Rojo. Они остаются в `.rbxl`. Если поломаются — синхронизировать через Studio "Save Place File".
