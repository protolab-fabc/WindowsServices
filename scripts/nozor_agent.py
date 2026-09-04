import os
import sys
import re
import json
import time
import random
import socket
import struct
import asyncio
import subprocess
from datetime import datetime
from typing import List, Dict, Any, Set
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
import uvicorn
from openai import OpenAI
from contextlib import asynccontextmanager

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

# Paths & Settings
BASE_DIR = r"C:\WindowsServices\scripts"
WEB_DIR = os.path.join(BASE_DIR, "web")
QUEUE_FILE = os.path.join(BASE_DIR, "nozor_queue.json")
EVENTS_FILE = os.path.join(BASE_DIR, "nozor_events.json")
CONFIG_FILE = os.path.join(BASE_DIR, "nozor_config.json")
PORT = 8090

# Default configuration
DEFAULT_CONFIG = {
    "api_key": "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",
    "models": [
        "openrouter/free",
        "google/gemma-4-31b-it:free",
        "nvidia/nemotron-3-ultra-550b-a55b:free",
        "minimax/minimax-m3:free",
        "nvidia/nemotron-3-super-120b-a12b:free",
        "meta-llama/llama-3.3-70b-instruct"
    ],
    "current_model": "openrouter/free",
    "auto_switch": True,
    "rpg_enabled": True,
    "rpg_interval_minutes": 15,
    "rpg_target": "random"
}

config = dict(DEFAULT_CONFIG)

def load_config():
    global config
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                loaded = json.load(f)
                config.update(loaded)
        except Exception as e:
            print(f"[CONFIG ERROR] Chargement: {e}", flush=True)

def save_config():
    try:
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[CONFIG ERROR] Sauvegarde: {e}", flush=True)

load_config()

def create_client():
    return OpenAI(
        base_url="https://openrouter.ai/api/v1",
        api_key=config.get("api_key", DEFAULT_CONFIG["api_key"]),
        default_headers={
            "HTTP-Referer": "http://localhost:8090",
            "X-Title": "NozorAgent"
        }
    )

client = create_client()

# Global State
stats = {
    "requests_count": 0,
    "actions_count": 0,
    "rpg_events_count": 0,
    "last_active": "En attente"
}
events_history: List[Dict[str, Any]] = []

def load_events():
    global events_history
    if os.path.exists(EVENTS_FILE):
        try:
            with open(EVENTS_FILE, 'r', encoding='utf-8') as f:
                events_history = json.load(f)
                if len(events_history) > 200:
                    events_history = events_history[-200:]
        except Exception:
            events_history = []

