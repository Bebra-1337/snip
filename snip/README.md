# Snip

Snipping Tool из Windows 11 для Noctalia + Hyprland.

Бинд замораживает экран и открывает плоскую панель сверху по центру:

```
[Фото|Видео] │ Область  Окно  Экран  Все │ (Звук Микр.) │ Цвет  Текст  QR │ Закрыть
```

- **Фото**: выбор поверх замороженного экрана. Окна подсвечиваются при наведении (`slurp -r`).
  Снимок вырезается из кадра, сделанного в момент нажатия, и открывается во встроенном
  редакторе Noctalia (`noctalia msg annotate`). Курсора на снимке нет.
- **Видео**: область, окно или монитор → отсчёт 3-2-1 → `wf-recorder` (NVENC). Звук системы и микрофон
  включаются тумблерами; если включены оба, микрофон пишется `pw-record` и сводится `ffmpeg`. Мини-панель
  показывает таймер и кнопку «Стоп». Повторное нажатие бинда тоже останавливает запись.
  Путь к файлу копируется в буфер обмена.
- **Цвет** (`hyprpicker`), **Текст** (OCR, `tesseract`), **QR** (`zbarimg`): результат
  копируется в буфер обмена.

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

Зависимости: grim, slurp, wayfreeze, imagemagick, jq, hyprpicker, tesseract, zbar,
wf-recorder, pipewire, ffmpeg, wl-clipboard, libnotify.
