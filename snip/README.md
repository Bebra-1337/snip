# Snip

Snipping Tool из Windows 11 для Noctalia + Hyprland.

Бинд открывает плоскую панель сверху по центру. Снимки делает сама Noctalia
(`noctalia msg screenshot-*`), поэтому курсор в них не попадает:

```
[Фото|Видео] │ Область  Окно  Экран  Все │ (Звук Микр.) │ Цвет  Текст  QR │ Закрыть
```

- **Фото**: выбор режима и сразу снимок + встроенный редактор Noctalia.
  - **Область** — селектор Noctalia (`noctalia msg screenshot-region`).
  - **Окно** — селектор окон (`slurp -r`): выбранное окно фокусируется и снимается через
    `noctalia msg screenshot-window`. Window-capture курсор не содержит никогда.
  - **Экран / Все** — `noctalia msg screenshot-fullscreen <монитор>` / `all`.
  - Для `region`/`fullscreen` без курсора нужен hardware-курсор: при software-курсоре
    Hyprland запекает указатель в кадр. В конфиге Hyprland:
    ```lua
    hl.config({ cursor = { no_hardware_cursors = false } })
    ```
  - В редакторе `show_cursor`/кнопка указателя выключены по умолчанию (`--no-show-cursor`).
- **Видео**: область, окно или монитор → отсчёт 3-2-1 → `gpu-screen-recorder`. Звук системы и микрофон включаются
  тумблерами и сводятся в одну дорожку. На NixOS нужен `programs.gpu-screen-recorder.enable = true`
  (setcap для `gsr-kms-server`), иначе каждый старт спрашивает пароль. Мини-панель
  показывает таймер и кнопку «Стоп». Повторное нажатие бинда тоже останавливает запись.
  Курсор в видео остаётся (`-cursor yes`). Путь к файлу копируется в буфер обмена.
- **Цвет** (`hyprpicker`), **Текст** (OCR, `tesseract`), **QR** (`zbarimg`): результат
  копируется в буфер обмена. Область для OCR/QR выбирается через `slurp` и снимается
  `grim`; при hardware-курсоре указатель в кадр не попадает.

Клавиши в панели: `1–4` режимы, `5–7` утилиты, `Tab` переключает Фото/Видео, `Enter`
повторяет последний режим, `Esc` отменяет.

## Подключение

```sh
noctalia msg plugins source add snip path ~/noctalia-snip
noctalia msg plugins enable bebra/snip
```

Hyprland (Lua):

```lua
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("noctalia msg plugin bebra/snip:service all open"))
```

Зависимости: grim, slurp, imagemagick, jq, hyprpicker, tesseract, zbar,
gpu-screen-recorder, wl-clipboard. Нужна Noctalia 5.5+ (команды `screenshot-*`).