def save_events():
    try:
        with open(EVENTS_FILE, 'w', encoding='utf-8') as f:
            json.dump(events_history[-200:], f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[ERROR] Saving events: {e}", flush=True)

load_events()

def sanitize_minecraft_command(cmd: str) -> str:
    """
    Auto-corrige les syntaxes NBT obsolètes (< 1.20.5 / 1.21.4+) pour Minecraft 1.21+:
    - Traduit /give {Enchantments:[...]} -> [enchantments={...}]
    - Supprime les guillemets superflus autour des Text Components (custom_name='{...}' -> custom_name={...})
      pour éviter que le jeu affiche le JSON brut '{"text":"..."}' à l'écran ou dans les messages de mort !
    """
    stripped = cmd.strip()
    if stripped.startswith('/'):
        stripped = stripped[1:].strip()

    # 1. Traitement spécifique pour conversion /give legacy NBT < 1.20.5
    m = re.match(r"^give\s+(\S+)\s+([a-z0-9_:]+)\{(.*)\}(.*)$", stripped, re.IGNORECASE)
    if m:
        target, item, nbt, trailing = m.group(1), m.group(2), m.group(3), m.group(4)
        components = []

        # 1. Enchantements: Enchantments:[{id:"?minecraft:([a-z_]+)"?,lvl:(\d+).*?}, ...]
        ench_matches = re.findall(r'id\s*:\s*["\']?(?:minecraft:)?([a-z_]+)["\']?\s*,\s*lvl\s*:\s*(\d+)', nbt, re.IGNORECASE)
        if not ench_matches:
            ench_matches = re.findall(r'lvl\s*:\s*(\d+)\s*,\s*id\s*:\s*["\']?(?:minecraft:)?([a-z_]+)["\']?', nbt, re.IGNORECASE)
            ench_matches = [(em[1], em[0]) for em in ench_matches]

        if ench_matches:
            ench_str = ",".join([f"\"{ench[0].lower()}\":{int(ench[1])}" for ench in ench_matches])
            components.append(f"enchantments={{{ench_str}}}")

        # 2. Custom name (PAS de guillemets externes autour du composé {text:...})
        name_match = re.search(r'Name\s*:\s*\'(.*?)\'', nbt, re.IGNORECASE)
        if not name_match:
            name_match = re.search(r'Name\s*:\s*\"(.*?)\"', nbt, re.IGNORECASE)
        if name_match:
            raw_name = name_match.group(1).replace('\\"', '"').replace("\\'", "'")
            if raw_name.startswith('{') and raw_name.endswith('}'):
                components.append(f"custom_name={raw_name}")
            else:
                components.append(f"custom_name={{\"text\":\"{raw_name}\"}}")

        # 3. Lore (PAS de guillemets externes autour des composés JSON)
        lore_match = re.search(r'Lore\s*:\s*\[(.*?)\]', nbt, re.IGNORECASE)
        if lore_match:
            raw_lore = lore_match.group(1).strip()
            fixed_lore = re.sub(r"'({\s*\"text\".*?})'", r'\1', raw_lore)
            fixed_lore = re.sub(r'"({\s*\"text\".*?})"', r'\1', fixed_lore)
            components.append(f"lore=[{fixed_lore}]")

        # 4. Unbreakable
        if re.search(r'Unbreakable\s*:\s*1', nbt, re.IGNORECASE):
            components.append("unbreakable={}")

        if components:
            comp_str = "[" + ",".join(components) + "]"
            stripped = f"give {target} {item}{comp_str}{trailing}"

    # 2. Correction générale pour custom_name et CustomName sous forme '{"text":...}'
    # En 1.21.4+, custom_name='{"text":"..."}' affiche le JSON brut {"text":"..."} à l'écran !
    # Il faut enlever les guillemets externes pour que ce soit custom_name={"text":"..."}
    stripped = re.sub(r"custom_name\s*=\s*'(\{[^']*\})'", r'custom_name=\1', stripped)
    stripped = re.sub(r'custom_name\s*=\s*"(\{[^"]*\})"', r'custom_name=\1', stripped)

    stripped = re.sub(r"CustomName\s*:\s*'(\{[^']*\})'", r'CustomName:\1', stripped)
    stripped = re.sub(r'CustomName\s*:\s*"(\{[^"]*\})"', r'CustomName:\1', stripped)

    # Pareil pour lore=[ '{"text":...}' ]
    def unquote_lore(match):
        prefix = match.group(1)
        body = match.group(2)
        suffix = match.group(3)
        clean_body = re.sub(r"'({\s*\"text\".*?})'", r'\1', body)
        clean_body = re.sub(r'"({\s*\"text\".*?})"', r'\1', clean_body)
        return f"{prefix}{clean_body}{suffix}"

    stripped = re.sub(r'(lore\s*=\s*\[)(.*?)(\])', unquote_lore, stripped, flags=re.DOTALL)

    # 3. Correction pour title et tellraw sous forme '{"text":...}'
    stripped = re.sub(r"(\btitle\s+\S+\s+(?:title|subtitle|actionbar)\s+)'(\{[^']*\})'", r'\1\2', stripped, flags=re.IGNORECASE)
    stripped = re.sub(r'(\btitle\s+\S+\s+(?:title|subtitle|actionbar)\s+)"(\{[^"]*\})"', r'\1\2', stripped, flags=re.IGNORECASE)
    stripped = re.sub(r"(\btellraw\s+\S+\s+)'(\{[^']*\})'", r'\1\2', stripped, flags=re.IGNORECASE)
    stripped = re.sub(r'(\btellraw\s+\S+\s+)"(\{[^"]*\})"', r'\1\2', stripped, flags=re.IGNORECASE)

    if stripped != cmd:
        print(f"[RCON AUTO-FIX] '{cmd}' -> '{stripped}'", flush=True)

    return stripped

# Native RCON via TCP Socket (High Speed & Full Unicode / Quotes)
def rcon_exec(cmd: str, timeout: float = 6.0) -> str:
    """Exécute une commande Minecraft directement via socket TCP RCON."""
    cmd = sanitize_minecraft_command(cmd)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(("127.0.0.1", 25575))

        def send_pkt(req_id, pkt_type, body):
            b = body.encode('utf-8')
            s.send(struct.pack('<iii', len(b) + 10, req_id, pkt_type) + b + b'\x00\x00')

        def read_pkt():
            raw_len = s.recv(4)
            if not raw_len:
                return None
            l = struct.unpack('<i', raw_len)[0]
            data = b''
            while len(data) < l:
                chunk = s.recv(l - len(data))
                if not chunk:
                    break
                data += chunk
            return data[8:-2].decode('utf-8', errors='ignore')

        # Auth
        send_pkt(1, 3, "ton_mot_de_passe_rcon")
        auth_resp = read_pkt()
        if auth_resp is None:
            return "Erreur auth RCON"

        # Commande
        send_pkt(2, 2, cmd)
        resp = read_pkt()
        return resp if resp is not None else ""
    except Exception as e:
        return f"Erreur RCON: {e}"
    finally:
        s.close()

def get_online_players() -> List[str]:
    """Retourne la liste des joueurs actuellement connectés au serveur Minecraft."""
    res = rcon_exec("list")
    if ":" in res:
        names_part = res.split(":", 1)[1].strip()
        if names_part:
            return [name.strip() for name in names_part.split(",") if name.strip()]
    return []

# WebSocket Manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)

    async def broadcast(self, message: dict):
        disconnected = set()
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                disconnected.add(connection)
        for dead in disconnected:
            self.active_connections.discard(dead)

manager = ConnectionManager()

async def emit_event(ev_type: str, data: dict):
    """Enregistre et diffuse un événement en direct."""
    event = {
        "id": f"ev_{int(time.time() * 1000)}",
        "type": ev_type,
        "timestamp": datetime.now().isoformat(),
        **data
    }
    events_history.append(event)
    save_events()
    await manager.broadcast(event)
    print(f"[{ev_type.upper()}] {data.get('content') or data}", flush=True)

async def switch_model_auto(failed_model: str, reason: str) -> str:
    """Bascule automatiquement vers le modèle suivant dans la liste de priorité."""
    models = config.get("models", DEFAULT_CONFIG["models"])
    if not models:
        models = DEFAULT_CONFIG["models"]

    try:
        idx = models.index(failed_model)
        next_model = models[(idx + 1) % len(models)]
    except ValueError:
        next_model = models[0]

    config["current_model"] = next_model
    save_config()

    print(f"[AUTO-SWITCH] Bascule de {failed_model} vers {next_model} | Raison: {reason}", flush=True)

    await emit_event("model_switch", {
        "old_model": failed_model,
        "new_model": next_model,
        "reason": reason,
        "content": f"⚠️ {reason} sur '{failed_model}'. Bascule automatique vers '{next_model}'..."
    })

    await manager.broadcast({
        "type": "model_update",
        "model": next_model
    })

    return next_model

# Catalogue des Événements RPG
RPG_EVENTS = {
    "meteorite": {
        "id": "meteorite",
        "name": "Météorite Stellaire & Trésor Céleste",
        "icon": "☄️",
        "title": "☄️ MÉTÉORITE CÉLESTE",
        "subtitle": "Un fragment ardent s'est écrasé près de {player} !",
        "title_color": "gold",
        "subtitle_color": "yellow",
        "lore": "Le ciel se déchire et un météore incandescent s'écrase sur la terre ! Il renferme un coffre céleste protégé par des créatures de magma.",
        "commands": [
            "playsound minecraft:entity.lightning_bolt.thunder master @a",
            "playsound minecraft:entity.generic.explode master @a",
            "execute at {player} run setblock ^ ^ ^4 minecraft:magma_block",
            'execute at {player} run setblock ^ ^1 ^4 minecraft:chest{Items:[{Slot:0b,id:"minecraft:diamond",Count:4b},{Slot:1b,id:"minecraft:golden_apple",Count:2b},{Slot:2b,id:"minecraft:netherite_scrap",Count:1b}]}',
            "execute at {player} run summon minecraft:magma_cube ^ ^ ^6 {Size:2}",
            "execute at {player} run summon minecraft:blaze ^ ^ ^7"
        ]
    },
    "invasion": {
        "id": "invasion",
        "name": "Invasion de la Horde Maudite",
        "icon": "⚔️",
        "title": "⚔️ INVASION DE LA HORDE",
        "subtitle": "La Légion Maudite assaille {player} !",
        "title_color": "dark_red",
        "subtitle_color": "red",
        "lore": "Le cor de guerre retentit dans les brumes. Des guerriers squelettes et des berserkers zombifiés émergent du néant pour réclamer vos âmes !",
        "commands": [
            "playsound minecraft:event.raid.horn master @a",
            'execute at {player} run summon minecraft:skeleton ^3 ^ ^3 {ArmorItems:[{},{},{id:"minecraft:iron_chestplate",Count:1b},{id:"minecraft:iron_helmet",Count:1b}],HandItems:[{id:"minecraft:bow",Count:1b},{}]}',
            'execute at {player} run summon minecraft:zombie ^-3 ^ ^3 {ArmorItems:[{},{},{id:"minecraft:iron_chestplate",Count:1b},{id:"minecraft:iron_helmet",Count:1b}],HandItems:[{id:"minecraft:iron_sword",Count:1b},{}]}',
            'execute at {player} run summon minecraft:zombie ^ ^ ^5 {ArmorItems:[{},{},{},{id:"minecraft:diamond_helmet",Count:1b}],HandItems:[{id:"minecraft:iron_axe",Count:1b},{}]}'
        ]
    },
    "boss": {
        "id": "boss",
        "name": "Le Seigneur Revenant Nozor",
        "icon": "☠️",
        "title": "☠️ BOSS : SEIGNEUR REVENANT",
        "subtitle": "Un titan spectral réclame vengeance devant {player} !",
        "title_color": "dark_purple",
        "subtitle_color": "light_purple",
        "lore": "Les ténèbres s'épaississent et un Seigneur Revenant équipé d'une armure en Netherite et d'une lame runique surgit devant vous ! Terrassez-le pour obtenir son butin.",
        "commands": [
            "playsound minecraft:entity.wither.spawn master @a",
            """execute at {player} run summon minecraft:wither_skeleton ^ ^ ^4 {CustomName:{"text":"★ Seigneur Revenant Nozor ★","color":"dark_red","bold":true},CustomNameVisible:1b,Glowing:1b,ArmorItems:[{id:"minecraft:netherite_boots",Count:1b},{id:"minecraft:netherite_leggings",Count:1b},{id:"minecraft:netherite_chestplate",Count:1b},{id:"minecraft:netherite_helmet",Count:1b}],HandItems:[{id:"minecraft:diamond_sword",Count:1b,tag:{Enchantments:[{id:"sharpness",lvl:3s}]}},{id:"minecraft:shield",Count:1b}],HandDropChances:[1.0f,0.0f],ActiveEffects:[{Id:5,Amplifier:1,Duration:6000}]}"""
        ]
    },
    "blessing": {
        "id": "blessing",
        "name": "Bénédiction Céleste des Arcanes",
        "icon": "✨",
        "title": "✨ BÉNÉDICTION DIVINE",
        "subtitle": "Nozor insuffle la puissance des héros !",
        "title_color": "aqua",
        "subtitle_color": "green",
        "lore": "Une pluie d'étincelles dorées tombe du ciel. La force héroïque, la célérité et la régénération habitent désormais tous les aventuriers !",
        "commands": [
            "playsound minecraft:ui.toast.challenge_complete master @a",
            "effect give @a minecraft:speed 180 1",
            "effect give @a minecraft:regeneration 60 1",
            "effect give @a minecraft:strength 180 0",
            "execute at {player} run particle minecraft:totem_of_undying ~ ~1 ~ 0.8 1.2 0.8 0.1 120"
        ]
    },
    "blood_moon": {
        "id": "blood_moon",
        "name": "La Nuit du Cauchemar",
        "icon": "🌑",
        "title": "🌑 NUIT DU CAUCHEMAR",
        "subtitle": "Le voile se déchire... Survivrez-vous à l'effroi ?",
        "title_color": "dark_red",
        "subtitle_color": "red",
        "lore": "Le soleil disparaît brusquement, la foudre s'abat et les créatures cauchemardesques envahissent le monde.",
        "commands": [
            "time set midnight",
            "weather thunder",
            "playsound minecraft:ambient.cave master @a",
            "execute at {player} run summon minecraft:phantom ^ ^10 ^",
            "execute at {player} run summon minecraft:creeper ^4 ^ ^4 {powered:1b}"
        ]
    },
    "treasure": {
        "id": "treasure",
        "name": "Le Trésor des Arcanes",
        "icon": "💎",
        "title": "💎 TRÉSOR DES ARCANES",
        "subtitle": "Un coffre mystique gardé est apparu près de {player} !",
        "title_color": "gold",
        "subtitle_color": "aqua",
        "lore": "Un sanctuaire en obsidienne émerge du sol, renfermant un coffre magique protégé par un Évocateur et ses esprits maléfiques.",
        "commands": [
            "playsound minecraft:block.portal.travel master @a",
            "execute at {player} run setblock ^ ^ ^4 minecraft:crying_obsidian",
            'execute at {player} run setblock ^ ^1 ^4 minecraft:chest{Items:[{Slot:0b,id:"minecraft:emerald",Count:16b},{Slot:1b,id:"minecraft:enchanted_golden_apple",Count:1b},{Slot:2b,id:"minecraft:experience_bottle",Count:8b}]}',
            "execute at {player} run summon minecraft:evoker ^ ^ ^6"
        ]
    }
}

async def generate_ai_rpg_event(target_player: str) -> dict:
    """Génère un événement RPG totalement imprévisible et inédit via l'IA."""
    prompt = f"""Tu es Nozor, le Maître du Jeu (Game Master) RPG d'un serveur Minecraft.
Invente un événement RPG immersif, épique et original pour le joueur {target_player}.
Réponds UNIQUEMENT avec un JSON strict valide sans texte avant ni après, sous ce format:
{{
  "name": "Nom de l'event (ex: 🌪️ Tempête du Dragon)",
  "icon": "emoji",
  "title": "Titre affiché sur l'écran",
  "subtitle": "Sous-titre affiché",
  "title_color": "gold ou red ou aqua ou dark_purple",
  "subtitle_color": "yellow ou red ou green",
  "lore": "1 ou 2 phrases immersives de mise en scène",
  "commands": [
    "commande 1 (ex: playsound ... ou effect give ...)",
    "commande 2 (ex: execute at {target_player} run summon ...)",
    "commande 3"
  ]
}}
Note Minecraft 1.21+: Pour CustomName ou custom_name, n'entoure jamais le JSON de guillemets externes (ex: CustomName:{"text":"Nom","color":"red"})."""
    try:
        cur_model = config.get("current_model", "openrouter/free")
        response = await asyncio.to_thread(
            client.chat.completions.create,
            model=cur_model,
            messages=[{"role": "user", "content": prompt}],
            timeout=20
        )
        content = response.choices[0].message.content.strip()
        # Extraire JSON
        json_match = re.search(r'\{.*\}', content, re.DOTALL)
        if json_match:
            raw_json = json_match.group(0)
            try:
                data = json.loads(raw_json, strict=False)
            except Exception:
                # Réparer les antislashs invalides (ex: commandes Minecraft avec NBT)
                clean_json = re.sub(r'\\(?![/"\\bfnrtu])', r'\\\\', raw_json)
                data = json.loads(clean_json, strict=False)
            data["id"] = "ai_random"
            return data
    except Exception as e:
        print(f"[AI RPG EVENT ERROR] {e}", flush=True)

    # Fallback si l'IA échoue
    fb = dict(RPG_EVENTS["meteorite"])
    fb["name"] = "Événement Mystique Aléatoire"
    return fb

async def execute_rpg_event(event_type: str, target_player: str = None) -> dict:
    """Exécute un événement RPG complet dans Minecraft et le diffuse."""
    global stats

    online_players = await asyncio.to_thread(get_online_players)
    if not target_player or target_player == "random" or target_player not in online_players:
        if online_players:
            target_player = random.choice(online_players)
        else:
            target_player = "Vibrions"

    if event_type == "ai_random":
        event_def = await generate_ai_rpg_event(target_player)
    elif event_type in RPG_EVENTS:
        event_def = dict(RPG_EVENTS[event_type])
    else:
        chosen_key = random.choice(list(RPG_EVENTS.keys()))
        event_def = dict(RPG_EVENTS[chosen_key])

    name = event_def.get("name", "Événement RPG")
    icon = event_def.get("icon", "⚔️")
    title = event_def.get("title", "⚔️ ÉVÉNEMENT RPG").replace("{player}", target_player)
    subtitle = event_def.get("subtitle", "Préparez-vous !").replace("{player}", target_player)
    t_color = event_def.get("title_color", "gold")
    s_color = event_def.get("subtitle_color", "yellow")
    lore = event_def.get("lore", "").replace("{player}", target_player)
    raw_cmds = event_def.get("commands", [])

    # 1. Annonces visuelles et sonores dans Minecraft
    title_cmd = f'title @a title {{"text":"{title}","color":"{t_color}","bold":true}}'
    sub_cmd = f'title @a subtitle {{"text":"{subtitle}","color":"{s_color}"}}'
    chat_cmd = f'tellraw @a {{"text":"[Nozor RPG] {lore}","color":"gold","italic":true}}'

    await asyncio.to_thread(rcon_exec, title_cmd)
    await asyncio.to_thread(rcon_exec, sub_cmd)
    await asyncio.to_thread(rcon_exec, chat_cmd)

    # 2. Exécution des commandes in-game
    executed_cmds = []
    for cmd_template in raw_cmds:
        cmd = cmd_template.replace("{player}", target_player)
        out = await asyncio.to_thread(rcon_exec, cmd)
        executed_cmds.append({"command": cmd, "output": out})
        stats["actions_count"] += 1

    stats["rpg_events_count"] += 1
    stats["last_active"] = datetime.now().strftime("%H:%M:%S")

    # 3. Diffusion de l'événement sur l'interface Web
    event_payload = {
        "event_id": event_def.get("id", event_type),
        "name": name,
        "icon": icon,
        "target_player": target_player,
        "lore": lore,
        "title": title,
        "subtitle": subtitle,
        "commands_count": len(executed_cmds),
        "commands": executed_cmds
    }
    await emit_event("rpg_event", event_payload)

    return event_payload

# Boucle Game Master RPG Automatique
async def rpg_game_master_loop():
    """Déclenche périodiquement un événement RPG aléatoire si des joueurs sont connectés."""
    print("[RPG GM LOOP] Démarrage du Game Master RPG autonome", flush=True)
    while True:
        try:
            load_config()
            interval_mins = int(config.get("rpg_interval_minutes", 15))
            await asyncio.sleep(max(interval_mins, 1) * 60)

            load_config()
            if config.get("rpg_enabled", False):
                players = await asyncio.to_thread(get_online_players)
                if players:
                    print(f"[RPG GM] Lancement automatique d'un event pour {len(players)} joueur(s) en ligne", flush=True)
                    # 70% chances event catalog, 30% chances event IA inédit
                    chosen_type = "ai_random" if random.random() < 0.3 else random.choice(list(RPG_EVENTS.keys()))
                    await execute_rpg_event(chosen_type)
        except Exception as e:
            print(f"[RPG GM ERROR] {e}", flush=True)
            await asyncio.sleep(10)

# Outils de l'Agent
def run_shell_command(command: str) -> str:
    """Exécute une commande PowerShell sur le serveur hôte Windows."""
    print(f"[SHELL] Executing: {command}", flush=True)
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
            capture_output=True, text=True, timeout=15, cwd=r"C:\WindowsServices"
        )
        out = result.stdout.strip()
        # Filtrer l'avertissement InitializeDefaultDrives s'il apparaît
        lines = [line for line in out.splitlines() if "InitializeDefaultDrives" not in line]
        clean_out = "\n".join(lines).strip()
        return clean_out if clean_out else (result.stderr.strip() or "Commande exécutée avec succès (sans sortie).")
    except Exception as e:
        return f"Erreur Shell: {e}"

