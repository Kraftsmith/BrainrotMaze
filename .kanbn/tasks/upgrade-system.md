---
created: 2026-04-27T07:00:00.000Z
started: 2026-04-27T16:00:00.000Z
---

# Upgrade System

3 трека апгрейдов из [Economy.md](../../Game Design/Economy.md): скорость, вместимость переноски, вместимость базы.

## Что сделано

- **`ServerStorage.PlayerData`** — in-memory per-player состояние (`speedLvl`, `carryLvl`, `baseLvl`). Future-ready под DataStore.
- **`ServerStorage.UpgradeConfig`** — таблицы значений + цен из Economy.md (speed 1-10 / carry 1-8 / baseCap 1-8).
- **`ServerScriptService.UpgradeService`** — на PlayerAdded/CharacterAdded применяет WalkSpeed и Capacity. Покупки через `tryUpgrade(player, track)`.
- **`BrainrotPickup`** — `MAX_CARRY` больше не захардкожен, читается из `PlayerData.carryLvl` через `UpgradeConfig.getEffect("carry", lvl)` при каждом пикапе.
- **Тест-команды в чате** (пока нет Shop UI): `/upgrade speed`, `/upgrade carry`, `/upgrade base`.

⚠️ **Стартовая carry capacity = 1**, не 2 (по дизайну Economy.md). Чтобы поднять до 2 — `/upgrade carry` за 250 монет.

## Как тестить (для сына)

**Что проверяем:** монеты можно тратить на апгрейды → персонаж становится быстрее, несёт больше, база вмещает больше.

### Подготовка

1. Нажми **Play** в Studio.
2. Подойди к spawn-platform 1, подбери Common-брейнрота.
3. Принеси на свою базу — Coins должны начать тикать.
4. **Накопи минимум 100 монет** (потребуется ~1.5 минуты с 1 Common брейнротом, или быстрее с Mythic).

### Тест A: Скорость 🏃

1. Открой чат (нажми `/` или Tab).
2. Напиши `/upgrade speed` и Enter.
3. **Должно произойти:**
   - Coins уменьшилось на 100.
   - Персонаж побежал **заметно быстрее** (WalkSpeed 16→18).
   - В Output: `[UpgradeService] MikhailSorokin bought speed lvl 2 (value=18, cost=100)`.
4. Накопи ещё 300 → купи speed lvl 3 (WalkSpeed 20).
5. Каждый следующий уровень = +2 скорости, дороже в ~2.5 раза.

### Тест B: Вместимость переноски 📦

1. Стартом ты несёшь только **1 брейнрота** (раньше было 2 — убрали по дизайну).
2. Накопи 250 монет.
3. Чат: `/upgrade carry`.
4. **Должно произойти:**
   - Coins -250.
   - Теперь подбираешь **2 брейнрота стопкой** на голове.
5. Купи carry ещё раз (за 1000) → 3 штуки на голове.

### Тест C: Вместимость базы 🏠

1. На базе стартом помещается **4 брейнрота** (потом не размещаются).
2. Накопи 500.
3. Чат: `/upgrade base`.
4. **Должно произойти:**
   - Coins -500.
   - Теперь на базе помещается **6** брейнротов.
5. Принеси 5-го и 6-го → размещаются. 7-го — нет.

### Тест D: Защиты

1. Не хватает монет → команда отклоняется. В Output: `[UpgradeService] MikhailSorokin /upgrade speed FAILED: not enough coins (50 / 100)`.
2. Достиг макса → отказ. В Output: `FAILED: max level`.

### Что писать папе если что-то не так

- "Команда `/upgrade speed` ничего не сделала — Coins не убрались, скорость та же."
- "Скорость поменялась, но через 5 секунд вернулась к 16" (что-то перебивает WalkSpeed).
- "Купил carry, но всё ещё несу 1" (Pickup не читает PlayerData).
- "Купил base, но 5-й брейнрот не размещается" (Capacity attribute не обновился).
- ⚠️ "Coins ушли, но эффект не применился" — баг.

## Pending после тестов

Если всё работает → двигай в Done. Дальше:
- **Shop UI** ([shop-ui-и-покупки](shop-ui-и-покупки.md)) — кнопки вместо чат-команд.
- **DataStore** ([data-store-персистентность](data-store-персистентность.md)) — апгрейды сохраняются между сессиями.
