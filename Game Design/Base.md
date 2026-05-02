# База

Персональная площадка игрока, на которую он приносит брейнротов. Размещённые брейнроты дают пассивный доход (см. [Brainrots.md](Brainrots.md)). База расширяется поштучной покупкой слотов в [магазине](Shop.md). Когда счётчик слотов пересекает границу диапазона, **визуальная модель базы заменяется** на более крупную.

---

## Структура

- Старт — 10 слотов на ground floor.
- Каждая покупка в магазине = +1 слот.
- При выходе за 10 (cap=11) появляется второй этаж; при выходе за 20 (cap=21) — третий.
- Шелл `bazapl1..4` (имя/Owner/SpawnPoint/Capacity) сохраняется при смене визуала; заменяется только Visual-контент.

Визуал базы привязан к диапазонам Capacity (`BaseSwap.server.lua`, `levelFromCapacity = ceil(cap/10)`):

| Capacity | Модель | Где живёт |
| --- | --- | --- |
| 10 | стартовый шелл `bazapl1..4` (без подмены) | `Workspace` |
| 11..20 | `baza5` (содержит Floor2) | `ServerStorage.BaseModels` |
| 21..30 | `bazalvl3` (содержит Floor2 + Floor3) | `ServerStorage.BaseModels` |

---

## Прогрессия

Поштучная покупка слотов. Каждая покупка = +1 слот, цена фиксированная (см. [Economy.md](Economy.md) §4 и [UpgradeConfig.lua](../src/ReplicatedStorage/UpgradeConfig.lua), трек `baseCap`).

- `getMaxLevel("baseCap") = 21` → уровни 1..21 = 10..30 слотов.
- Старт `baseLvl = 1` (10 слотов, бесплатно).
- Дальше — максимум 30 слотов (`baseLvl = 21`). Кнопка в магазине отключена при достижении max.

---

## Размещение брейнротов

Слоты — фиксированная сетка **5×2 на этаж** (10 слотов на этаж):

- `SlotIndex` 1..N глобальный по базе. Этаж = `ceil(SlotIndex/10)` (1..10 → ground, 11..20 → Floor2, 21..30 → Floor3).
- Внутри этажа: `col = (localIdx-1) % 5`, `row = floor((localIdx-1) / 5)`.

**Триггер — клавиша `E` на своей базе.** Бывшая Touched-механика ("шагнул на пол базы → автоматическая сдача") убрана, потому что:
- провоцирует случайные сдачи: игрок шёл через базу транзитом и неожиданно расстался с брейнротом;
- мешает зайти на собственную базу полюбоваться на доход без сдачи;
- две системы сдачи (Touched + E-drop) дают баги конфликта.

`E` теперь имеет дуальное поведение:
- **Игрок на своей базе** (Owner == player) → сдача одного брейнрота в слот базы.
- **Где угодно ещё** → обычный дроп (модель падает перед игроком, см. [`BrainrotPickup.dropTop`](../src/ServerScriptService/BrainrotPickup.server.lua)).

**Какой именно брейнрот сдаётся:** **случайный** из текущего carry-стека игрока. Не топ. Это снимает вопрос "как выбрать какого" — нет UI, нет number-keys, никаких меню. Сторонний эффект — игроку не нужно беспокоиться о порядке пикапа: какой выпадет — какой выпадет. (Если позже в плейтесте окажется что игроки хотят выбирать осознанно — добавим клик-меню по carry-стеку, но это отдельная фича.)

**Алгоритм сдачи** ([`BrainrotDelivery.tryPlaceRandom`](../src/ServerScriptService/BrainrotDelivery.server.lua), вызывается на `OnServerEvent` от клиентского E):

