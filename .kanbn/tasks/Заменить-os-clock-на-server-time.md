---
created: 2026-04-27T07:00:00.000Z
---

# Заменить os.clock на server time

`BrainrotDelivery.lastDelivery[player] = os.clock()` для дебаунса. `os.clock` — process CPU time, может прыгать при server hiccups, не синхронизирован между серверами.

Лучше `workspace:GetServerTimeNow()` (синхронизированное серверное время, в секундах с Unix epoch). Мелочь, но при кросс-сервер логике (например, общий маркетплейс) важно.

Грепнуть проект на `os.clock`/`tick()` и заменить везде где есть.
