# Code Labs на iPhone с Windows-ПК

Короткий ответ: **переписывать на Swift не нужно**, а собрать iOS-версию **без Mac можно** — на облачном
macOS-раннере GitHub Actions. Ниже — что именно делать.

---

## 1. Почему Swift не нужен

Я разобрал ваш `CodeLabs-1.6.2.apk` и релизные файлы. Code Labs собран так:

| Платформа | Технология | Подтверждение |
|---|---|---|
| Windows | Electron + electron-builder | `CodeLabs-Setup-1.6.2.exe`, `latest.yml`, `.blockmap` — формат electron-updater |
| Android | **Capacitor** | `assets/capacitor.config.json`, `assets/native-bridge.js`, веб-часть в `assets/public/` |
| Веб-ядро | Vite-сборка (`index-*.js`, чанки `NotesPage`, `TasksPage`, `Calendar`, `NoteEditor`, `SettingsPage`, `TrashPage`, `CommandPalette`) | общее для обеих платформ |

`appId` — `studio.codelabs.mobile`.

**Capacitor — кроссплатформенный, iOS он поддерживает официально.** Android-версия уже работает, значит
iOS — это не переписывание, а добавление третьей цели сборки к тому же `dist/`.

Все четыре используемых плагина имеют официальную iOS-реализацию:

| Плагин из `capacitor.plugins.json` | iOS |
|---|---|
| `@capacitor/app` | да |
| `@capacitor/filesystem` | да |
| `@capacitor/local-notifications` | да |
| `@capacitor/share` | да |

Переписывание всех экранов на SwiftUI — это недели работы и вторая кодовая база, которую придётся
поддерживать параллельно. И оно **всё равно не снимает** ограничение из пункта 2. Смысла нет.

## 2. Что обойти нельзя

Скомпилировать и подписать iOS-приложение можно **только на macOS** — Xcode и цепочка
подписи существуют лишь там. Официального способа сделать это на Windows нет.

Это ограничение на **сборку**, а не на вас: писать код, запускать сборки и устанавливать
приложение на iPhone вы будете с Windows. macOS живёт в облаке и запускается по кнопке.

## 3. Что понадобится

