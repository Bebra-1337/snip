--!nonstrict
-- Snip — recording indicator. Persistent, never takes keyboard focus.
-- Shows the 3-2-1 countdown, then "● 00:12 [■]". Mirrors the service's "rec" state.

local rec = noctalia.state.get("rec") or { phase = "idle" }
local seq = 0

local function send(action)
  seq += 1
  noctalia.state.set("command", { action = action, seq = seq })
end

local function clock(ms)
  local s = math.max(0, math.floor(ms / 1000))
  return string.format("%02d:%02d", s // 60, s % 60)
end

local function render()
  local body
  if rec.phase == "countdown" then
    body = {
      ui.label({ text = "Запись через", fontSize = 13, color = "on_surface_variant" }),
      ui.label({ text = tostring(rec.n or ""), fontSize = 22, fontWeight = "bold", color = "primary" }),
    }
  else
    local elapsed = if rec.startedAt then noctalia.nowMs() - rec.startedAt else 0
    body = {
      ui.glyph({ name = "point-filled", size = 18, color = "error" }),
      ui.label({ text = clock(elapsed), fontSize = 15, fontWeight = "bold" }),
    }
  end
  table.insert(body, ui.spacer({ flexGrow = 1 }))
  table.insert(body, ui.button({
    glyph = "player-stop-filled",
    variant = "destructive",
    controlSize = "sm",
    tooltip = if rec.phase == "countdown" then "Отмена" else "Остановить (Super+Shift+S)",
    onClick = function() send("stop") end,
  }))
  panel.render(ui.row({ gap = 8, paddingH = 12, paddingV = 8, align = "center" }, body))
end

function update()
  render()
end

noctalia.state.watch("rec", function(v)
  if type(v) == "table" then rec = v end
  render()
end)

function onOpen(_context)
  noctalia.state.set("recbarOpen", true)
  panel.setWantsSecondTicks(true)
  rec = noctalia.state.get("rec") or rec
  render()
end

function onClose()
  noctalia.state.set("recbarOpen", false)
end
