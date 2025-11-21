-- Reaper Connect Collaboration Tools – v1.0
-- Invia stem + stato traccia al peer tramite reaper_peer.py

local reaper = reaper

-- ADATTA questi percorsi alla tua installazione
local PYTHON_EXE  = [[C:\Users\user\AppData\Local\Programs\Python\Python310\python.exe]]
local BASE_DIR    = [[C:\Users\user\reaper connect]]
local PEER_SCRIPT = BASE_DIR .. "\\reaper_peer.py"
local LOCAL_STEMS = BASE_DIR .. "\\stems_local"
local CMD_LOG     = BASE_DIR .. "\\last_cmd.txt"

local function ensure_folder(path)
  local cmd = string.format('if not exist "%s" mkdir "%s"', path, path)
  os.execute(cmd)
end

local function sanitize(s)
  s = s or ""
  s = s:gsub("[\"']", "")
  return s
end

local function get_selected_track()
  return reaper.GetSelectedTrack(0, 0)
end

local function render_selected_track(song_folder, common_track, user_id)
  ensure_folder(LOCAL_STEMS)
  local ts = os.date("%Y%m%d_%H%M%S")
  local file_name = string.format("%s__%s__%s__%s.wav", song_folder, common_track, user_id, ts)
  local out_path = LOCAL_STEMS .. "\\" .. file_name

  -- bounds = intero progetto
  local len = reaper.GetProjectLength(0)
  reaper.GetSet_LoopTimeRange(true, false, 0, len, false)

  -- usa impostazioni di render correnti (assicurati: Stems (selected tracks), WAV stereo, ecc.)
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", out_path, true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true) -- 1 = time selection

  local RENDER_CMD = 42230 -- File: Render project, using most recent render settings
  reaper.Main_OnCommand(RENDER_CMD, 0)

  -- Alcune configurazioni di REAPER interpretano RENDER_FILE come cartella base,
  -- e usano il "File name" del dialog come vero nome del .wav (es. Song.wav).
  -- In questo caso out_path diventa una CARTELLA. Qui cerchiamo il vero WAV dentro.
  local folder = out_path
  local real_wav = nil
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(folder, i)
    if not f then break end
    if f:lower():match("%.wav$") then
      real_wav = folder .. "\\" .. f
      break
    end
    i = i + 1
  end

  return real_wav or out_path
end

-- SCRIPT PRINCIPALE
reaper.Undo_BeginBlock()

local tr = get_selected_track()
if not tr then
  reaper.ShowMessageBox("Seleziona una traccia prima di eseguire lo script.", "Net Send", 0)
  return
end

local ok, ret = reaper.GetUserInputs(
  "Invia stem + parametri",
  4,
  "SongFolder,CommonTrackName,UserID,PeerURL (es. http://192.168.1.20:9000):",
  "Song_01,VOX_LEAD,USER_A,http://192.168.1.20:9000"
)
if not ok then return end

local song, common, user, peer_url = ret:match("([^,]+),([^,]+),([^,]+),(.+)")
if not song or not common or not user or not peer_url then
  reaper.ShowMessageBox("Input non valido. Usa le 4 voci richieste.", "Errore", 0)
  return
end

song    = sanitize(song)
common  = sanitize(common)
user    = sanitize(user)
peer_url = peer_url:gsub("%s+", "")

local _, tname = reaper.GetTrackName(tr, "")
local vol  = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
local pan  = reaper.GetMediaTrackInfo_Value(tr, "D_PAN")
local mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE")
local solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO")

tname = sanitize(tname)

local wav_path = render_selected_track(song, common, user)

local cmd = string.format('"%s" "%s" send_stem_and_state "%s" "%s" "%s" "%s" "%s" %f %f %f %f "%s"',
  PYTHON_EXE, PEER_SCRIPT, wav_path, song, common, user, tname, vol, pan, mute, solo, peer_url)

-- Salviamo il comando in un log per poterlo ispezionare dall'esterno
local f = io.open(CMD_LOG, "w")
if f then
  f:write(cmd)
  f:close()
end

local ok_exec = os.execute(cmd)
if ok_exec ~= true and ok_exec ~= 0 then
  reaper.ShowMessageBox("Errore eseguendo il comando:\n\n" .. cmd .. "\n\nCodice: " .. tostring(ok_exec),
    "Net Send Stem + State (errore Python)", 0)
end

reaper.Undo_EndBlock("Net Send Stem + State", -1)
reaper.UpdateArrange()


