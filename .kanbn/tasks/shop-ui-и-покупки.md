---
created: 2026-04-27T07:00:00.000Z
---

# Shop UI и покупки

Без UI игрок не может потратить заработанные монеты. Нужен:
- ScreenGui с табами (Скорость / Вместимость / База / Лабиринты)
- Каждый item: текущий уровень, цена следующего, кнопка "Купить"
- RemoteEvent `PurchaseUpgrade(track, targetLevel)`
- Сервер-валидация: монет хватает, target = current+1, не превышен максимум
- Списание монет, повышение уровня в [UpgradeService](upgrade-system.md)

Цены — из [Economy.md](../../Game Design/Economy.md) § 2-4. На базе уже есть Shop-модель (на скрине лобби) — переиспользовать как точку открытия UI.

Зависит от [Upgrade System](upgrade-system.md). Использовать Remotes-архитектуру из [Remotes housekeeping](remotes-housekeeping.md).
