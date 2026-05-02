---
created: 2026-04-27T07:00:00.000Z
updated: 2026-05-02T11:10:09.827Z
started: 2026-05-02T09:10:13.479Z
completed: 2026-05-02T11:10:09.827Z
---

# PlayerData сервис

Состояние игрока размазано по 5+ местам: `BrainrotState.carrying`, `BrainrotDelivery.placed`, `BrainrotDelivery.lastDelivery`, `BaseManager.playerToBase`, `leaderstats.Coins`, плюс player attributes. Каждая новая фича добавляет свой слайс — нет единого источника правды.

Создать модуль `ServerStorage.PlayerData` с API `get(player) -> profile`, `update(player, mutator)`. Profile — Lua-таблица со всеми per-player полями (Coins, уровни апгрейдов, базы, цепочка переноски). Все потребители идут через сервис.

**Критично сделать ДО DataStore** — иначе DataStore будет сериализовать state из 5 разных мест, и потом всё равно придётся рефакторить в PlayerData. Двойная работа.