- **Apple Developer Program — 99 $/год.** Это обязательно, если хотите, чтобы приложение
  стояло на iPhone постоянно, а не перестало запускаться через 7 дней. Оформляется на
  [developer.apple.com](https://developer.apple.com/programs/) полностью из браузера.
- **Аккаунт GitHub.** Публичный репозиторий — macOS-минуты бесплатны. Приватный на Free-плане:
  2000 минут/мес, но macOS тарифицируется ×10, то есть ~200 macOS-минут — при сборке
  5–10 мин это 20–40 сборок в месяц. Хватает с запасом.
- **Ваш iPhone.** Регистрировать UDID не нужно: раздача через TestFlight этого не требует.

## 4. Шаг 1 — правки в коде (делаются на Windows)

### 4.1. Секция `ios` в `capacitor.config.json`

Сейчас там есть только `android`. Добавьте рядом:

```json
{
  "appId": "studio.codelabs.mobile",
  "appName": "Code Labs",
  "webDir": "dist",
  "android": {
    "backgroundColor": "#101412"
  },
  "ios": {
    "backgroundColor": "#0D0C0B",
    "contentInset": "never",
    "scrollEnabled": false,
    "limitsNavigationsToAppBoundDomains": true
  },
  "plugins": {
    "LocalNotifications": {
      "smallIcon": "ic_stat_code_labs",
      "iconColor": "#589584"
    }
  }
}
```

`scrollEnabled: false` убирает «резиновое» протягивание всей страницы — на iOS без него
интерфейс визуально отрывается от краёв. `smallIcon` и `iconColor` iOS просто игнорирует,
удалять их не надо.

### 4.2. Безопасные зоны («чёлка» и полоса-домой)

`<meta name="viewport" ... viewport-fit=cover>` в вашем `index.html` **уже стоит** — это половина дела.
Осталось проверить, что верхняя панель и нижняя навигация используют отступы:

```css
padding-top: env(safe-area-inset-top);
padding-bottom: env(safe-area-inset-bottom);
```

Без этого на iPhone контент уедет под вырез камеры.

### 4.3. Отключить самообновление на iOS — это обязательно

Сейчас Android-версия предлагает скачать `CodeLabs-1.6.x.apk`, а Windows-версия обновляется
через electron-updater. **На iOS такое запрещено** — правило App Store 2.5.2 не разрешает
приложению скачивать и запускать исполняемый код. Обновления на iOS приходят только через
TestFlight/App Store сами.

Заглушите весь блок обновлений на iOS:

```ts
import { Capacitor } from '@capacitor/core';

const isIOS = Capacitor.getPlatform() === 'ios';
// весь UI проверки/скачивания обновлений скрывать при isIOS
```

### 4.4. Проверить пути файловой системы

Найдите в исходниках обращения к Android-only директориям — на iOS они упадут:

```
findstr /S /I /N "Directory.External Directory.ExternalStorage Directory.ExternalCache" src\*
```

Если такие есть, замените на `Directory.Data` (внутреннее хранилище) или `Directory.Documents`
(видно в приложении «Файлы»; для этого workflow уже прописывает `UIFileSharingEnabled`).

### 4.5. Разрешение на уведомления

На iOS локальные уведомления не работают, пока пользователь не дал разрешение явно. Убедитесь,
что перед первым `schedule()` вызывается:

```ts
import { LocalNotifications } from '@capacitor/local-notifications';
const { display } = await LocalNotifications.requestPermissions();
```

### 4.6. Иконки и splash

```
npx @capacitor/assets generate --ios
```

Берёт `assets/icon.png` (1024×1024) и `assets/splash.png` и раскладывает по iOS-ресурсам.
Работает на Windows.

## 5. Шаг 2 — настройка на стороне Apple (всё в браузере)

1. **Team ID** — [developer.apple.com](https://developer.apple.com) → Membership details.
   10 символов, вида `A1B2C3D4E5`.
2. **Ключ App Store Connect API** — [App Store Connect](https://appstoreconnect.apple.com) →
   Users and Access → Integrations → App Store Connect API → «+».
   Роль: **App Manager** (или Admin). Скачайте файл `AuthKey_XXXXXXXXXX.p8` —
   **он даётся один раз, второй раз скачать нельзя.** Запишите **Key ID** и **Issuer ID**.
3. **Запись приложения** — App Store Connect → Apps → «+» → New App.
   Платформа iOS, Bundle ID `studio.codelabs.mobile`, SKU любой.
   Если Bundle ID в списке нет — сначала Identifiers → «+» на developer.apple.com.

Сертификат подписи и provisioning profile **вручную делать не надо**: в workflow стоит
`-allowProvisioningUpdates`, Xcode на раннере выпустит их сам по API-ключу.

## 6. Шаг 3 — секреты в GitHub

Репозиторий исходников → Settings → Secrets and variables → Actions → New repository secret:

| Имя секрета | Значение |
|---|---|
| `APPLE_TEAM_ID` | Team ID, 10 символов |
| `ASC_KEY_ID` | Key ID ключа API |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | **всё** содержимое `.p8`-файла, включая строки `-----BEGIN PRIVATE KEY-----` и `-----END PRIVATE KEY-----` |

## 7. Шаг 4 — разовый bootstrap

Скопируйте [`workflows/ios-bootstrap.yml`](workflows/ios-bootstrap.yml) в репозиторий исходников
как `.github/workflows/ios-bootstrap.yml`, закоммитьте и запустите:
Actions → «iOS bootstrap (создать папку ios/)» → Run workflow.

Он на macOS-раннере поставит `@capacitor/ios` нужной версии, выполнит `npx cap add ios`,
допишет ключи в `Info.plist` и **закоммитит папку `ios/` обратно в репозиторий**.

Именно поэтому шаг делается в CI: `cap add ios` тянет CocoaPods, которого на Windows нет.
Нужен один раз.

## 8. Шаг 5 — сборка и отправка в TestFlight

Скопируйте [`workflows/ios-testflight.yml`](workflows/ios-testflight.yml) как
`.github/workflows/ios-testflight.yml`. Запуск: Actions → «iOS -> TestFlight» → Run workflow
(поле версии можно оставить пустым — возьмёт из `package.json`).

Что делает: `npm ci` → `npm run build` → `npx cap sync ios` → `xcodebuild archive` →
`-exportArchive` в `.ipa` → `altool --upload-app` в TestFlight. Готовый `.ipa` дополнительно
кладётся в артефакты сборки, чтобы его можно было скачать.

Номер сборки берётся из `github.run_number` — он растёт сам, а TestFlight требует уникальный
номер для каждой загрузки.

## 9. Шаг 6 — установка на iPhone

1. Дождитесь письма «App Store Connect: сборка обработана» (5–30 минут после загрузки).
2. App Store Connect → ваше приложение → TestFlight → **Internal Testing** → создайте группу
   и добавьте себя (свой Apple ID) как тестировщика.
3. На iPhone установите из App Store приложение **TestFlight**, войдите тем же Apple ID.
4. Code Labs появится в TestFlight → **Install**.

Ключевой момент: **internal-тестирование не проходит проверку Apple**. Это не публикация в
App Store — ревью нет, модерации нет, ждать никого не нужно. До 100 внутренних тестировщиков.
Сборка живёт 90 дней, новая загрузка продлевает. Обновления прилетают на iPhone сами.

Провода и Mac для установки не нужны вообще.

## 10. Альтернативы, если 99 $/год платить не хотите

| Вариант | Цена | Насколько годится |
|---|---|---|
| **TestFlight (пункты выше)** | 99 $/год | **Рекомендую.** Windows-only, приложение стоит постоянно, обновления автоматом |
| Бесплатный Apple ID + Xcode | 0 ₽ | Подпись живёт **7 дней**, потом приложение не запускается. И всё равно нужен Mac для пересборки каждую неделю |
| Аренда облачного Mac (MacinCloud, Scaleway Mac mini) | ~20–30 $/мес или почасово | Работает, но дороже TestFlight и вы сидите в Xcode по RDP. Разумно для отладки на реальном устройстве |
| Sideloadly / AltStore на Windows | 0 ₽ | Устанавливает готовый `.ipa`, но **сам `.ipa` всё равно надо где-то собрать на macOS**. Плюс те же 7 дней на бесплатном Apple ID |
| Hackintosh / macOS в VMware | 0 ₽ | Нарушает лицензию Apple, ломается на обновлениях, подпись часто отваливается. Не советую |

Без Apple Developer Program любой путь сводится к перепривязке раз в 7 дней. Для приложения,
которым вы пользуетесь каждый день, это мучение — 99 $/год решают вопрос целиком.

## 11. Если всё-таки нужен именно нативный Swift

Тогда это полноценная переработка: SwiftUI-экраны вместо `NotesPage`, `TasksPage`, `Calendar`,
`NoteEditor`, `SettingsPage`, `TrashPage`, `CommandPalette`, своя модель данных и своя
синхронизация — и вторая кодовая база навсегда. Ограничение «собирать только на macOS»
при этом никуда не девается, то есть пункты 5–9 всё равно нужны.

Разумный компромисс, если упирается в производительность отдельного экрана: оставить Capacitor
и вынести узкое место в нативный Swift-плагин Capacitor. Тогда Swift появляется ровно там, где
он что-то даёт.

## 12. Частые грабли

- **`altool` ругается на дубликат номера сборки** — перезапустите workflow, `run_number` увеличится.
- **«No profiles for studio.codelabs.mobile»** — Bundle ID не зарегистрирован в Identifiers
  или у API-ключа роль ниже App Manager.
- **Белый экран на iPhone, на Android всё хорошо** — почти всегда CSP. В вашем `index.html`
  стоит `default-src 'self'`, а Capacitor на iOS отдаёт страницу с `capacitor://localhost`.
  Если экран пустой, смотрите консоль через Safari на Mac либо временно ослабьте CSP для проверки.
- **Уведомления не приходят** — не вызван `requestPermissions()` (пункт 4.5).
