# Инвентарь — реализация

## Цель

Реализовать клиентский экран инвентаря по спеке [Game Design/Inventory.md](../Game%20Design/Inventory.md). Игрок видит, что у него стоит на базе: список брейнротов с группировкой по rarity, счётчик `placed/capacity`, суммарный доход/сек.

Тоггл по `I` или кнопкой под Shop'ом. Источник данных — теги `PlacedBrainrot` + атрибуты `PlacedBy`/`Rarity`/`Capacity`/`Vip` (всё уже реплицируется клиенту, новых RemoteEvent'ов **не нужно**).

---

## Что уже есть в проекте

Костяк готов — инвентарь это в основном чтение:

- **Тег `PlacedBrainrot`** ставится `BrainrotLifecycle.transition(model, Placed, …)`. Источник истины для «что стоит на базе».
- **Атрибуты на placed-модели**:
  - `PlacedBy` — ник владельца (выставляет `BrainrotLifecycle`).
  - `PlacedOnBase` — имя `bazapl_` (на всякий случай, в инвентаре не используем).
  - `Rarity` — наследуется от шаблона `ServerStorage.BrainrotTemplates`.
  - `SlotIndex` — порядковый номер слота (для будущего click-to-locate).
- **Атрибут `Capacity` на базе** — выставляет `UpgradeService.applyBaseCapacity` после покупки слота в магазине. На клиенте читается напрямую (база — `bazapl_` с `Owner == LocalPlayer.Name`).
- **Атрибут `Vip` на базе** — для ×2 множителя дохода (см. [Base.md § VIP Base](../Game%20Design/Base.md)).
- **`ReplicatedStorage.BrainrotConfig`** — `getIncome(model)` уже учитывает имя и rarity-fallback. Доступен с клиента (ModuleScript в ReplicatedStorage).
- **`StarterPlayerScripts.ShopClient.client.lua`** — готовый референс для UI (стиль кнопки, frame, header, layout, live-обновление). Копируем компоновку, заменяем содержимое строк.

Чего нет:

- Палитры цветов rarity и порядка тиров — заводим в `BrainrotConfig`.
- Сам клиентский скрипт инвентаря.

---

## Функциональные требования

1. **Тоггл**: кнопка в правом верхнем углу под `Shop` + клавиша `I`. Открыто/закрыто переключается одинаково.
2. **Шапка**: `<placed>/<capacity> slots · +<sum>/sec total`. Capacity и сумма обновляются live, пока инвентарь открыт.
3. **Группы по rarity**: Gogly → Mythic → Legendary → Epic → Rare → Common. Заголовок группы = цветная плашка + название тира. Группы с count=0 **скрыты** (без пустых заголовков).
4. **Внутри группы — сортировка** по убыванию дохода/шт; при равенстве — алфавит по имени.
5. **Row**: `<name>  ×<count>   +<row_income>/s`, где `row_income = count × per_brainrot_income × vipMul`.
6. **Live-обновления** (только пока инвентарь открыт):
   - Новый `PlacedBrainrot` появился (своя tag-add) → ререндер.
   - `PlacedBrainrot` пропал (tag-remove или модель уничтожена) → ререндер.
   - `Capacity` базы изменился → ререндер шапки.
   - `Vip` базы изменился → ререндер чисел.
   - `Owner` любой `bazapl_` стал = LocalPlayer.Name → пересохранить ссылку на свою базу + ререндер.
7. **Дребезг ререндера** через `task.defer` — серия из 14 rehydration-сигналов даёт **один** ререндер.
8. **Пустая база** — центрированный текст `Empty. Place a brainrot to start earning.` вместо списка.
9. **Чужая база** — фильтр `PlacedBy == LocalPlayer.Name` гарантирует, что показываем только свои брейнроты, независимо от того, рядом с какой базой стоит игрок.
10. **Серверной части нет.** Никаких RemoteEvent'ов, мутаций `PlayerData`, серверных скриптов.

---

## Решённые вопросы

1. **Источник Capacity для шапки** — атрибут `Capacity` на базе игрока, читаем напрямую с клиента. Альтернатива (мирорить в player-attribute) отвергнута: лишнее место синхронизации, клиент и так находит свою базу через Owner.
2. **Источник суммы дохода** — клиентский расчёт по тем же формулам, что серверный `BrainrotDelivery.income tick`: `sum(getIncome(M) × vipMul) for M in tagged where PlacedBy == self`. В нормальной репликации совпадает с сервером; если разойдётся — это сигнал бага в репликации, не баг инвентаря.
3. **3D-превью отложено** в Future — ViewportFrame по 5–8 шт. на кадр может просесть FPS на слабых девайсах. MVP без превью.
4. **Сортировка тиров** — Gogly выше Mythic (Gogly = топ по доходу: 1000–10000/сек). Внутри тира — по убыванию дохода/шт.
5. **Цвета rarity** — стандартная RPG-палитра (см. таблицу в спеке). Если у проекта появится своя бренд-палитра — поменяем константу в `BrainrotConfig.rarityColor`, не трогая остальной код.
6. **Кейс «несколько баз» (vipbase, ADMINBASE)** — игнорируем, ищем только `bazapl1..4`. ADMINBASE — отладочная, vipbase — это визуальный шаблон, не slot-база.

