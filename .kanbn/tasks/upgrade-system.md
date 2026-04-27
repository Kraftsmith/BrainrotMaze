---
created: 2026-04-27T07:00:00.000Z
---

# Upgrade System

Дизайн ([Economy.md](../../Game Design/Economy.md)) описывает 3 трека апгрейдов:
- Скорость (lvl 1–10): 16 → 35
- Вместимость переноски (lvl 1–8): 1 → 8
- Вместимость базы (lvl 1–8): 4 → 48

Сейчас все 3 захардкожены: `MAX_CARRY = 2` в BrainrotPickup, `Capacity = 4` атрибут на базе, скорость 16 (Roblox дефолт).

Создать `UpgradeService` модуль с API `getLevel(player, track)`, `setLevel(player, track, level)`. Переписать:
- `BrainrotPickup.MAX_CARRY` → `UpgradeService.getCarryCapacity(player)`
- Базы — атрибут `Capacity` ставится из upgrade
- Скорость — на CharacterAdded ставить `Humanoid.WalkSpeed` из upgrade

Зависит от [PlayerData](player-data-сервис.md) и [DataStore](data-store-персистентность.md).
