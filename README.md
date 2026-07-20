# GitHub Product System

Универсальный локальный контур для запуска новых продуктов в GitHub: детерминированный bootstrap, безопасные шаблоны, CI, Dependabot, issue/PR-процесс и статический аудит без обязательной сети, Git или GitHub CLI.

## Что уже автоматизировано

- профили `generic`, `node` и `python`;
- private-проект по умолчанию, без выдуманной лицензии;
- pull request template и формы bug/feature;
- минимальные GitHub Actions permissions;
- CI с отменой устаревших запусков и лимитом времени;
- единые версии runner, Node.js и Python из `config/defaults.json`;
- Dependabot для Actions и выбранной экосистемы;
- проверка незаменённых токенов, опасных файлов, крупных файлов и незакреплённых actions;
- отдельный publish-скрипт: сеть и GitHub никогда не вызываются скрытно из bootstrap.

## Быстрый старт

Из папки системы:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 `
  -Name "my-product" `
  -DisplayName "Мой продукт" `
  -Profile node `
  -Destination (Join-Path $env:USERPROFILE 'Documents\GitHub') `
  -Visibility private
```

Проверка созданного продукта:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit.ps1 `
  -Path (Join-Path $env:USERPROFILE 'Documents\GitHub\my-product')
```

Проверка обновлений управляемых GitHub-файлов:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync.ps1 `
  -Path (Join-Path $env:USERPROFILE 'Documents\GitHub\my-product')
```

Команда только показывает drift. Применение выполняется отдельно с `-Apply`; README, AGENTS, SECURITY, CONTRIBUTING и код продукта не перезаписываются.

Проверка самой системы:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

## Настройки по умолчанию

Файл `config/defaults.json` задаёт каталог назначения, видимость, лицензию, владельца GitHub, runner и версии Node.js/Python. Эти значения реально попадают в manifest и CI каждого нового продукта; параметры `bootstrap.ps1` имеют приоритет над defaults.

## Профили

| Профиль | Для чего | Базовая проверка |
|---|---|---|
| `generic` | документы, прототипы, нестандартный стек | структура и целостность репозитория |
| `node` | Node.js-библиотека или сервис | setup заданной версии, `npm ci`, syntax check, `node --test` |
| `python` | Python-библиотека или сервис | setup заданной версии, editable install, syntax check, `unittest` |

## Публичные продукты

Публичный продукт требует явного выбора лицензии:

```powershell
... -Visibility public -License MIT
```

Доступны `MIT` и `Apache-2.0`. Для private-проекта значение по умолчанию — `none`.

## Публикация

Bootstrap создаёт только локальный продукт. После установки Git и `gh`, аутентификации и отдельного подтверждения публикация выполняется скриптом `scripts/publish.ps1`. Порядок первого подключения описан в [docs/FIRST_PUBLISH_RU.md](docs/FIRST_PUBLISH_RU.md).

## Ограничения GitHub Free

Private-репозитории поддерживают CI и Dependabot, но полноценная защита `main`, rulesets и environments требует GitHub Pro. Подробная матрица: [docs/GITHUB_FREE_RU.md](docs/GITHUB_FREE_RU.md).