def read_file(path: str) -> str:
    """Lit le contenu d'un fichier sur le serveur hôte."""
    print(f"[FILE] Reading: {path}", flush=True)
    try:
        resolved = os.path.join(r"C:\WindowsServices", path) if not os.path.isabs(path) else path
        with open(resolved, 'r', encoding='utf-8-sig', errors='ignore') as f:
            return f.read(5000)
    except Exception as e:
        return f"Erreur lecture fichier: {e}"

def speak_to_player_minecraft(player: str, message: str):
    """Envoie un message tellraw au joueur Minecraft."""
    clean_msg = message.replace('"', "'").replace('\n', ' ')
    clean_msg = re.sub(r'[^\x00-\x7F\u00A0-\u00FF\u0100-\u017F]', '', clean_msg)
    clean_msg = re.sub(r'\s+', ' ', clean_msg).strip()
    if not clean_msg:
        return
    tellraw_cmd = f'tellraw {player} {{"text":"[Nozor] {clean_msg}","color":"gold"}}'
    rcon_exec(tellraw_cmd)

tools = [
    {
        "type": "function",
        "function": {
            "name": "execute_rcon_command",
            "description": "Exécute une commande Minecraft via RCON (ex: 'summon zombie ~ ~ ~', 'give <player> stick[custom_name={\"text\":\"Bâton Magique\",\"color\":\"gold\"},enchantments={\"knockback\":100}] 1', 'weather clear', 'time set day'). Note 1.21+: les noms d'items s'écrivent [custom_name={\"text\":\"...\"}] SANS guillemets externes autour des accolades {}.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "La commande Minecraft exacte sans slash initial"
                    }
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "trigger_rpg_event",
            "description": "Déclenche un événement RPG immersif avec sons, titres à l'écran, apparition de créatures/boss, météores ou bénédictions.",
            "parameters": {
                "type": "object",
                "properties": {
                    "event_type": {
                        "type": "string",
                        "enum": ["meteorite", "invasion", "boss", "blessing", "blood_moon", "treasure", "ai_random"],
                        "description": "Le type d'événement RPG"
                    },
                    "target_player": {
                        "type": "string",
                        "description": "Nom du joueur ciblé par l'événement"
                    }
                },
                "required": ["event_type"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": "Exécute une commande PowerShell sur l'hôte Windows du serveur.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "La commande PowerShell"
                    }
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Lit le contenu d'un fichier sur l'hôte Windows.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Chemin absolu du fichier"
                    }
                },
                "required": ["path"]
            }
        }
    }
]

