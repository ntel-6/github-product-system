# GitHub Product System

## Назначение

Этот репозиторий — генератор и проверяющий контур для новых продуктов. Источник истины: `config/managed-files.json`, `policy/baseline.json`, `templates/`, `profiles/` и `scripts/`.

## Обязательные правила

- Поддерживать Windows PowerShell 5.1 и PowerShell 7.
- Не добавлять обязательные сторонние модули, npm- или pip-зависимости в генератор.
- Bootstrap не обращается к сети и не выполняет commit, push или GitHub API.
- Никогда не перезаписывать существующую папку продукта.
- Любое изменение шаблонов сопровождается запуском `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1`.
- GitHub Actions должны иметь минимальные `permissions`, `timeout-minutes`, `concurrency` и закреплённые полным SHA внешние actions.
- Не включать `pull_request_target`.
- Не создавать облачные репозитории, коммиты, push, rulesets, secrets или environments без отдельного подтверждения пользователя.
- Не обещать branch protection, rulesets, environments или CodeQL для private-репозитория личного GitHub Free.

## Управляемые и пользовательские файлы

- `managed`: инфраструктурный файл может обновляться системой.
- `create`: файл создаётся только при старте продукта и затем принадлежит продукту.
- Не переводить пользовательские README, SECURITY, CONTRIBUTING и AGENTS в `managed` без миграционного плана.
