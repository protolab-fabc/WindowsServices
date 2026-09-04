import os
import sys
import time
import shutil
import socket
import struct
import subprocess

sys.path.insert(0, os.path.dirname(__file__))
from nozor_agent import rcon_exec

SERVER_DIR = r"C:\WindowsServices"
OW_DIR = os.path.join(SERVER_DIR, r"world\dimensions\minecraft\overworld")
PROPS_FILE = os.path.join(SERVER_DIR, "server.properties")
SEED = -4029535714769340309

def is_rcon_alive() -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(("127.0.0.1", 25575))
        s.close()
        return True
    except Exception:
        return False

def is_java_running() -> bool:
    try:
        out = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", "Get-Process -Name java -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
            text=True
        ).strip()
        return bool(out)
    except Exception:
        return False

def main():
    print("=== DEBUT DU RESET DU MONDE SURVIE (OVERWORLD) ===")

    # 1. Sauvegarde et mise en sécurité des joueurs
    if is_rcon_alive():
        print("1. Mise en sécurité des joueurs et sauvegarde...")
        rcon_exec('tellraw @a {"text":"[SERVEUR] Réinitialisation du monde Survie en cours... Téléportation au Hub.","color":"gold","bold":true}')
        # Téléporter tous les joueurs au Hub
        rcon_exec('execute in hub:lobby run tp @a 193.5 64 -200 0 0')
        time.sleep(1)
        rcon_exec('save-all flush')
        time.sleep(2)
        print("-> Sauvegarde effectuée.")

        # Arrêt propre du serveur
        print("2. Arrêt propre du serveur Minecraft...")
        rcon_exec('stop')
    else:
        print("RCON indisponible, vérification du processus Java...")

    # Attente de l'arrêt complet de Java
    wait_time = 0
    while is_java_running() and wait_time < 45:
        print(f"Attente de l'arrêt de java.exe ({wait_time}s)...")
        time.sleep(2)
        wait_time += 2

    if is_java_running():
        print("Force-kill de Java restant...")
        subprocess.run(["powershell", "-NoProfile", "-Command", "Stop-Process -Name java -Force -ErrorAction SilentlyContinue"])
        time.sleep(2)

    print("-> Serveur arrêté.")

    # 3. Purge des dossiers de l'Overworld uniquement
    print(f"3. Purge de l'Overworld ({OW_DIR})...")
    for folder in ["region", "entities", "poi"]:
        p = os.path.join(OW_DIR, folder)
        if os.path.exists(p):
            try:
                shutil.rmtree(p)
                print(f"  - Supprimé: {folder}")
            except Exception as e:
                print(f"  - Erreur suppression {folder}: {e}")
        else:
            print(f"  - Dossier {folder} absent, rien à faire.")

    # Vérification du seed dans server.properties
    if os.path.exists(PROPS_FILE):
        with open(PROPS_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()
        with open(PROPS_FILE, "w", encoding="utf-8") as f:
            for l in lines:
                if l.startswith("level-seed="):
                    f.write(f"level-seed={SEED}\n")
                else:
                    f.write(l)
        print(f"-> Seed {SEED} confirmé dans server.properties.")

    # 4. Redémarrage du serveur via WMI
    print("4. Redémarrage du serveur Minecraft via WMI...")
    start_cmd = (
        "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{"
        "CommandLine = 'wscript.exe C:\\WindowsServices\\scripts\\start.vbs';"
        "CurrentDirectory = 'C:\\WindowsServices'"
        "}"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", start_cmd], check=True)

    # 5. Attente de la réouverture de RCON
    print("5. Attente du démarrage de Minecraft et de l'écoute RCON...")
    rcon_ready = False
    for i in range(40):
        time.sleep(3)
        if is_rcon_alive():
            # Tester l'auth RCON
            test = rcon_exec("list")
            if "players" in test.lower() or "joueur" in test.lower() or ":" in test:
                rcon_ready = True
                print(f"-> Serveur Minecraft en ligne et RCON prêt ({i*3}s) !")
                break
        print(f"  ...en attente du serveur ({(i+1)*3}s)")

    if not rcon_ready:
        print("ERREUR: Le serveur n'a pas répondu sur RCON après 120s.")
        return False

    # 6. Attente de génération du chunk de spawn et reconstruction de la plateforme
    print("6. Reconstruction de la plateforme sanctuaire, du portail et des hologrammes...")
    time.sleep(5)

    from build_beautiful_platform import build
    build()

    # 7. Rafraîchissement propre de Nozor
    print("7. Rafraîchissement de Nozor...")
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", r"C:\WindowsServices\scripts\restart_nozor.ps1"], check=False)

    # Annonce aux joueurs
    rcon_exec('tellraw @a {"text":"[SERVEUR] Le monde Survie a été réinitialisé avec succès dans la Plaine de Tournesols ! Le portail est ouvert.","color":"green","bold":true}')
    print("=== RESET DU MONDE SURVIE TERMINE AVEC SUCCES ===")
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