---

## Подзадачи (порядок реализации)

### 1. Палитра rarity в BrainrotConfig

- [ ] В `src/ReplicatedStorage/BrainrotConfig.lua` добавить:
  - `BrainrotConfig.rarityColor = { Common = Color3.fromRGB(156,163,175), Rare = Color3.fromRGB(34,197,94), Epic = Color3.fromRGB(59,130,246), Legendary = Color3.fromRGB(249,115,22), Mythic = Color3.fromRGB(168,85,247), Gogly = Color3.fromRGB(250,204,21) }`
  - `BrainrotConfig.rarityOrder = {"Gogly","Mythic","Legendary","Epic","Rare","Common"}` — порядок отображения групп сверху вниз.
- [ ] Проверить, что таблица не ломает существующие чтения (`getIncome` не зависит от новых полей).

### 2. UI-каркас InventoryClient

- [ ] Создать `src/StarterPlayerScripts/InventoryClient.client.lua`. Скопировать структуру `ShopClient.client.lua`:
  - `ScreenGui` (`ResetOnSpawn = false`).
  - Toggle button — `Position = UDim2.new(1, -140, 0, 160)` (под Shop, который на 100). Текст `🗂 Inventory [I]`.
  - Main frame — размер ~`420×500`, центрированный.
  - Header bar с заголовком + close `✕`.
  - Под header — single-line `summaryLabel` (для `<placed>/<capacity> slots · +<sum>/sec`).
  - Под ним — `ScrollingFrame` (`itemsContainer`) с `UIListLayout`, `AutomaticCanvasSize = Y`, `CanvasSize = UDim2.new(0,0,0,0)`.
- [ ] Toggle: `MouseButton1Click` на toggleBtn + `UserInputService.InputBegan` на `KeyCode.I` (с `processed` гейтом).
- [ ] Close button: скрывает frame.

### 3. Поиск своей базы

- [ ] Функция `findOwnBase()`:
  ```lua
  for _, name in {"bazapl1","bazapl2","bazapl3","bazapl4"} do
    local b = workspace:FindFirstChild(name)
    if b and b:GetAttribute("Owner") == player.Name then return b end
  end
  return nil
  ```
- [ ] Кеш ссылки на базу + подписка на `GetAttributeChangedSignal("Owner")` для каждой `bazapl_` — как только Owner становится своим, обновляем кеш + ререндер. Аналогично если Owner ушёл (база отдана) — сбрасываем кеш.

### 4. Сбор snapshot'а

- [ ] Функция `collectInventory()` возвращает структуру:
  ```
  {
    capacity = 14,
    placed = 7,             -- сколько уникальных моделей
    totalIncome = 247,
    groups = {
      Mythic = { totalIncome = 200, items = { {name="Alessio", count=1, income=200, perItem=200}, … } },
      Legendary = { … },
      …
    }
  }
  ```
- [ ] Итерировать `CollectionService:GetTagged("PlacedBrainrot")`, фильтровать `PlacedBy == player.Name and m.Parent ~= nil`.
- [ ] Группировать по name + rarity. Считать count, perItem income (`BrainrotConfig.getIncome(m)`), groupIncome, totalIncome.
- [ ] Учитывать VIP: если у базы `Vip == true`, умножать perItem income на 2 (это соответствует тому, что считает `BrainrotDelivery`).

### 5. Рендер

- [ ] Функция `render()`:
  - Очистить `itemsContainer:GetChildren()` кроме `UIListLayout`.
  - Обновить `summaryLabel` из `collectInventory()`.
  - Если `placed == 0` — показать `Empty. Place a brainrot to start earning.` (можно отдельный label, который Visible/Hidden) — без рендера групп.
  - Иначе для каждого rarity в `BrainrotConfig.rarityOrder`:
    - Если `groups[rarity]` пуст или nil — пропустить.
    - Создать заголовок group (Frame с `BackgroundColor3 = rarityColor` + label `name`).
    - Сортировать `items` по `perItem` desc, потом по name asc.
    - Создать row для каждого item: Frame с тремя TextLabel'ами (имя, `× count`, `+income/s`).
- [ ] Стиль row'ов — копировать визуал из `ShopClient.itemRows`, упрощённый (no buy-button).

### 6. Подписки и debounced re-render