1. Проверка владельца: `base:GetAttribute("Owner") == player.Name`. Иначе — fallback в `BrainrotPickup.dropTop` (обычный дроп).
2. `placedCount(base) < Capacity` — иначе брейнрот не сдаётся, остаётся в руках. Fallback: можно либо ничего не делать (игрок не понимает), либо сделать обычный дроп. Выбираем "ничего не делать" + клиентский HUD-хинт "База полная".
3. `BaseSlots.findFreeSlot(base, placed)` — ищет младший свободный `SlotIndex` в `[1..Capacity]`. Занятые слоты — те, у кого на placed-модели стоит атрибут `SlotIndex`. Если все заняты — то же что (2).
4. **Случайный выбор**: `idx = math.random(1, PlayerData.countCarry(player))`, `entry = PlayerData.removeCarryAt(player, idx)`. Снимаем head-weld, anchored=true, prompts off.
5. Ставим `SlotIndex` атрибут на модель, считаем target CFrame через `BaseSlots.slotPositionInBase(base, model, slotIndex)` **до** `model.Parent = base` (иначе bbox базы распухнет на parts модели в carry-позиции).
6. `model.Parent = base`, `model:PivotTo(target)`, `BrainrotLifecycle.transition(...)` → ставит тег `PlacedBrainrot` + атрибуты `PlacedBy`/`PlacedOnBase`.

**Маршрутизация E** ([`BrainrotInput.client.lua`](../src/StarterPlayerScripts/BrainrotInput.client.lua) → server):
- E-press на клиенте всегда фаерит один и тот же `RemoteEvent` (например, `DropOrPlaceBrainrot`, объединённый с прежним `DropBrainrot`).
- Сервер на приёме определяет: игрок стоит на своей базе → tryPlaceRandom, иначе → dropTop.
- "Стоит на базе" = `RaycastParams` под `HumanoidRootPart` либо проверка `player.Character`'s position относительно bbox каждой `bazapl_`. Решаем геометрически на сервере, не доверяя клиентскому флагу.

**Геометрия слота** ([`BaseSlots.slotPositionInBase`](../src/ServerStorage/BaseSlots.lua)):

- **Источник X/Z позиции — явные маркеры в Studio**, расставленные дизайнером. Это `Part`-ы с `Name="slot"`. Подходит любая иерархия (например, `bazapl_.slots.slots.slot` или `baza5.slots.slots.slot`). Никакой явной метки этажа не надо — этажи определяются по Y-координате маркеров (см. ниже).
- **Где ищем маркеры**:
  1. Если у базы есть `base.Visual` (после `BaseSwap` клонирует `baza5`/`bazalvl6`) — все маркеры берутся ОТТУДА. Шелл `bazapl_` визуально hide'нут — его маркеры игнорируем.
  2. Если Visual нет (L1, cap=10) — берём из самого `base` (`bazapl_`).
- **Этажи через Y-binning**: маркеры группируются по Y (бин 5 студ для шумоустойчивости), бины сортируются по возрастанию: bin[1] = Floor 1, bin[2] = Floor 2, bin[3] = Floor 3. Этаж определяется ВЫСОТОЙ маркера, а не его местом в дереве. Дизайнеру не нужно ставить отдельные `Floor2`-папки — достаточно поставить маркер выше остальных.
- **SlotIndex внутри этажа** — детерминированная сортировка по `(X, потом Z)`. Designer может класть маркеры в дереве в любом порядке — `findFreeSlot` всегда даст один и тот же мапинг 1..N.
- **Правило "1 маркер = 1 слот = 1 брейнрот"**. Capacity attribute задаёт верхнюю границу прокачки (10..30), фактическая позиция — у маркера. Если `Capacity > #markers` — слоты сверх количества маркеров не используются.
- **Top Y этажа** — берётся от Y маркера в группе (маркер.Y совпадает с поверхностью пола: на bazapl1 маркеры Y=25.5, на template baza5 — Y=0.2 и Y=22.2; после `alignBottomsTo` обе высоты смещаются на одну дельту, инвариант сохраняется). Если на этаже маркеров нет — fallback на `SpawnPoint.Y` (Floor 1) или `Floor%d` bbox (Floor 2+).
- **PivotTo по bbox-центру** (а не pivot модели): `pivotCF + (target - bcf.Position)`, где `target = (marker.X, topY + bsz.Y/2 + 0.1, marker.Z)`. У шаблонов брейнротов pivot часто смещён от bbox-центра на несколько студов — наивный `PivotTo` поставит pivot в слот, а парты сбоку.
- **Fallback: алгоритмическая сетка 5×2**, pitch 7, центр на `SpawnPoint`. Используется если на этаже нет маркеров (например, у `bazalvl6` пока нет slot-разметки для Floor 3) или у не-размеченных баз.

