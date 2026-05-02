# Take-back брейнрота с базы

## Цель

Игрок может снять размещённого брейнрота со своей базы обратно в руки, чтобы освободить слот для более доходного. Без UI-меню, без отдельного тулбара — нативно через `ProximityPrompt` с `E`.

Спека: [Game Design/Base.md § Снятие брейнрота с базы](../Game%20Design/Base.md#снятие-брейнрота-с-базы-take-back).

---

## Что уже сделано ✅

Задача реализована за один проход. Фактический объём:

- **Lifecycle:** [`BrainrotLifecycle.lua`](../src/ServerStorage/BrainrotLifecycle.lua) — добавлен переход `Placed → Carried` в `ALLOWED`. Тег `PlacedBrainrot` снимается, `Brainrot` ставится автоматически.
- **State:** [`PlayerData.lua`](../src/ServerStorage/PlayerData.lua) — новый метод `removePlaced(player, model)` для синхронного удаления из placed-списка (не полагаемся на ленивый `prunePlaced`, иначе одна и та же модель окажется и в `placed`, и в `carrying` на один тик).
- **Pickup:** [`BrainrotPickup.server.lua`](../src/ServerScriptService/BrainrotPickup.server.lua):
  - `takeBackFromBase(player, model)` — owner-check, capacity-check, разрушение prompt'а, reparent в workspace, carry rig (анкер + welds + `setPartsCarriedState` + `setPromptsEnabled(false)`), state-mutations, lifecycle.transition.
  - `bindPlacedModel(model)` — на `CollectionService:GetInstanceAddedSignal("PlacedBrainrot")` создаёт свежий `TakeBackPrompt` на `PrimaryPart` модели, коннектит `Triggered` → `takeBackFromBase`.

---

## Архитектурные решения

### Почему `ProximityPrompt`, а не tag-bind на собственный keypress

- Roblox `gameProcessedEvent` автоматически решает конфликт `E = drop/place` vs `E = take-back`. При активации prompt'а `UserInputService.InputBegan` получает `processed=true`, и [`BrainrotInput.client`](../src/StarterPlayerScripts/BrainrotInput.client.lua) (`if processed then return end`) не фаерит `DropBrainrot:FireServer`. Без prompt'а — фаерит как обычно.
- `RequiresLineOfSight=true` фильтрует подсказку: prompt активируется только когда игрок **смотрит** на конкретного брейнрота. На базе с 10 брейнротами игрок не получает 10 одновременных prompt'ов — только тот, на которого направлен взгляд.
- Стандартный Roblox UX, не нужно писать кастомный HUD-индикатор.

### Почему `model.Parent = workspace`, а не оставить под base

- Семантически: «снят с базы» = модель не ребёнок базы.
- Income-tick читает `m.Parent` для `Vip`-множителя. Если оставить `Parent = base`, фильтр пришлось бы делать через тег (`HasTag(m, "PlacedBrainrot")`) — лишняя проверка на каждой итерации.
- `BaseSwap` итерирует `base.Visual` и шелл напрямую — не задело бы, но defensive: меньше путей пересечения.

### Почему prompt уничтожается, а не disable'ится

- `setPromptsEnabled(model, false)` при carry **выключает все prompts** включая `TakeBackPrompt`.
- При последующем drop в лабиринте (`dropTop` → `setPartsDroppedState` → `setPromptsEnabled(model, true)`) — все prompts re-enable, включая «Забрать». Лежащий в лабиринте брейнрот не должен показывать «Забрать» (он не на базе ни у кого).
- Уничтожение prompt'а в `takeBackFromBase` ДО lifecycle transition гарантирует, что только обычный maze-prompt вернётся.
- При повторном размещении `bindPlacedModel` создаёт свежий `TakeBackPrompt` (новый Triggered-connection).

### Почему случайный slot, а не «тот же что был»

- Re-place идёт через стандартный [`tryPlaceRandom`](../src/ServerScriptService/BrainrotDelivery.server.lua) — `findFreeSlot` отдаёт младший свободный. Если игрок забрал слот 3 и принёс нового, новый встанет в слот 3 (если он младший свободный) или младший меньше (если 1 или 2 свободны).
- Не делаем «вернуть в тот же слот»: это требует хранить «пожелание» на стороне carry-стека, и ломает простоту `findFreeSlot`. Игрок не замечает разницу — слоты на одном этаже визуально близко.

---

## Граничные случаи

| Ситуация | Поведение |
|---|---|
| Игрок целится на чужого placed-брейнрота, жмёт E | Prompt активируется, server-check `PlacedBy != player.Name` → no-op без логов (тихий отказ; spam-лог при попытке "забрать чужого" не нужен) |
| Carry-стек полон, игрок целится на своего | Prompt активируется, server-check `countCarry >= getMaxCarry` → лог `take-back rejected: carry full (X/Y)`, no-op |
| Take-back во время BaseSwap (апгрейд капасити) | `model.Parent = base`, `BaseSwap` не трогает direct-children базы (только `base.Visual`) → take-back проходит штатно |
| Take-back во время автосейва | `SaveService.buildSnapshot` фильтрует по тегу `PlacedBrainrot`. Если тег уже снят (lifecycle transition прошёл) — модель не попадёт в snapshot. Race-окно ~1ms, не материально |
| Игрок умер с забранным брейнротом в руках | `BrainrotPickup.destroyAllCarried` стандартно уничтожает (как и обычные picked-up); brainrot теряется (по дизайну) |
| Player покинул сервер с забранным | `BrainrotPickup` `Players.PlayerRemoving` → `destroyAllCarried`. Уничтожается. SaveService на leave не успевает сохранить (модель уже в Destroyed state, тегов нет) |

---

## Что НЕ сделано (опционально, не блокер)

- **Анимация take-back.** Сейчас брейнрот мгновенно появляется на голове. Можно добавить tween (CFrame от base-позиции к head-anchor за 0.3с) для соковости. Не делал — мгновенный pickup согласован со стандартным maze-pickup.
- **Sound на take-back.** Сейчас нет звука. Maze-pickup тоже без звука (только trap-hit и delivery), так что согласовано.
- **Серверный rate-limit.** Game-теоретически безвредно (take-back ничего не даёт сверх инвертирования placement), но при 1000+ запросов в секунду через эксплоит — лишняя CPU-нагрузка. Если будет видно в логах — добавить debounce 0.2с per-player.
- **Per-player visibility prompt'а.** Сейчас «Забрать» показывается всем в радиусе. Не-владельцы видят и могут жать (отказывается server). Чтобы скрыть — `ProximityPromptService.PromptShown` в LocalScript с фильтром по `PlacedBy == LocalPlayer.Name`. Не делал — visual-noise низкий (на чужой базе игрок редко).

---

## Acceptance criteria ✅

1. ✅ Принёс брейнрота, поставил на свою базу, подошёл, нажал E → брейнрот на голове, слот свободен.
2. ✅ Прицелиться надо именно на брейнрота — без аима E делает обычный place / drop.
3. ✅ Чужой игрок не может забрать твоих брейнротов (server-check).
4. ✅ Carry-стек полный — take-back не проходит, лог в консоли.
5. ✅ После take-back брейнрот можно снова поставить на базу через E (стандартный place).
6. ✅ Income перестаёт капать с забранного на следующий tick.
7. ✅ После save/load (выйти-зайти): забранный (если игрок не размещал заново до выхода) — теряется. Размещённые — рехидрируются на свои слоты.
