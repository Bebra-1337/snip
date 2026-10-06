--!nonstrict
-- Snip — headless service.
--
-- Pipeline: open → snip.sh freeze (grim snapshot + wayfreeze) → menu panel → action.
-- Photo actions crop the frozen snapshot and hand it to `noctalia msg annotate`; video
-- actions select an area, count down in the recbar panel, then run wf-recorder.
-- Long-running work (slurp, recording) runs as detached snip.sh processes that report
-- back through `noctalia msg plugin bebra/snip:service all <event> <payload>` → onIpc.

local SCRIPT = `{noctalia.pluginDir()}/scripts/snip.sh`
local MENU = "bebra/snip:menu"
local RECBAR = "bebra/snip:recbar"
local COUNTDOWN = 3

-- idle | countdown | recording
local rec = { phase = "idle" }
local pending = nil -- { kind, target, show, audioOut, audioIn } between rec-select and rec-start
local audio = { out = false, inp = false }

local function log(msg)
  noctalia.log(`snip: {msg}`)
end

local function cfg(key)
  return noctalia.getConfig(key)
end

local function scriptArgv(args)
  local primary = noctalia.getColor("primary") or "#ffffff"
  local argv = {
    "env",
    `SNIP_BORDER={primary}`,
    `SNIP_BOX={primary}26`,
    `SNIP_OCR_LANG={cfg("ocr_lang") or "eng+rus"}`,
    SCRIPT,
  }
  for _, a in args do
    table.insert(argv, tostring(a))
  end
  return argv
end

-- Detached: the script reports back over IPC.
local function spawn(...)
  if not noctalia.runAsync(scriptArgv({ ... })) then
    noctalia.notifyError("Ножницы", "Не удалось запустить snip.sh")
  end
end

local function publish()
  noctalia.state.set("rec", {
    phase = rec.phase,
    n = rec.n,
    startedAt = rec.startedAt,
  })
end

local function setRecbar(open)
  if (noctalia.state.get("recbarOpen") == true) ~= open then
    noctalia.togglePanel(RECBAR)
  end
end

local function setPhase(phase)
  rec = { phase = phase }
  noctalia.setUpdateInterval(if phase == "idle" then 1000 else 250)
  publish()
end

-- ── Actions ────────────────────────────────────────────────────────────────

local PHOTO_MODES = { region = true, window = true, screen = true, all = true }
local VIDEO_MODES = { region = true, window = true, screen = true }
local TOOLS = { color = true, ocr = true, qr = true }

local function stopRecording()
  spawn("rec-stop")
end

local function open()
  if rec.phase == "recording" or rec.phase == "starting" then
    stopRecording()
    return
  end
  if rec.phase == "countdown" then
    pending = nil
    setPhase("idle")
    setRecbar(false)
    return
  end
  if noctalia.state.get("menuOpen") == true then
    noctalia.togglePanel(MENU) -- closes; menu's onClose unfreezes
    return
  end
  noctalia.runAsync(scriptArgv({ "freeze" }), function(res)
    if res.exitCode ~= 0 then
      log(`freeze failed: {res.stderr}`)
      return
    end
    noctalia.togglePanel(MENU)
  end, 5000)
end

local function action(p)
  if type(p) ~= "table" then return end
  if TOOLS[p.mode] then
    spawn(p.mode)
  elseif p.kind == "video" and VIDEO_MODES[p.mode] then
    audio.out, audio.inp = p.audioOut == true, p.audioIn == true
    spawn("rec-select", p.mode)
  elseif PHOTO_MODES[p.mode] then
    spawn("shot", p.mode)
  else
    spawn("unfreeze")
  end
end

-- "kind|target|show" from snip.sh rec-select
local function recReady(payload)
  local kind, target, show = string.match(payload or "", "^([^|]+)|([^|]+)|(%d)$")
  if not kind then
    log(`bad recReady payload: {payload}`)
    return
  end
  pending = { kind = kind, target = target, show = show == "1" }
  rec = { phase = "countdown", n = COUNTDOWN, deadline = noctalia.nowMs() + COUNTDOWN * 1000 }
  noctalia.setUpdateInterval(100)
  publish()
  setRecbar(true)
end

local function startRecorder()
  local p = pending
  pending = nil
  if not p then return end
  if not p.show then setRecbar(false) end
  spawn(
    "rec-start",
    p.kind,
    p.target,
    audio.out,
    audio.inp,
    noctalia.expandPath(cfg("video_dir") or "~/Videos/Screencasts"),
    cfg("fps") or 60,
    cfg("codec") or "h264_nvenc"
  )
end

local function recStarted(_path)
  rec = { phase = "recording", startedAt = noctalia.nowMs() }
  noctalia.setUpdateInterval(1000)
  publish()
end

local function recStopped(path)
  setPhase("idle")
  setRecbar(false)
  noctalia.notify("Запись сохранена", `{path}\nПуть скопирован в буфер`)
end

local function recFailed(msg)
  setPhase("idle")
  setRecbar(false)
  log(`recording failed: {msg}`)
  noctalia.notifyError("Запись не удалась", msg or "")
end

local function dispatch(event, payload)
  if event == "open" then open()
  elseif event == "action" then action(payload)
  elseif event == "cancel" then spawn("unfreeze")
  elseif event == "stop" then
    if rec.phase == "countdown" then open() else stopRecording() end
  elseif event == "recReady" then recReady(payload)
  elseif event == "recStarted" then recStarted(payload)
  elseif event == "recStopped" then recStopped(payload)
  elseif event == "recFailed" then recFailed(payload)
  else log(`unknown event: {event}`)
  end
end

function update()
  if rec.phase ~= "countdown" then return end
  local left = rec.deadline - noctalia.nowMs()
  if left <= 0 then
    rec = { phase = "starting" }
    publish()
    startRecorder()
    return
  end
  local n = math.ceil(left / 1000)
  if n ~= rec.n then
    rec.n = n
    publish()
  end
end

-- Panels drive the service through this channel; the CLI and snip.sh use onIpc.
noctalia.state.watch("command", function(cmd)
  if type(cmd) == "table" then
    dispatch(cmd.action, cmd.payload)
  end
end)

function onIpc(event, payload)
  dispatch(event, payload)
end

-- ── Boot ───────────────────────────────────────────────────────────────────

setPhase("idle")
-- Survive a shell/plugin reload in the middle of a recording.
noctalia.runAsync(scriptArgv({ "rec-status" }), function(res)
  if res.exitCode == 0 then
    recStarted(nil)
  end
end)
