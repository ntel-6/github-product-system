# Первая публикация

## 1. Установить Git и GitHub CLI

Скрипт `scripts/install-tooling.ps1` загружает только официальные portable-релизы, проверяет SHA-256 и размещает версии в `%USERPROFILE%\AI_Library\tools`.

## 2. Подключить GitHub CLI

После установки:

```powershell
gh auth login --web --git-protocol https
gh auth setup-git
gh auth status --active --hostname github.com
```

На Windows можно вместо этого запустить `scripts\connect-github.cmd`: он показывает одноразовый код в отдельном окне и выполняет ту же официальную OAuth-процедуру.

Подтверждение браузера выполняет пользователь. Не передавайте Codex пароль, одноразовый код или токен.

## 3. Настроить Git identity

Выберите реальное либо GitHub noreply-значение и задайте его самостоятельно:

```powershell
git config --global user.name "ntel-6"
git config --global user.email "ВАШ_ПОДТВЕРЖДЕННЫЙ_EMAIL_ИЛИ_NOREPLY"
```

## 4. Публиковать отдельно от bootstrap

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish.ps1 `
  -Path (Join-Path $env:USERPROFILE 'Documents\GitHub\my-product') `
  -Owner ntel-6 `
  -Visibility private
```

Скрипт сначала проверяет продукт, `gh auth` и точный target. Публикация никогда не является скрытым побочным эффектом генерации.