async def process_agent_request(instruction: str, player: str, pos: Any = None, rot: Any = None):
    """Boucle ReAct autonome avec tools Minecraft et Game Master RPG."""
    global stats

    stats["requests_count"] += 1
    stats["last_active"] = datetime.now().strftime("%H:%M:%S")

    await emit_event("request", {
        "player": player,
        "instruction": instruction,
        "position": pos,
        "rotation": rot
    })

    system_prompt = f"""Tu es Nozor, l'IA et Maître du Jeu (Game Master) autonome du serveur Minecraft.
Le joueur qui te sollicite s'appelle {player}.
Position du joueur: {pos}, Rotation: {rot}.

Tu as accès à des outils réels:
- trigger_rpg_event : pour déclencher un événement RPG immersif (meteorite, invasion, boss, blessing, blood_moon, treasure, ai_random)
- execute_rcon_command : pour lancer des commandes Minecraft (summon, give, time, weather, teleport, gamerule, etc.)
- run_shell_command : pour exécuter des scripts système si nécessaire
- read_file : pour lire des fichiers de config ou logs

RÈGLES IMPORTANTES:
1. Si le joueur te demande un event, un événement RPG, un boss, ou un défi, appelle DIRECTEMENT l'outil 'trigger_rpg_event' (utilise "ai_random" s'il ne précise pas lequel) ! Ne te contente pas de lister les événements, AGIS en jeu !
2. Pour faire apparaître un mob ou un item devant le joueur ({player}), utilise execute_rcon_command.
3. COMMANDES ET SYNTAXE MINECRAFT 1.21+:
   - POUR /give AVEC ENCHANTEMENTS : utilise IMPÉRATIVEMENT les composants `[enchantments={{...}}]` et JAMAIS l'ancien NBT `{{Enchantments:[...]}}` qui provoque une erreur fatale !
     Exemple stick recul 100 : `give {player} stick[enchantments={{"knockback":100}}] 1`
     Exemple épée tranchant 5 : `give {player} diamond_sword[enchantments={{"sharpness":5,"fire_aspect":2}}] 1`
     Exemple nom custom : `give {player} stick[custom_name={{"text":"Bâton Magique","color":"gold"}},enchantments={{"knockback":100}}] 1`
     CRITIQUE: N'entoure JAMAIS le JSON `{{"text":...}}` de guillemets simples ou doubles dans custom_name ou CustomName ! Écris directement `custom_name={{"text":"..."}}`, sinon Minecraft affichera le texte JSON brut en jeu !
     Exemple incassable : `give {player} diamond_sword[unbreakable={{}}] 1`
   - Pour bloquer/débloquer le temps : `gamerule advance_time false` / `true` (et non doDaylightCycle).
   - Pour la météo : `gamerule advance_weather false` / `true`.
   - Pour conserver l'inventaire : `gamerule keep_inventory true`.
4. À la fin, réponds clairement et de façon théâtrale/amicale au joueur dans le chat."""

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": instruction}
    ]

    executed_tools = []
    models_pool = list(config.get("models", DEFAULT_CONFIG["models"]))

    for step in range(8):
        response = None
        max_attempts = max(len(models_pool), 3)

        for attempt in range(max_attempts):
            cur_model = config.get("current_model", "openrouter/free")
            try:
                response = await asyncio.to_thread(
                    client.chat.completions.create,
                    model=cur_model,
                    messages=messages,
                    tools=tools,
                    tool_choice="auto",
                    timeout=25
                )
                break
            except Exception as e:
                err_str = str(e)
                print(f"[API ERROR on {cur_model}] {err_str}", flush=True)

                if not config.get("auto_switch", True):
                    await emit_event("thought", {"content": f"Erreur API ({cur_model}): {err_str[:120]}"})
                    break

                if "402" in err_str or "credit" in err_str.lower():
                    reason = "Crédits épuisés (Erreur 402)"
                elif "429" in err_str or "rate limit" in err_str.lower():
                    reason = "Limite de requêtes atteinte (Erreur 429)"
                elif "404" in err_str or "unavailable" in err_str.lower():
                    reason = "Modèle indisponible (Erreur 404)"
                else:
                    reason = f"Erreur fournisseur ({err_str[:40]}...)"

                await switch_model_auto(cur_model, reason)
                await asyncio.sleep(1)

        if not response:
            print(f"[ERROR] Impossible d'obtenir une réponse d'aucun modèle pour: '{instruction}'", flush=True)
            break

        choice = response.choices[0]
        message = choice.message
        messages.append(message)

        if message.tool_calls:
            for tool_call in message.tool_calls:
                fn_name = tool_call.function.name
                raw_args = tool_call.function.arguments
                try:
                    args = json.loads(raw_args)
                except Exception:
                    args = {"command": raw_args}

                tool_output = ""
                if fn_name == "trigger_rpg_event":
                    ev_type = args.get("event_type", "meteorite")
                    target_p = args.get("target_player") or player
                    res_rpg = await execute_rpg_event(ev_type, target_p)
                    tool_output = f"Événement RPG '{res_rpg.get('name')}' déclenché pour {target_p} avec succès !"
                    executed_tools.append(f"RPG Event: {res_rpg.get('name')}")
                elif fn_name == "execute_rcon_command":
                    cmd = args.get("command", "")
                    tool_output = await asyncio.to_thread(rcon_exec, cmd)
                    stats["actions_count"] += 1
                    executed_tools.append(cmd)
                    await emit_event("action", {
                        "tool": "execute_rcon_command",
                        "command": cmd,
                        "output": tool_output
                    })
                elif fn_name == "run_shell_command":
                    cmd = args.get("command", "")
                    tool_output = await asyncio.to_thread(run_shell_command, cmd)
                    stats["actions_count"] += 1
                    executed_tools.append(cmd)
                    await emit_event("action", {
                        "tool": "run_shell_command",
                        "command": cmd,
                        "output": tool_output
                    })
                elif fn_name == "read_file":
                    p = args.get("path", "")
                    tool_output = await asyncio.to_thread(read_file, p)
                    stats["actions_count"] += 1
                    executed_tools.append(f"read_file: {p}")
                    await emit_event("action", {
                        "tool": "read_file",
                        "command": f"Lecture de {p}",
                        "output": tool_output[:300]
                    })
                else:
                    tool_output = "Outil inconnu"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "name": fn_name,
                    "content": str(tool_output)
                })

            continue

        if message.content and message.content.strip():
            text = message.content.strip()
            await emit_event("speech", {
                "player": player,
                "content": text
            })
            await asyncio.to_thread(speak_to_player_minecraft, player, text)
            return

        if not message.tool_calls:
            break

    if executed_tools:
        fallback_speech = f"C'est fait pour {player} ! ({len(executed_tools)} action(s) accomplie(s))"
        await emit_event("speech", {
            "player": player,
            "content": fallback_speech
        })
        await asyncio.to_thread(speak_to_player_minecraft, player, fallback_speech)

