---
created: 2026-05-02T11:00:00.000Z
---

# Инвентарь — UI placed-брейнротов

Игрок видит, что у него стоит на базе: список с группировкой по rarity, счётчик `placed/capacity`, суммарный доход/сек.

Тоггл по `I` + кнопка под Shop'ом, оверлей. Источник данных — теги `PlacedBrainrot` + атрибуты `PlacedBy`/`Rarity` (всё уже реплицируется клиенту, новых RemoteEvent'ов не нужно).

- Спека (UI / поведение) — [Game Design/Inventory.md](../../Game%20Design/Inventory.md).
- Имплементейшн-план (что делать пошагово) — [Tasks/Inventory.md](../../Tasks/Inventory.md).

В Tasks/Inventory.md разложено: палитра rarity в `BrainrotConfig`, UI-каркас `InventoryClient`, поиск своей базы, сбор snapshot'а, рендер, подписки + debounced re-render, smoke-тест. Acceptance criteria тоже там — 10 пунктов.

Серверной части нет — клиент читает теги `PlacedBrainrot` и атрибуты напрямую.
