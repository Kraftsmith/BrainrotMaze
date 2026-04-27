---
created: 2026-04-27T07:00:00.000Z
---

# BrainrotLifecycle state machine

Lifecycle брейнрота (Template → Spawned → Carried → Placed/Dropped → Destroyed) сейчас закодирован тремя независимыми механизмами: тегами (`Brainrot`, `PlacedBrainrot`), атрибутами (`PlacedBy`, `BeingPickedUp`, `InternalWeldsBuilt`) и parent-ом (workspace vs base).

Каждый из 3 скриптов (Pickup, Delivery, Spawner) интерпретирует свою комбинацию. Чтобы добавить новые состояния (например, "в полёте через портал" или "заморожен ивентом"), нужно править все 3.

Создать `BrainrotLifecycle` модуль: явные состояния (enum), явные переходы (`transition(model, newState)`), валидация переходов (нельзя из Placed обратно в Carried). Скрипты только дёргают переходы; модуль сам обновляет теги/атрибуты.
