# SSH-клиент (iOS + Android)

Простой SSH-клиент в духе Termius. Один код на Flutter для обеих платформ.

## Стек

| Задача | Библиотека |
|---|---|
| UI, iOS + Android | Flutter 3.47 (Dart) |
| SSH-протокол | [dartssh2](https://pub.dev/packages/dartssh2) — чистый Dart, без нативного кода |
| Эмулятор терминала | [xterm](https://pub.dev/packages/xterm) (xterm-256color) |
| Пароли и ключи | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) — Keychain / Android Keystore |
| Список хостов | shared_preferences (без секретов) |

## Что уже есть (MVP)

- Список хостов: добавить, изменить, удалить.
- Вход по паролю или по приватному ключу (OpenSSH/PEM, с passphrase).
- Секреты хранятся только в Keychain/Keystore, отдельно от списка хостов.
- Проверка ключа сервера (TOFU): при первом подключении показывается отпечаток `SHA256:…`, при смене ключа предупреждение.
- Терминал с PTY, ресайзом и цветами.
- Панель доп. клавиш: Esc, Tab, залипающий Ctrl, стрелки, `| - / ~ : * &`, Home/End, PgUp/PgDn.
- Переподключение одной кнопкой.

## Структура

```
lib/
  main.dart                    точка входа
  models/host.dart             модель хоста и секретов
  data/host_repository.dart    список хостов
  data/secret_store.dart       Keychain / Keystore
  ssh/ssh_session.dart         SSH-сессия ↔ терминал
  screens/hosts_screen.dart    список хостов
  screens/host_edit_screen.dart  форма хоста
  screens/terminal_screen.dart терминал
  widgets/extra_keys_bar.dart  доп. клавиши
```

## Запуск

```bash
flutter pub get
flutter run            # на подключённом телефоне или эмуляторе
flutter test
```

Для iOS нужен Mac с Xcode (подпись: откройте `ios/Runner.xcworkspace`, выберите свою Team).
Для Android — Android Studio / SDK. Сборка релиза: `flutter build apk` и `flutter build ipa`.

## Дальше (идеи)

1. Генерация ключей ed25519 в приложении и копирование публичного ключа.
2. Несколько сессий вкладками, работа в фоне.
3. Сниппеты (сохранённые команды).
4. Вход в приложение по Face ID / отпечатку.
5. SFTP-браузер файлов (dartssh2 его поддерживает).
6. Проброс портов (local forward).
7. Синхронизация хостов между устройствами (зашифрованный экспорт / iCloud).
8. Темы и размер шрифта, жесты (щипок для масштаба).