⚠️ **Шаблоны брейнротов должны быть чистыми**: все BasePart'ы шаблона ≤ ~10 студов от `PrimaryPart`. Стрэй-Part'ы в шаблонах распухают bbox и ломают `target = bcf + ...` логику. Пример найденного бага: в `ServerStorage.BrainrotTemplates["Lirilì Larilà"].Cube.002.Part` лежал забытый кубик в 79 студах от RootPart — bbox раздувался до 80×14×26 (вместо реальных 4×10×8).

**Rehydration** ([`BrainrotDelivery.tryRegisterPlaced`](../src/ServerScriptService/BrainrotDelivery.server.lua), вызывается на `CollectionService:GetInstanceAddedSignal("PlacedBrainrot")`):

- Восстановленный SaveService'ом брейнрот приходит с тегом `PlacedBrainrot` и атрибутами `PlacedBy`/`PlacedOnBase`, но без `SlotIndex`.
- Назначаем младший свободный `SlotIndex` (порядок rehydration сохраняет исходный порядок размещения) и сразу `model:PivotTo(BaseSlots.slotPositionInBase(...))` — переезжаем в актуальную сетку. Сохранённая `cframe` могла быть из старой формулы (random или buggy template) — оставлять её = брейнрот висит вне базы.

**При апгрейде базы** (`Capacity` растёт) уже размещённые брейнроты остаются на тех же `SlotIndex`-ах (атрибут не пересчитываем). Новые слоты вверху диапазона свободны → новые брейнроты заполняют их по очереди.

---

## Снятие брейнрота с базы (take-back)

**Зачем.** Игрок принёс новый, более доходный брейнрот, а на базе все слоты заняты низко-доходными. Чтобы не делить доход «между всеми» и не давать «всё или ничего», даём возможность освободить слот — снять старого брейнрота обратно в руки, потом поставить нового.

**Триггер — `E` с прицелом на брейнрота на базе.** Реализация через `ProximityPrompt`:

- На каждой placed-модели висит `ProximityPrompt` (имя `TakeBackPrompt`, `ActionText="Забрать"`, `KeyboardKeyCode=E`, `MaxActivationDistance=8`, `RequiresLineOfSight=true`).
- Когда игрок подходит и **смотрит** на конкретного брейнрота — prompt активируется, в HUD появляется «[E] Забрать».
- E без прицела (на пустую часть базы / с края) — обычное `tryPlaceRandom` / drop. Конфликт между двумя «E на базе» (place vs take-back) автоматически разрешается Roblox-механикой `gameProcessedEvent`: при активации prompt'а `BrainrotInput.client` (там `if processed then return end`) пропускает `DropBrainrot:FireServer`. Только сервер-сайд `takeBackFromBase` срабатывает.
- Только владелец (`PlacedBy == player.Name`) может забрать своего. Чужой игрок видит prompt, но сервер отклоняет с no-op.

**Алгоритм** ([`BrainrotPickup.takeBackFromBase`](../src/ServerScriptService/BrainrotPickup.server.lua)):

1. Owner-check (`PlacedBy`) и state-check (`PlacedBrainrot` тег ещё на модели — защита от race).
2. Capacity-check carry-стека: `PlayerData.countCarry(player) < getMaxCarry(player)`. Иначе лог `take-back rejected: carry full`, no-op.
3. Уничтожаем `TakeBackPrompt` на primary part — иначе `setPromptsEnabled(true)` при следующем дропе включит «Забрать» на брейнроте, лежащем в лабиринте (UX-баг: чужой брейнрот в лабиринте показывает «Забрать», нажатие игнорируется server-side).
4. `model.Parent = workspace` — выезжаем из base-иерархии.
5. Carry rig: anchor part над головой, `BRHeadWeld` (anchor↔head), `BRMainWeld` (anchor↔primary), `setPartsCarriedState` (Anchored=false, CanCollide=false, Massless=true), `setPromptsEnabled(false)`.
6. `PlayerData.removePlaced(player, model)` + `PlayerData.pushCarry(player, {model, anchor})`.
7. `BrainrotLifecycle.transition(model, Carried, {player})` — `PlacedBrainrot`→`Brainrot` тег-свап, `Picked` BindableEvent (так что spawner pad не реагирует — модель не клон с pad-а).

