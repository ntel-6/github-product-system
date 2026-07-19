# Возможности личного GitHub Free

Проверено 19 июля 2026 года.

| Возможность | Public | Private на Free | Решение системы |
|---|---:|---:|---|
| Template repository | Да | Да | Поддерживается после первой публикации |
| GitHub Actions | Бесплатные стандартные runners | 2 000 минут/месяц | Короткий CI на `ubuntu-latest` |
| Dependabot | Да | Да | Включён в каждом профиле |
| Rulesets | Да | Нет | Для private — предупреждение, нужен Pro |
| Protected branches | Да | Нет | Для private — PR-дисциплина без ложного обещания enforcement |
| Environments | Да | Нет | Не создаются базовым шаблоном |
| CodeQL | Да | Нет | Для public включается штатным Default Setup после публикации |
| GitHub Pages | Да | Нет | Не включается без отдельного решения о документации |

Официальные источники:

- [GitHub plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)
- [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Dependabot version updates](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-version-updates)
- [CodeQL code scanning](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-code-scanning)
- [Actions billing and usage](https://docs.github.com/en/actions/concepts/billing-and-usage)

Для максимальной защиты private-продуктов минимальное разумное обновление — GitHub Pro. Система остаётся работоспособной на Free и не подменяет недоступные гарантии локальными галочками.
