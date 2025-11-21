-- Reaper Connect Collaboration Tools – v1.0
-- Importa automaticamente gli stems ricevuti (salvati in stems/<SongFolder>/)

local reaper = reaper

local BASE_DIR   = [[C:\Users\user\reaper connect]]
local STEMS_ROOT = BASE_DIR .. "\\stems"

local function ensure_folder(path)
  local cmd = string.format('if not exist "%s" mkdir "%s"', path, path)
  os.execute(cmd)
end

local function list_wav_in_folder(folder)
  local res = {}
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(folder, i)
    if not f then break end
    if f:lower():match("%.wav$") then
      table.insert(res, folder .. "\\" .. f)
    end
    i = i + 1
  end
  return res
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

local function parse_common_from_filename(path)
  -- Atteso: SongFolder__CommonTrack__UserID__Timestamp.wav
  local filename = path:match("([^\\/:]+)$") or path
  local base = filename:gsub("%.wav$", "")
  local parts = {}
  for part in string.gmatch(base, "([^_]+)__") do
    table.insert(parts, part)
  end
  if #parts >= 2 then
    return parts[2]
  else
    return base
  end
end

local function import_wav_to_track(path, common_name)
  local tr = get_or_create_track_by_name(common_name)
  if not tr then return end
  reaper.SetOnlyTrackSelected(tr)
  local pos = 0.0
  reaper.InsertMedia(path, 0)
  local item_count = reaper.CountTrackMediaItems(tr)
  local item = reaper.GetTrackMediaItem(tr, item_count - 1)
  if item then
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  end
end

-- SCRIPT PRINCIPALE
reaper.Undo_BeginBlock()

local ok, song = reaper.GetUserInputs("Importa stems ricevuti", 1, "SongFolder:", "Song_01")
if not ok then return end

local song_folder = song:gsub("[\\/:*?\"<>|]", "_")
local stems_dir = STEMS_ROOT .. "\\" .. song_folder
ensure_folder(stems_dir)

local wavs = list_wav_in_folder(stems_dir)
if #wavs == 0 then
  reaper.ShowMessageBox("Nessun WAV trovato in " .. stems_dir, "Net Import Stems", 0)
  reaper.Undo_EndBlock("Net Import Stems", -1)
  return
end

for _, p in ipairs(wavs) do
  local common = parse_common_from_filename(p)
  import_wav_to_track(p, common)
end

reaper.Undo_EndBlock("Net Import Stems", -1)
reaper.UpdateArrange()