**Состояние после take-back:**

- `PlayerData.placed[owner]` — без этой модели.
- `PlayerData.carrying[player]` — модель в стеке.
- Income-tick: `m.Parent` = workspace, нет `PlacedBrainrot` тега → пропускается. Доход с этого брейнрота прекращается на следующий тик.
- SaveService.snapshotPlaced: фильтрует по `PlacedBrainrot` тегу — модель в снапшот не попадает. На leave/autosave старая запись перезатирается без неё.

**Re-place того же брейнрота:**

- Игрок несёт, шагает на базу, жмёт E (без аима) → `tryPlaceRandom` ставит брейнрота в **первый свободный слот** (не обязательно тот же, где стоял).
- `bindPlacedModel` (на `PlacedBrainrot` тег-сигнал) пересоздаёт `TakeBackPrompt` свежим — старый Triggered-connection умер вместе с уничтоженным prompt'ом.

**Неэффективные стратегии:**

- Поставить → забрать → поставить → забрать в цикле — ничего не даёт, доход не складывается, занятие слота счётом не идёт. Только время игрока на анимацию пикапа.
- Take-back чужих брейнротов через эксплоит — server-side check на `PlacedBy` блокирует.

---

## Чужие базы

(дублирует [Main Game Design.md](Main%20Game%20Design.md), вынесено сюда для самодостаточности)

- Чужие базы видны в мире.
- Взаимодействовать с чужими брейнротами нельзя — забрать или потрогать может только владелец.
- Пассивный доход начисляется только владельцу.

---

## Визуальное различение баз

**Проблема.** Когда игрок бежит из лабиринта с брейнротом, он должен сходу понимать, какая из четырёх баз — его. Номер `bazapl1..4` ему ничего не говорит, владельцы меняются между сессиями.

**Решение — `BillboardGui` с ником владельца над каждой базой.**

- Над каждой базой висит таблица с `DisplayName` владельца.
- Текст окрашен в персональный цвет игрока (детерминированно по `UserId` либо по индексу слота при назначении Owner — главное, чтобы у разных игроков на сессии цвета не совпали).
- Виден издалека (`AlwaysOnTop = true`, `MaxDistance` ~ размер карты).
- Если у базы нет владельца (никто не занял слот) — метка скрыта или показывает «свободно».

**Почему именно так.** Метка следует за атрибутом `Owner`, а не за номером базы — поэтому игрок не должен запоминать «я зелёный с базой №3» каждый раз заново. Статичная раскраска `bazapl1..4` (4 фиксированных цвета на модели) проще и красивее издалека, но ломается при смене владельца между сессиями.

**Опционально (nice-to-have).** Пока игрок несёт брейнрота, на его HUD подсвечивается ник/цвет его базы — и/или указатель/стрелка в сторону базы. Это уже про навигацию, не про идентификацию; решаем после базовой метки.

---

## Реализация (для разработчика)

