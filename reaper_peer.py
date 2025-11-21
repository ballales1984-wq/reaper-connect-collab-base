"""
Reaper Connect Collaboration Tools – v1.0
Backend + client per collaborazione Reaper peer-to-peer.

Uso:
  Server (da tenere sempre acceso su ciascun PC):
      python reaper_peer.py server --host 0.0.0.0 --port 9000

  Client (chiamato dagli script Lua di Reaper):
      python reaper_peer.py send_stem_and_state <local_wav> <song_folder> <common_track> <user_id> <track_name> <vol> <pan> <mute> <solo> <peer_url>
      python reaper_peer.py pull_session <song_folder> <peer_url> <out_lua_path>

Il file di sessione per ogni song_folder viene salvato in:
  sessions/<song_folder>.json
con struttura:
  {
    "tracks": [...],
    "contributions": {
      "USER_ID": { "total_seconds": float }
    }
  }
"""

import os
import sys
import time
import json
import argparse
import wave
from typing import Dict, Any

import requests
from flask import Flask, request, jsonify

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STEMS_DIR = os.path.join(BASE_DIR, "stems")
SESSIONS_DIR = os.path.join(BASE_DIR, "sessions")

os.makedirs(STEMS_DIR, exist_ok=True)
os.makedirs(SESSIONS_DIR, exist_ok=True)


# =============== GESTIONE SESSIONI (FOGLIO COMUNE) ===============

def load_session(song_folder: str) -> Dict[str, Any]:
    path = os.path.join(SESSIONS_DIR, f"{song_folder}.json")
    if not os.path.isfile(path):
        return {"tracks": [], "contributions": {}}
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception:
            data = {}
    if "tracks" not in data:
        data["tracks"] = []
    if "contributions" not in data:
        data["contributions"] = {}
    return data


