# Code Labs в вебе на Vercel

Главное: **переносить нечего и синхронизацию писать не надо — она уже есть.**

---

## 1. Что я нашёл в бандле

Синхронизация у Code Labs уже работает, и работает через **Neon** (Postgres).
В сборку вшиты три адреса:

```
VITE_NEON_AUTH_URL      .../neondb/auth          — Neon Auth
VITE_NEON_DATA_API_URL  .../neondb/rest/v1       — Data API (PostgREST)
VITE_NEON_FILES_URL     https://br-…-files…/     — функция выдачи ссылок на вложения
```

Работа с данными идёт через таблицы: `payments`, `attachments`, `members`, `favorites`,
`categories`, `subscriptions`, `recents`, `workspace`, `record_versions`, `activity`.
Маршруты приложения: `/notes`, `/tasks`, `/prompts`, `/messages`, `/clients`,
`/payments`, `/trash`, `/settings`.

В `SettingsPage` есть форма, где эти три адреса можно переопределить руками
(«Адрес Neon Auth», «Адрес Data API», «Адрес функции files»).

**Вывод:** десктоп, Android и веб — это один и тот же Vite-бандл, который ходит в один и
тот же Neon. Веб-версия не «портируется» — она уже существует, её надо просто собрать и
выложить. Данные синхронизируются автоматически, потому что источник у всех один.

`indexedDB` и `localStorage` в коде тоже есть, но это локальный кэш поверх Neon, а не
основное хранилище.

## 2. Что нужно сделать

Ровно три вещи. Никакого кода.

### 2.1. Поправить `base` в конфиге Vite

Сейчас в сборке `BASE_URL: "./"` — относительные пути. Это правильно для Electron
(`file://`) и Capacitor (`capacitor://localhost`), но для веба с клиентским роутингом
лучше абсолютный путь, иначе вложенные маршруты могут не найти ассеты.

В `vite.config.ts` сделайте `base` зависимым от цели сборки:

```ts
export default defineConfig(({ mode }) => ({
  base: mode === 'web' ? '/' : './',
  // ...
}));
```

и для Vercel собирайте командой `vite build --mode web`.

Если все маршруты плоские (`/notes`, `/tasks`, без вложенности), то `./` тоже заработает —
но лучше не закладываться.

### 2.2. Переменные окружения в Vercel

Project → Settings → Environment Variables, для Production и Preview:

| Переменная | Значение |
|---|---|
| `VITE_NEON_AUTH_URL` | `https://ep-lively-breeze-b2xwl4nu.neonauth.c-6.eu-central-1.aws.neon.tech/neondb/auth` |
| `VITE_NEON_DATA_API_URL` | `https://ep-lively-breeze-b2xwl4nu.apirest.c-6.eu-central-1.aws.neon.tech/neondb/rest/v1` |
| `VITE_NEON_FILES_URL` | `https://br-winter-salad-b2yom94t-files.compute.c-6.eu-central-1.aws.neon.tech/` |

Это те же адреса, что уже вшиты в текущую сборку — я их взял из бандла.

Важно: префикс `VITE_` означает, что значения попадают **в публичный JS**. Для адресов это
нормально (они и так видны в APK). Но никаких секретов и паролей БД в `VITE_*` класть нельзя.

### 2.3. `vercel.json`

Готовый лежит рядом: [`vercel.json`](vercel.json) → положить в корень репозитория исходников.

Он делает SPA-роутинг (любой путь отдаёт `index.html`, иначе `/notes` при перезагрузке
страницы даст 404), вечный кэш для хешированных ассетов и базовые security-заголовки.

## 3. Обязательно проверить: CORS в Neon

Это единственное, что реально может сломать синхронизацию в вебе.

Сейчас в Neon ходят Android (`capacitor://localhost`) и Electron. Браузер с домена
`*.vercel.app` — **новый origin**, и если он не разрешён, все запросы к Data API упадут
с ошибкой CORS. Приложение откроется, но останется пустым.

В настройках Neon (Data API / Auth) нужно добавить в разрешённые origins:

```
https://<имя-проекта>.vercel.app
https://<ваш-домен>            — если подключите свой
```

Превью-деплои Vercel получают **каждый раз новый** поддомен вида
`code-labs-abc123-barbariki.vercel.app`. Если хотите, чтобы превью тоже работали,
разрешайте по шаблону либо тестируйте только на Production-домене.

Проверить отсюда я не смог — сетевая политика контейнера не пускает к `neon.tech`.
Проще всего проверить так: откройте задеплоенный сайт, F12 → Console. Если увидите
`blocked by CORS policy` — дело в этом.

## 4. Как деплоить

Лучший способ — **Git-интеграция Vercel**, не workflow:

1. [vercel.com/new](https://vercel.com/new) → Import Git Repository → репозиторий исходников
   Code Labs.
2. Framework Preset: **Vite**. Build Command и Output Directory возьмутся из `vercel.json`.
3. Добавить переменные из 2.2.
4. Deploy.

Дальше каждый push в `main` автоматически пересобирает Production, а любая ветка
получает превью-ссылку. Ничего настраивать не надо.

## 5. Приватность — включите защиту деплоя

`package.json` описывает Code Labs как «приватное рабочее пространство для двоих».
По умолчанию деплой Vercel доступен **всем, у кого есть ссылка**.

Данные защищены логином Neon Auth, так что без учётки их не увидят. Но саму страницу
лучше закрыть: Project → Settings → **Deployment Protection** → включить
**Vercel Authentication**. Тогда открыть сайт смогут только члены команды `barbariki`.

Если нужен доступ с чужих устройств без аккаунта Vercel — используйте
Protection Bypass или оставьте открытым, полагаясь на Neon Auth.

## 6. Чего это не даёт

- **PWA/офлайн** — в бандле нет service worker. В браузере офлайн-режима не будет,
  в отличие от десктопа и Android.
- **Печать в PDF** — на вебе используется запасной путь через скрытый `iframe`
  (нативный `printHtml` только на мобильных, `invoicePdf` только на десктопе).
  Работает, но диалог печати будет браузерный.
- **Автообновление** — в вебе не нужно: пользователь всегда получает свежую версию.
  Блок обновлений и так гейтится через `isNativePlatform()`, на вебе он выключен.