# Polling Queue Loop
async def queue_watcher_loop():
    """Vérifie la file d'attente issue du chat Minecraft."""
    print("[QUEUE LOOP] Démarrage de la surveillance nozor_queue.json", flush=True)
    while True:
        try:
            if os.path.exists(QUEUE_FILE):
                content = ""
                with open(QUEUE_FILE, 'r', encoding='utf-8-sig') as f:
                    content = f.read().strip()

                if content:
                    try:
                        data = json.loads(content)
                        requests_list = data.get("requests", [])
                        if requests_list:
                            req = requests_list[0]
                            remaining = requests_list[1:]
                            with open(QUEUE_FILE, 'w', encoding='utf-8') as f:
                                json.dump({"requests": remaining}, f, ensure_ascii=False, indent=2)

                            instruction = req.get("instruction", "")
                            player = req.get("player", "Joueur")
                            pos = req.get("position")
                            rot = req.get("rotation")

                            print(f"[QUEUE] Traitement requête de {player}: '{instruction}'", flush=True)
                            await process_agent_request(instruction, player, pos, rot)
                    except json.JSONDecodeError as err:
                        print(f"[QUEUE JSON DECODE ERROR] {err}", flush=True)
        except Exception as e:
            print(f"[QUEUE ERROR] {e}", flush=True)

        await asyncio.sleep(1)

