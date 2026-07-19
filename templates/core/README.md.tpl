# {{DISPLAY_NAME}}

`{{PRODUCT_NAME}}` создан профилем `{{PROFILE}}` системы GitHub Product System `{{SYSTEM_VERSION}}`.

## Локальная проверка

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

## Рабочий процесс

1. Создайте issue с ожидаемым результатом.
2. Работайте в отдельной ветке.
3. Запустите локальную проверку.
4. Откройте pull request и дождитесь зелёного CI.
5. Объединяйте через squash merge.

## Статус публикации

Видимость репозитория: `{{VISIBILITY}}`. Лицензия: `{{LICENSE}}`.