- **Конфиг**: [`UpgradeConfig.lua`](../src/ReplicatedStorage/UpgradeConfig.lua), трек `baseCap`. 21 уровень (lvl 1 = 10 слотов бесплатно, lvl 2..21 = 11..30 слотов по 500 монет за слот).
- **Применение апгрейда**: [`UpgradeService.server.lua`](../src/ServerScriptService/UpgradeService.server.lua) пишет атрибут `Capacity` (10..30) на парт `bazapl1..4`.
- **Подмена визуала**: [`BaseSwap.server.lua`](../src/ServerScriptService/BaseSwap.server.lua) подписан на изменение `Capacity`, прячет визуал предыдущего уровня и клонирует модель текущего уровня в дочернюю папку `Visual`. Маппинг — `levelFromCapacity = ceil(cap/10)`, диапазоны 10 / 11..20 / 21..30.
- **Слоты — геометрия**: [`BaseSlots.lua`](../src/ServerStorage/BaseSlots.lua) (ModuleScript). Чистый модуль без знания о владельце — функции `getCapacity`, `findFreeSlot(base, placedList)`, `slotPositionInBase(base, model, slotIndex)`. Сетка 5×2/этаж, рекурсивный поиск `Floor%d` для Floor 2+, PivotTo по bbox-центру.
- **Сдача брейнротов и income tick**: [`BrainrotDelivery.server.lua`](../src/ServerScriptService/BrainrotDelivery.server.lua) (тег `PlacedBrainrot`). Триггер сдачи — `RemoteEvent` от клиента, фаерится клавишей `E`. Сервер проверяет: если игрок стоит на своей базе → `tryPlaceRandom` (1 случайный брейнрот из carry-стека → слот). Иначе → fallback в [`BrainrotPickup.dropTop`](../src/ServerScriptService/BrainrotPickup.server.lua) (обычный дроп). Использует `BaseSlots` для всей геометрии.
- **Маршрутизация E** ([`BrainrotInput.client.lua`](../src/StarterPlayerScripts/BrainrotInput.client.lua)): на E фаерит один RemoteEvent (объединённый `DropOrPlaceBrainrot`). Решение place-vs-drop принимает сервер по геометрии (raycast/bbox check относительно `bazapl_`), не клиент.
- **Метка владельца над базой**: [`BaseLabel.server.lua`](../src/ServerScriptService/BaseLabel.server.lua) слушает изменение атрибута `Owner` на `bazapl1..4`, создаёт/обновляет `BillboardGui` с `DisplayName` владельца. Цвет — детерминированный хеш по `UserId` из палитры из 8 цветов, с разрешением коллизий между активными базами (если уже занят — берётся следующий свободный). Также подписывается на `Capacity` (BaseSwap меняет Visual → высота bbox меняется → `defer`-ом репозиционируем якорь). Без `Owner` — `gui.Enabled = false`.

---

## VIP Base

Премиум-вариант базы за Robux. Меняет визуал и даёт умеренный бонус к доходу — мотивация для тех, кто хочет поддержать игру и выделиться визуально, не ломая прогрессию обычных игроков.

### Что даёт

- **Визуал.** Своя серия моделей `vipbase1`, `vipbase2`, `vipbase3` (по одной на каждый уровень — VIP-визуал работает с L1 сразу, не только на старших уровнях). Стиль — золото / огни / эффекты, на усмотрение арта.
- **Бонус к доходу: ×2** ко всем брейнротам, размещённым на VIP-базе. Применяется после `BrainrotConfig.getIncome` в income-тике [`BrainrotDelivery`](../src/ServerScriptService/BrainrotDelivery.server.lua).
- **Прогрессия и слоты — те же, что у обычной базы**: 10 / 20 / 30 слотов, max 3 уровня. VIP не отменяет апгрейды — слоты по-прежнему покупаются за монеты.

### Покупка

- **GamePass** (одноразовая покупка через `MarketplaceService`). Lifetime — после покупки активен на аккаунте навсегда.
- **Цена: 67 Robux.**
- ID GamePass — TBD (создаётся в Roblox Creator Hub).
- Покупка проверяется на каждом заходе: `MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)`. Результат кешируется в атрибут `VipBase` на игроке.
- В магазине — отдельная секция «Премиум База» (или хотя бы выделенная карточка с иконкой Robux), чтобы не путаться с обычными апгрейдами за монеты.

### Эффект на существующую логику

- [`BaseSwap`](../src/ServerScriptService/BaseSwap.server.lua) при подмене визуала выбирает шаблон по атрибуту владельца базы: `VipBase=true → vipbase{lvl}`, иначе `baza{lvl}`. Маппинг расширяется новой таблицей в скрипте.
- [`BrainrotDelivery`](../src/ServerScriptService/BrainrotDelivery.server.lua) в income-тике умножает доход на ×2, если `base:GetAttribute("Vip") == true`. Атрибут проставляется при назначении владельца, если у того есть GamePass.
- Если игрок купит VIP в середине сессии — `BaseSwap` пересоздаёт визуал немедленно (через тот же канал, что и обычный апгрейд).