@asynccontextmanager
async def lifespan(app: FastAPI):
    task_queue = asyncio.create_task(queue_watcher_loop())
    task_rpg = asyncio.create_task(rpg_game_master_loop())
    yield
    task_queue.cancel()
    task_rpg.cancel()

# Application FastAPI
app = FastAPI(title="Nozor AI Console & RPG Game Master", lifespan=lifespan)

app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

@app.get("/")
async def root():
    return FileResponse(os.path.join(WEB_DIR, "index.html"))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:
        manager.disconnect(websocket)

@app.get("/api/history")
async def get_history():
    return JSONResponse(events_history[-100:])

@app.get("/api/status")
async def get_status():
    queue_len = 0
    if os.path.exists(QUEUE_FILE):
        try:
            with open(QUEUE_FILE, 'r', encoding='utf-8-sig') as f:
                d = json.load(f)
                queue_len = len(d.get("requests", []))
        except Exception:
            pass

    online_players = await asyncio.to_thread(get_online_players)

    return JSONResponse({
        "model": config.get("current_model", "openrouter/free"),
        "models_available": config.get("models", DEFAULT_CONFIG["models"]),
        "auto_switch": config.get("auto_switch", True),
        "requests_count": stats["requests_count"],
        "actions_count": stats["actions_count"],
        "rpg_events_count": stats["rpg_events_count"],
        "queue_length": queue_len,
        "online_players": online_players,
        "rpg_enabled": config.get("rpg_enabled", True),
        "rpg_interval": config.get("rpg_interval_minutes", 15),
        "last_active": stats["last_active"]
    })