def save_session(song_folder: str, data: Dict[str, Any]) -> None:
    path = os.path.join(SESSIONS_DIR, f"{song_folder}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def update_track_in_session(
    song_folder: str,
    common_track: str,
    user_id: str,
    track_name: str,
    vol: float,
    pan: float,
    mute: float,
    solo: float,
) -> None:
    sess = load_session(song_folder)
    tracks = sess.setdefault("tracks", [])
    found = False
    for t in tracks:
        if t.get("common_track") == common_track and t.get("user_id") == user_id:
            t["track_name"] = track_name
            t["vol"] = float(vol)
            t["pan"] = float(pan)
            t["mute"] = float(mute)
            t["solo"] = float(solo)
            t["updated_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
            found = True
            break
    if not found:
        tracks.append(
            {
                "song_folder": song_folder,
                "common_track": common_track,
                "user_id": user_id,
                "track_name": track_name,
                "vol": float(vol),
                "pan": float(pan),
                "mute": float(mute),
                "solo": float(solo),
                "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
        )
    save_session(song_folder, sess)


def add_contribution_seconds(song_folder: str, user_id: str, seconds: float) -> None:
    sess = load_session(song_folder)
    contributions = sess.setdefault("contributions", {})
    user = contributions.setdefault(user_id, {"total_seconds": 0.0})
    user["total_seconds"] = float(user.get("total_seconds", 0.0)) + float(seconds)
    save_session(song_folder, sess)


def get_wav_duration_seconds(path: str) -> float:
    try:
        with wave.open(path, "rb") as w:
            frames = w.getnframes()
            rate = w.getframerate()
            if rate == 0:
                return 0.0
            return frames / float(rate)
    except Exception:
        return 0.0


# =============== SERVER FLASK ===============

app = Flask(__name__)


@app.route("/incoming/state", methods=["POST"])
def incoming_state():
    data = request.json or {}
    required = [
        "song_folder",
        "common_track",
        "user_id",
        "track_name",
        "vol",
        "pan",
        "mute",
        "solo",
    ]
    if not all(k in data for k in required):
        return jsonify({"error": "missing fields"}), 400

    update_track_in_session(
        song_folder=data["song_folder"],
        common_track=data["common_track"],
        user_id=data["user_id"],
        track_name=data["track_name"],
        vol=float(data["vol"]),
        pan=float(data["pan"]),
        mute=float(data["mute"]),
        solo=float(data["solo"]),
    )
    return jsonify({"status": "ok"})


@app.route("/incoming/stem", methods=["POST"])
def incoming_stem():
    file = request.files.get("file")
    if not file:
        return jsonify({"error": "missing file"}), 400

    song_folder = request.form.get("song_folder", "Song_Unknown")
    common_track = request.form.get("common_track", "UNKNOWN")
    user_id = request.form.get("user_id", "UNKNOWN")

    target_dir = os.path.join(STEMS_DIR, song_folder)
    os.makedirs(target_dir, exist_ok=True)

    filename = file.filename or f"{common_track}_{user_id}_{int(time.time())}.wav"
    filename = filename.replace("..", "_")
    local_path = os.path.join(target_dir, filename)
    file.save(local_path)

    # aggiorna contributi in base alla durata dello stem
    duration = get_wav_duration_seconds(local_path)
    if duration > 0:
        add_contribution_seconds(song_folder, user_id, duration)

    return jsonify({"status": "ok", "saved_as": local_path, "duration_seconds": duration})


@app.route("/session/<song_folder>", methods=["GET"])
def get_session(song_folder: str):
    sess = load_session(song_folder)
    return jsonify(sess)


# =============== CLIENT (per chiamate da Lua) ===============

def client_send_stem_and_state(
    local_wav: str,
    song_folder: str,
    common_track: str,
    user_id: str,
    track_name: str,
    vol: float,
    pan: float,
    mute: float,
    solo: float,
    peer_url: str,
) -> None:
    peer_url = peer_url.rstrip("/")

    state_payload = {
        "song_folder": song_folder,
        "common_track": common_track,
        "user_id": user_id,
        "track_name": track_name,
        "vol": float(vol),
        "pan": float(pan),
        "mute": float(mute),
        "solo": float(solo),
    }
    r1 = requests.post(f"{peer_url}/incoming/state", json=state_payload, timeout=10)
    r1.raise_for_status()

    with open(local_wav, "rb") as f:
        files = {"file": (os.path.basename(local_wav), f, "audio/wav")}
        data = {
            "song_folder": song_folder,
            "common_track": common_track,
            "user_id": user_id,
        }
        r2 = requests.post(f"{peer_url}/incoming/stem", data=data, files=files, timeout=60)
        r2.raise_for_status()


def client_pull_session(song_folder: str, peer_url: str, out_lua_path: str) -> None:
    peer_url = peer_url.rstrip("/")
    r = requests.get(f"{peer_url}/session/{song_folder}", timeout=10)
    r.raise_for_status()
    sess = r.json()
    # scrive un file .lua: return { ... }
    with open(out_lua_path, "w", encoding="utf-8") as f:
        f.write("return ")
        json.dump(sess, f, indent=2)


# =============== ENTRYPOINT ===============

def main():
    parser = argparse.ArgumentParser(description="Reaper Connect peer backend/client")
    sub = parser.add_subparsers(dest="mode")

    s_server = sub.add_parser("server", help="Avvia il server HTTP locale")
    s_server.add_argument("--host", default="0.0.0.0")
    s_server.add_argument("--port", type=int, default=9000)

    s_send = sub.add_parser("send_stem_and_state", help="Invia stem + stato al peer")
    s_send.add_argument("local_wav")
    s_send.add_argument("song_folder")
    s_send.add_argument("common_track")
    s_send.add_argument("user_id")
    s_send.add_argument("track_name")
    s_send.add_argument("vol", type=float)
    s_send.add_argument("pan", type=float)
    s_send.add_argument("mute", type=float)
    s_send.add_argument("solo", type=float)
    s_send.add_argument("peer_url")

    s_pull = sub.add_parser("pull_session", help="Scarica sessione dal peer in formato .lua")
    s_pull.add_argument("song_folder")
    s_pull.add_argument("peer_url")
    s_pull.add_argument("out_lua_path")

    args = parser.parse_args()

    if args.mode == "server":
        app.run(host=args.host, port=args.port)
    elif args.mode == "send_stem_and_state":
        client_send_stem_and_state(
            args.local_wav,
            args.song_folder,
            args.common_track,
            args.user_id,
            args.track_name,
            args.vol,
            args.pan,
            args.mute,
            args.solo,
            args.peer_url,
        )
    elif args.mode == "pull_session":
        client_pull_session(args.song_folder, args.peer_url, args.out_lua_path)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()


