# AQ Graph Engine — Документация

Добро пожаловать в документацию графового движка AQ!

---

## 📚 Быстрый старт

Для начала работы рекомендуем прочитать в следующем порядке:

1. **[OVERVIEW.md](OVERVIEW.md)** — общий обзор системы, философия "Граф как Закон"
2. **[CLIENT_USAGE.md](CLIENT_USAGE.md)** — руководство по использованию GraphEngineClient
3. **[Краткое резюме по типам графов](general/Краткое%20резюме%20по%20типам%20графов.md)** — когда какой тип графа использовать

---

## 📖 Техническая документация

### Архитектура

- **[CLIENT_SERVER_ARCHITECTURE.md](CLIENT_SERVER_ARCHITECTURE.md)** — принцип "Тонкого клиента", трёхслойная архитектура
- **[API_KEYS.md](API_KEYS.md)** — двойная авторизация (JWT + API keys)

### Типы графов

- **[WORKFLOW_GRAPH.md](WORKFLOW_GRAPH.md)** — WorkflowGraph: узлы, рёбра, параллельное выполнение, suspend/resume
- **[INSTRUCTION_GRAPH.md](INSTRUCTION_GRAPH.md)** — InstructionGraph: контракт, валидация, циклы

### Руководства

- **[GRAPH_ENGINE_GUIDE.md](GRAPH_ENGINE_GUIDE.md)** — полиморфная архитектура узлов, использование Runners
- **[CLIENT_USAGE.md](CLIENT_USAGE.md)** — API клиента, примеры, error handling, best practices

---

## 🎯 Стратегия и бизнес-логика

Документы в папке **[general/](general/)**:

- **[PACKAGE_STRATEGY.md](general/PACKAGE_STRATEGY.md)** — полная стратегия пакета (философия, архитектура, план развития)
- **[AQ Graph Engine — Обзорный документ](general/AQ%20Graph%20Engine%20—%20Обзорный%20документ:%20бизнес-логика,%20архитектура%20и%20production-готовность.md)** — бизнес-логика и production-готовность
- **[Краткое резюме по типам графов](general/Краткое%20резюме%20по%20типам%20графов.md)** — сравнительная таблица типов графов

---

## 📋 План развития

- **[AQ Graph Engine — План полной production-готовности](AQ%20Graph%20Engine%20—%20План%20полной%20production-готовности.md)** — целевая архитектура, фазированный план (7 недель)

---

## 📦 Архив

Исторические документы (отчёты о прогрессе, выполненные планы) находятся в папке **[archive/](archive/)**.

---

## 🏗️ Структура документации

```
docs/
├── README.md                          ← Вы здесь
│
├── general/                           ← Стратегия и бизнес-логика
│   ├── PACKAGE_STRATEGY.md
│   ├── AQ Graph Engine — Обзорный документ.md
│   └── Краткое резюме по типам графов.md
│
├── archive/                           ← Исторические отчёты
│   ├── IMPLEMENTATION_PLAN.md
│   ├── CODE_AUDIT_REPORT.md
│   ├── COMPLETION_REPORT.md
│   └── ...
│
└── [Техническая документация]         ← Актуальные технические документы
    ├── OVERVIEW.md
    ├── WORKFLOW_GRAPH.md
    ├── INSTRUCTION_GRAPH.md
    ├── GRAPH_ENGINE_GUIDE.md
    ├── CLIENT_USAGE.md
    ├── CLIENT_SERVER_ARCHITECTURE.md
    └── API_KEYS.md
```

---

## 🔍 Поиск информации

**Хотите узнать:**

- Как работает система? → [OVERVIEW.md](OVERVIEW.md)
- Как использовать клиент? → [CLIENT_USAGE.md](CLIENT_USAGE.md)
- Какой тип графа выбрать? → [Краткое резюме](general/Краткое%20резюме%20по%20типам%20графов.md)
- Как устроена архитектура? → [CLIENT_SERVER_ARCHITECTURE.md](CLIENT_SERVER_ARCHITECTURE.md)
- Как работает авторизация? → [API_KEYS.md](API_KEYS.md)
- Что такое WorkflowGraph? → [WORKFLOW_GRAPH.md](WORKFLOW_GRAPH.md)
- Что такое InstructionGraph? → [INSTRUCTION_GRAPH.md](INSTRUCTION_GRAPH.md)
- Полная стратегия пакета? → [PACKAGE_STRATEGY.md](general/PACKAGE_STRATEGY.md)

---

## 📝 Обновление документации

При добавлении новых документов:

- **Техническая документация** → корень `docs/`
- **Стратегия/бизнес-логика** → `docs/general/`
- **Отчёты о прогрессе** → `docs/archive/`

---

**Версия документации:** 2026-04-11
**Статус пакета:** Production Ready (100%)