@app.get("/api/config")
async def get_config():
    raw_key = config.get("api_key", "")
    masked_key = f"{raw_key[:12]}...{raw_key[-4:]}" if len(raw_key) > 16 else raw_key
    return JSONResponse({
        "api_key_masked": masked_key,
        "current_model": config.get("current_model", "openrouter/free"),
        "models": config.get("models", DEFAULT_CONFIG["models"]),
        "auto_switch": config.get("auto_switch", True),
        "rpg_enabled": config.get("rpg_enabled", True),
        "rpg_interval_minutes": config.get("rpg_interval_minutes", 15)
    })

class UpdateConfigPayload(BaseModel):
    api_key: str = None
    models: List[str] = None
    current_model: str = None
    auto_switch: bool = None
    rpg_enabled: bool = None
    rpg_interval_minutes: int = None

@app.post("/api/config")
async def update_config(payload: UpdateConfigPayload):
    global client
    changed = False

    if payload.api_key and payload.api_key.strip() and not payload.api_key.endswith("..."):
        config["api_key"] = payload.api_key.strip()
        client = create_client()
        changed = True

    if payload.models is not None and len(payload.models) > 0:
        config["models"] = payload.models
        changed = True

    if payload.current_model and payload.current_model.strip():
        config["current_model"] = payload.current_model.strip()
        changed = True

    if payload.auto_switch is not None:
        config["auto_switch"] = payload.auto_switch
        changed = True

    if payload.rpg_enabled is not None:
        config["rpg_enabled"] = payload.rpg_enabled
        changed = True

    if payload.rpg_interval_minutes is not None:
        config["rpg_interval_minutes"] = max(payload.rpg_interval_minutes, 1)
        changed = True

    if changed:
        save_config()
        await manager.broadcast({
            "type": "model_update",
            "model": config.get("current_model")
        })

    return JSONResponse({"status": "ok", "message": "Configuration mise à jour"})

