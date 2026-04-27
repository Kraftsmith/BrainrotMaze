---
created: 2026-04-27T07:00:00.000Z
---

# BasesService абстракция

Hardcoded `BASE_NAMES = {"bazapl1", ..., "bazapl4"}` повторяется в `BrainrotDelivery`, `BaseManager`, `RoundManager`. Доступ к базам через `workspace:FindFirstChild` тоже разбросан. Чтобы добавить 5-ю базу — править N скриптов.

Создать `ServerStorage.BasesService` с API:
- `getAll() -> {Base}`
- `getOwner(base) -> Player?`
- `getCapacity(base) -> int`
- `getPlacedBrainrots(base) -> {Model}`
- `getPlayerBase(player) -> Base?`

Внутри — кеш + watch на `DescendantAdded` для динамики. Все потребители идут через сервис, не напрямую в Workspace.
