# AQ Graph Engine — Документация

**Статус:** В активной разработке  
**Последнее обновление:** 2026-05-02

---

## Читать в таком порядке

1. [OVERVIEW.md](OVERVIEW.md) — что это, три типа графов, что работает сейчас
2. [ARCHITECTURE.md](ARCHITECTURE.md) — внутреннее устройство, структура файлов, поток выполнения
3. [CLIENT_SERVER_ARCHITECTURE.md](CLIENT_SERVER_ARCHITECTURE.md) — принцип тонкого клиента, режимы работы
4. [CLIENT_USAGE.md](CLIENT_USAGE.md) — API GraphEngineClient, примеры
5. [API_KEYS.md](API_KEYS.md) — авторизация

---

## Текущее состояние

| Компонент | Статус |
|-----------|--------|
| TypedWorkflowGraph + WorkflowRunner | ✅ Работает |
| InstructionRunner | ✅ Работает (через deprecated InstructionGraph) |
| PromptRunner | ✅ Работает (через deprecated PromptGraph) |
| LocalEngineTransport | ✅ Работает |
| HttpEngineTransport | ✅ Работает |
| GraphEngineClient | ✅ Работает |
| TypedInstructionGraph | 🔄 Создан, миграция runner — следующая сессия |
| TypedPromptGraph | 🔄 Создан, миграция runner — следующая сессия |
| Distributed lock | ❌ Заглушка (single-worker only) |

---

## Аудит и tech debt

- [audit_2026_05_02/AUDIT_REPORT.md](audit_2026_05_02/AUDIT_REPORT.md) — найденные проблемы
- [audit_2026_05_02/STATUS.md](audit_2026_05_02/STATUS.md) — что решено, что осталось

---

## Архив

Исторические документы — в [archive/](archive/).
Там же: старые описания `WorkflowGraph`, `InstructionGraph`, `PromptGraph` (deprecated типы).
