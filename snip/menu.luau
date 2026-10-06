--!nonstrict
-- Snip — the flat top-center action bar (Windows 11 Snipping Tool style).
--
-- [Фото|Видео] │ Область Окно Экран Все │ Звук Микр. │ Цвет Текст QR │ Закрыть
--
-- Clicking a mode runs it immediately; the last mode is highlighted and Enter repeats it.
-- Keys: 1–4 modes, 5–7 tools, Tab switches Фото/Видео, Esc closes (and unfreezes).
-- Choices persist in the plugin data dir.

local STATE_FILE = `{noctalia.pluginDataDir()}/menu.json`

local MODES = {
  { id = "region", glyph = "marquee-2", label = "Область", key = "1" },
  { id = "window", glyph = "app-window", label = "Окно", key = "2" },
  { id = "screen", glyph = "device-desktop", label = "Экран", key = "3" },
  { id = "all", glyph = "devices", label = "Все", key = "4", photoOnly = true },
}

local TOOLS = {
  { id = "color", glyph = "color-picker", label = "Цвет", key = "5" },
  { id = "ocr", glyph = "text-recognition", label = "Текст", key = "6" },
  { id = "qr", glyph = "qrcode", label = "QR", key = "7" },
}

local prefs = { kind = "photo", mode = "region", audioOut = true, audioIn = false }
local hovered = nil
local acted = false
local seq = 0
local render

-- ── Persistence ────────────────────────────────────────────────────────────

local function load()
  local raw = noctalia.readFile(STATE_FILE)
  if not raw then return end
  local data = noctalia.json.decode(raw)
  if type(data) ~= "table" then return end
  for k, v in data do
    if prefs[k] ~= nil and type(v) == type(prefs[k]) then prefs[k] = v end
  end
end

local function save()
  noctalia.writeFile(STATE_FILE, noctalia.json.encode(prefs))
end

-- ── Commands ───────────────────────────────────────────────────────────────

local function send(action, payload)
  seq += 1
  noctalia.state.set("command", { action = action, payload = payload, seq = seq })
end

local function modeEnabled(m)
  return not (m.photoOnly and prefs.kind == "video")
end

local function run(id, isMode)
  if isMode then
    prefs.mode = id
    save()
  end
  acted = true
  send("action", { kind = prefs.kind, mode = id, audioOut = prefs.audioOut, audioIn = prefs.audioIn })
  panel.close()
end

local function setKind(kind)
  prefs.kind = kind
  if kind == "video" and prefs.mode == "all" then prefs.mode = "region" end
  save()
  render()
end

-- ── UI ─────────────────────────────────────────────────────────────────────

local function hover(id)
  return function(state)
    if state == "true" then
      hovered = id
    elseif hovered == id then
      hovered = nil
    end
    render()
  end
end

-- Icon above a small caption, like the Win11 toolbar buttons.
local function tile(id, glyph, label, opts)
  local selected = opts.selected
  local enabled = opts.enabled ~= false
  local fg = if selected then "primary" else "on_surface"
  local fill = if selected then "primary/0.16"
    elseif enabled and hovered == id then "on_surface/0.08"
    else "#00000000"
  return ui.column({
    key = id,
    width = opts.width or 70,
    height = 52,
    radius = 10,
    gap = 3,
    align = "center",
    justify = "center",
    fill = fill,
    opacity = if enabled then 1 else 0.35,
    tooltip = opts.tooltip,
    onClick = if enabled then opts.onClick else nil,
    onHover = if enabled then hover(id) else nil,
  }, {
    ui.glyph({ name = glyph, size = 20, color = fg }),
    ui.label({ text = label, fontSize = 11, color = fg }),
  })
end

local function sep()
  return ui.row({ paddingH = 4, align = "center" }, {
    ui.box({ width = 1, height = 34, fill = "outline/0.6" }),
  })
end

function render()
  local children = {}
  local function add(node) table.insert(children, node) end

  -- Фото | Видео segmented switch
  add(ui.row({ gap = 2, padding = 2, radius = 12, fill = "on_surface/0.07", align = "center" }, {
    tile("kind-photo", "camera", "Фото", {
      width = 60, selected = prefs.kind == "photo", tooltip = "Снимок (Tab)",
      onClick = function() setKind("photo") end,
    }),
    tile("kind-video", "video", "Видео", {
      width = 60, selected = prefs.kind == "video", tooltip = "Запись (Tab)",
      onClick = function() setKind("video") end,
    }),
  }))
  add(sep())

  for _, m in MODES do
    add(tile(m.id, m.glyph, m.label, {
      selected = prefs.mode == m.id,
      enabled = modeEnabled(m),
      tooltip = `{m.label} ({m.key})`,
      onClick = function() run(m.id, true) end,
    }))
  end

  -- Always present so the bar keeps its shape; only active for video.
  local video = prefs.kind == "video"
  add(sep())
  add(tile("audio-out", if prefs.audioOut then "volume" else "volume-off", "Звук", {
    width = 56, selected = video and prefs.audioOut, enabled = video, tooltip = "Звук системы",
    onClick = function() prefs.audioOut = not prefs.audioOut; save(); render() end,
  }))
  add(tile("audio-in", if prefs.audioIn then "microphone" else "microphone-off", "Микр.", {
    width = 56, selected = video and prefs.audioIn, enabled = video, tooltip = "Микрофон",
    onClick = function() prefs.audioIn = not prefs.audioIn; save(); render() end,
  }))

  add(sep())
  for _, t in TOOLS do
    add(tile(t.id, t.glyph, t.label, {
      tooltip = `{t.label} ({t.key})`,
      onClick = function() run(t.id, false) end,
    }))
  end

  add(sep())
  add(tile("close", "x", "Закрыть", {
    width = 64, tooltip = "Отмена (Esc)",
    onClick = function() panel.close() end,
  }))

  -- The host already pads the panel surface; no extra padding here.
  panel.render(ui.row({ gap = 4, align = "center", justify = "center" }, children))
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "Tab" then
    setKind(if prefs.kind == "photo" then "video" else "photo")
  elseif chord == "Return" or chord == "KP_Enter" then
    run(prefs.mode, true)
  else
    for _, m in MODES do
      if chord == m.key and modeEnabled(m) then return run(m.id, true) end
    end
    for _, t in TOOLS do
      if chord == t.key then return run(t.id, false) end
    end
  end
end

function onOpen(_context)
  acted, hovered = false, nil
  load()
  noctalia.state.set("menuOpen", true)
  render()
end

function onClose()
  noctalia.state.set("menuOpen", false)
  if not acted then send("cancel") end
end
