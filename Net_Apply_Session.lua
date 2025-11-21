-- Reaper Connect Collaboration Tools – v1.0
-- Scarica la sessione dal peer e applica vol/pan/mute/solo alle tracce comuni

local reaper = reaper

local PYTHON_EXE   = [[C:\Users\user\AppData\Local\Programs\Python\Python310\python.exe]]
local BASE_DIR     = [[C:\Users\user\reaper connect]]
local PEER_SCRIPT  = BASE_DIR .. "\\reaper_peer.py"
local SESSION_DIR  = BASE_DIR .. "\\session_cache"

local function ensure_folder(path)
  local cmd = string.format('if not exist "%s" mkdir "%s"', path, path)
  os.execute(cmd)
end

local function get_or_create_track_by_name(name)
  local proj = 0
  local cnt = reaper.CountTracks(proj)
  for i = 0, cnt - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, tname = reaper.GetTrackName(tr, "")
    if tname == name then
      return tr
    end
  end
  reaper.InsertTrackAtIndex(cnt, true)
  local tr = reaper.GetTrack(proj, cnt)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

reaper.Undo_BeginBlock()

local ok, ret = reaper.GetUserInputs(
  "Applica sessione da peer",
  2,
  "SongFolder,PeerURL (es. http://192.168.1.20:9000):",
  "Song_01,http://192.168.1.20:9000"
)
if not ok then return end

local song, peer_url = ret:match("([^,]+),(.+)")
if not song or not peer_url then
  reaper.ShowMessageBox("Input non valido. Usa le 2 voci richieste.", "Errore", 0)
  reaper.Undo_EndBlock("Apply Session From Peer", -1)
  return
end

ensure_folder(SESSION_DIR)
local session_lua_path = SESSION_DIR .. "\\session_" .. song .. ".lua"

local cmd = string.format('"%s" "%s" pull_session "%s" "%s" "%s"',
  PYTHON_EXE, PEER_SCRIPT, song, peer_url, session_lua_path)

os.execute(cmd)

local ok_load, data = pcall(dofile, session_lua_path)
if not ok_load or type(data) ~= "table" or type(data.tracks) ~= "table" then
  reaper.ShowMessageBox("Impossibile leggere la sessione.", "Errore", 0)
  reaper.Undo_EndBlock("Apply Session From Peer", -1)
  return
end

for _, t in ipairs(data.tracks) do
  local common_name = t.common_track or t.track_name or "COMMON"
  local tr = get_or_create_track_by_name(common_name)
  if tr then
    if t.vol  then reaper.SetMediaTrackInfo_Value(tr, "D_VOL",  t.vol)  end
    if t.pan  then reaper.SetMediaTrackInfo_Value(tr, "D_PAN",  t.pan)  end
    if t.mute ~= nil then reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", t.mute) end
    if t.solo ~= nil then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", t.solo) end
  end
end

reaper.Undo_EndBlock("Apply Session From Peer", -1)
reaper.UpdateArrange()


