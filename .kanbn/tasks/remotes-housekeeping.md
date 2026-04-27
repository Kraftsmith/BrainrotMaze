---
created: 2026-04-27T07:00:00.000Z
---

# Remotes housekeeping

В `ReplicatedStorage` 11 RemoteEvent'ов на верхнем уровне без структуры. Среди них **дубликат `BuyGearEvent` × 2** — реальный баг. Хэндлеры не валидируют аргументы и не проверяют auth.

Что сделать:
1. Удалить дубликат `BuyGearEvent`.
2. Создать `ReplicatedStorage.Remotes` с под-папками `Brainrot/`, `Shop/`, `Admin/`. Перенести существующие.
3. Написать обёртку `RemoteHandler.secure(event, schema, handler)` — проверяет типы аргументов и явную авторизацию. Перевести все хэндлеры на неё.

Без этого первый же exploit (Shop без проверки баланса, например) даст бесконечные монеты.
