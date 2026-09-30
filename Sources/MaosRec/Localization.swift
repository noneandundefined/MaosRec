import Foundation

extension Notification.Name {
    static let languageDidChange = Notification.Name("MaosRec.languageDidChange")
}

final class L10n {
    static let shared = L10n()

    private let strings: [String: [String: String]] = [
        "en": [
            "app.subtitle": "Lightweight screen recorder",
            "source.screen": "SCREEN",
            "source.camera": "CAMERA OVERLAY",
            "source.audio": "AUDIO",
            "source.display": "Display",
            "source.device": "Device",
            "source.off": "Off",
            "preview.title": "Recording preview",
            "preview.hint": "The live screen preview is disabled to save memory.",
            "preview.camera": "CAMERA",
            "record.start": "Start recording",
            "record.stop": "Stop recording",
            "record.preparing": "Preparing…",
            "record.saving": "Saving…",
            "record.ready": "Ready",
            "record.elapsed": "Recording  %@",
            "record.saved": "Recording saved",
            "record.error": "Could not record",
            "record.permission": "Allow Screen Recording in System Preferences → Security & Privacy, then restart MaosRec.",
            "record.devicePermission": "Camera or microphone access was denied. Allow access in System Preferences → Security & Privacy.",
            "error.display": "The selected display is no longer available.",
            "error.screenInput": "The screen capture input could not be created.",
            "error.output": "The capture output could not be created.",
            "error.camera": "The selected camera is unavailable.",
            "error.microphone": "The selected microphone is unavailable.",
            "settings.title": "Settings",
            "settings.general": "General",
            "settings.language": "Language",
            "settings.language.auto": "System language",
            "settings.language.en": "English",
            "settings.language.ru": "Russian",
            "settings.output": "Save recordings to",
            "settings.choose": "Choose…",
            "settings.theme": "Theme",
            "settings.theme.system": "System (light or dark automatically)",
            "settings.quality": "Recording quality",
            "settings.quality.economy": "Economy — 540p, 12 fps",
            "settings.quality.balanced": "Balanced — 720p, 15 fps",
            "settings.quality.smooth": "Smooth — 720p, 30 fps",
            "settings.minimize": "Minimize the window when recording starts",
            "settings.updates": "Updates",
            "settings.autoUpdates": "Automatically check for and install updates",
            "settings.check": "Check now",
            "camera.position": "Position",
            "camera.size": "Size",
            "camera.topLeft": "Top left",
            "camera.topRight": "Top right",
            "camera.bottomLeft": "Bottom left",
            "camera.bottomRight": "Bottom right",
            "menu.file": "File",
            "menu.settings": "Settings…",
            "menu.updates": "Check for Updates…",
            "menu.quit": "Quit MaosRec",
            "menu.showFile": "Show in Finder",
            "alert.ok": "OK"
        ],
        "ru": [
            "app.subtitle": "Лёгкая запись экрана",
            "source.screen": "ЭКРАН",
            "source.camera": "КАМЕРА ПОВЕРХ",
            "source.audio": "ЗВУК",
            "source.display": "Монитор",
            "source.device": "Устройство",
            "source.off": "Выкл.",
            "preview.title": "Предпросмотр записи",
            "preview.hint": "Живой предпросмотр экрана отключён для экономии памяти.",
            "preview.camera": "КАМЕРА",
            "record.start": "Начать запись",
            "record.stop": "Остановить запись",
            "record.preparing": "Подготовка…",
            "record.saving": "Сохранение…",
            "record.ready": "Готово",
            "record.elapsed": "Идёт запись  %@",
            "record.saved": "Запись сохранена",
            "record.error": "Не удалось записать",
            "record.permission": "Разрешите «Запись экрана» в Системных настройках → Защита и безопасность, затем перезапустите MaosRec.",
            "record.devicePermission": "Нет доступа к камере или микрофону. Разрешите доступ в Системных настройках → Защита и безопасность.",
            "error.display": "Выбранный монитор больше недоступен.",
            "error.screenInput": "Не удалось создать источник записи экрана.",
            "error.output": "Не удалось создать выход записи.",
            "error.camera": "Выбранная камера недоступна.",
            "error.microphone": "Выбранный микрофон недоступен.",
            "settings.title": "Настройки",
            "settings.general": "Основные",
            "settings.language": "Язык",
            "settings.language.auto": "Язык системы",
            "settings.language.en": "English",
            "settings.language.ru": "Русский",
            "settings.output": "Сохранять записи в",
            "settings.choose": "Выбрать…",
            "settings.theme": "Тема",
            "settings.theme.system": "Системная (светлая или тёмная автоматически)",
            "settings.quality": "Качество записи",
            "settings.quality.economy": "Экономное — 540p, 12 кадр/с",
            "settings.quality.balanced": "Баланс — 720p, 15 кадр/с",
            "settings.quality.smooth": "Плавное — 720p, 30 кадр/с",
            "settings.minimize": "Сворачивать окно после начала записи",
            "settings.updates": "Обновления",
            "settings.autoUpdates": "Автоматически проверять и устанавливать обновления",
            "settings.check": "Проверить сейчас",
            "camera.position": "Положение",
            "camera.size": "Размер",
            "camera.topLeft": "Слева сверху",
            "camera.topRight": "Справа сверху",
            "camera.bottomLeft": "Слева снизу",
            "camera.bottomRight": "Справа снизу",
            "menu.file": "Файл",
            "menu.settings": "Настройки…",
            "menu.updates": "Проверить обновления…",
            "menu.quit": "Завершить MaosRec",
            "menu.showFile": "Показать в Finder",
            "alert.ok": "ОК"
        ]
    ]

    var languageCode: String {
        switch Preferences.language {
        case .english: return "en"
        case .russian: return "ru"
        case .automatic:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? "ru" : "en"
        }
    }

    func string(_ key: String) -> String {
        strings[languageCode]?[key] ?? strings["en"]?[key] ?? key
    }

    func setLanguage(_ language: AppLanguage) {
        Preferences.language = language
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}

func tr(_ key: String) -> String { L10n.shared.string(key) }