- [ ] Флаг `pendingRender = false`. Функция `scheduleRender()`:
  ```lua
  if pendingRender or not frame.Visible then return end
  pendingRender = true
  task.defer(function()
    pendingRender = false
    if frame.Visible then render() end
  end)
  ```
- [ ] Подписки:
  - `CollectionService:GetInstanceAddedSignal("PlacedBrainrot"):Connect(scheduleRender)`.
  - `CollectionService:GetInstanceRemovedSignal("PlacedBrainrot"):Connect(scheduleRender)`.
  - На каждой `bazapl_`: `GetAttributeChangedSignal("Owner"):Connect(...)` — обновить кеш базы и `scheduleRender`.
  - На своей базе (после resolve): `GetAttributeChangedSignal("Capacity"):Connect(scheduleRender)`, `GetAttributeChangedSignal("Vip"):Connect(scheduleRender)`. Перевешиваются при смене кешированной базы.
- [ ] Открытие frame'а вызывает `render()` сразу (минуя debounce).
- [ ] Закрытие frame'а — ничего, подписки остаются (re-render no-op в `scheduleRender`).

### 7. Регистрация в HUD

- [ ] Проверить, что Toggle-кнопка не пересекается с Shop'ом (Shop на `Y = 100`, Inventory на `Y = 160`).
- [ ] Логировать готовность: `print("[InventoryClient] ready (toggle: button or [I])")`.

### 8. Smoke-тест в Studio

- [ ] Play, заспавнить пару брейнротов в лабиринте, принести на базу, сдать.
- [ ] Открыть инвентарь по `I` — список совпадает с физикой.
- [ ] Купить слот — Capacity в шапке обновился.
- [ ] /vip on (если есть chat-команда) или вручную выставить `base:SetAttribute("Vip", true)` — ×2 в income-числах.
- [ ] Leave + rejoin — после rehydration инвентарь показывает всё, что было.
- [ ] Сдать на полную базу (cap=10, 10 placed, 11-й отказ): инвентарь не двигается, никаких ошибок в Output.

---

## Граничные случаи

- **Игрок зашёл, базы ещё нет** (BaseManager не успел назначить) — `findOwnBase() == nil`, шапка показывает `0 / ?? slots · +0/sec`, список пуст. Подписка на `Owner` всех `bazapl_` подхватит назначение и пересоберёт.
- **База удалена/Owner снят** — `findOwnBase()` теряет ссылку, header → `0 / ??`, список пуст (фильтр `PlacedBy == self` всё ещё работает, но без базы Capacity недоступен).
- **Server-rehydration** на joining'е (несколько `PlacedBrainrot` сразу) — каждый сигнал планирует render через `task.defer`, в итоге один render на всю серию.
- **Rapid placing** — 5 быстрых сдач за секунду → один debounced render, не 5.
- **Большой инвентарь** (cap=30, 6+ разных видов) — ScrollingFrame с auto canvas, прокрутка работает.
- **VIP куплен в середине сессии** — `GetAttributeChangedSignal("Vip")` подхватит, числа пересчитаются.
- **Чужой брейнрот рядом** (например, на чужой базе) — фильтр `PlacedBy == self` отсекает, в инвентаре не появится.

---

## Acceptance criteria

Задача закрыта, когда:

1. ✅ Кнопка `🗂 Inventory` видна под Shop'ом, клавиша `I` открывает/закрывает.
2. ✅ Сразу после старта (с пустой базой) открытие показывает `Empty. Place a brainrot to start earning.`
3. ✅ Сдал 1 брейнрота — открыл инвентарь — видна одна строка с правильными name/count/income, шапка `1 / 10 slots · +X/sec`.
4. ✅ Сдал ещё 2 одинаковых — строка стала `× 3` с утроенным income.
5. ✅ Сдал брейнрота другого rarity — появилась новая группа в правильном месте по тиру.
6. ✅ Купил слот в Shop'е — шапка обновилась `<N> / 11 slots`.
7. ✅ Включил VIP (атрибут `Vip = true` на базе) — все income-числа удвоились, total в шапке тоже.
8. ✅ Leave + rejoin — после rehydration инвентарь показывает то же, что до выхода.
9. ✅ Подошёл к чужой базе с расставленными брейнротами — открыл инвентарь — видны мои, не их.
10. ✅ В Output нет ошибок и warning'ов от InventoryClient.

---

## Что ЯВНО вне скоупа этой задачи

- 3D-превью моделей (ViewportFrame).
- Click-to-locate (камера на конкретный экземпляр).
- Sell from inventory.
- Drag-reorder слотов.
- Filter / search по rarity или имени.
- Diff highlight (новые брейнроты подсвечены после открытия).
- Серверные RemoteEvent'ы для инвентаря — не требуются, всё на репликации тегов.
- Изменение `BrainrotLifecycle` или `PlayerData` — данные уже там, чего не хватает — добавляется на клиенте.