class TriggerRPGPayload(BaseModel):
    event_type: str = "meteorite"
    target_player: str = None

@app.post("/api/rpg/trigger")
async def trigger_rpg_api(payload: TriggerRPGPayload):
    res = await execute_rpg_event(payload.event_type, payload.target_player)
    return JSONResponse({"status": "ok", "event": res})

@app.get("/api/rpg/catalog")
async def get_rpg_catalog():
    catalog = []
    for k, v in RPG_EVENTS.items():
        catalog.append({
            "id": k,
            "name": v["name"],
            "icon": v["icon"],
            "lore": v["lore"]
        })
    catalog.append({
        "id": "ai_random",
        "name": "Événement Aléatoire IA (Surprise)",
        "icon": "🎲",
        "lore": "Nozor invente un scénario et des commandes Minecraft totalement inédits en temps réel."
    })
    return JSONResponse(catalog)

class SendRequest(BaseModel):
    player: str = "Vibrions"
    instruction: str

@app.post("/api/send")
async def send_instruction(req: SendRequest):
    asyncio.create_task(process_agent_request(
        instruction=req.instruction,
        player=req.player
    ))
    return JSONResponse({"status": "ok", "message": "Instruction reçue"})

if __name__ == "__main__":
    print(f"=======================================================", flush=True)
    print(f"  NOZOR AI SERVER & RPG GAME MASTER", flush=True)
    print(f"  Interface Web : http://localhost:{PORT}", flush=True)
    print(f"  Modèle actif  : {config.get('current_model')}", flush=True)
    print(f"  Events RPG    : {'Actif (toutes les ' + str(config.get('rpg_interval_minutes')) + ' min)' if config.get('rpg_enabled') else 'Désactivé'}", flush=True)
    print(f"=======================================================", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
