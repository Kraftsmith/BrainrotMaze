---
created: 2026-04-27T07:00:00.000Z
---

# Templates registry с валидацией

`BrainrotSpawner` загружает templates просто через `templatesFolder:GetChildren()` — никакой валидации. Если template без BasePart или без атрибута `Rarity` — спавнер крашится в `findOrSetPrimary` или присваивает Common молча.

Создать `BrainrotTemplateRegistry` модуль: при добавлении шаблона валидирует (есть BasePart? есть Rarity? есть PrimaryPart?). Невалидные — лог ошибки + не индексирует. API: `getRandom(rarities) -> Model?`, `validateAll() -> {issues}`, `count(rarity) -> int`.

Особенно полезно когда сын импортирует новые меши — сразу скажет "у этого нет PrimaryPart, не подхвачу".
