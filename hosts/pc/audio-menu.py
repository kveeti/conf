import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path


STATE_FILE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "audio-menu/history.json"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=35)


def bluetooth_devices():
    devices = []
    for line in run("bluetoothctl", "devices", "Paired").splitlines():
        _, address, name = line.split(" ", 2)
        info = run("bluetoothctl", "info", address)
        if "0000110b-" not in info:
            continue
        devices.append({
            "key": "bluetooth:" + address,
            "name": name,
            "kind": "Bluetooth",
            "address": address,
            "is_connected": "Connected: yes" in info,
            "node": None,
        })
    return devices


def device_name(props, hardware):
    device = hardware.get(props.get("device.id"), {})
    profile_device = props.get("card.profile.device")
    for route in device.get("params", {}).get("Route", []):
        if profile_device is None or route.get("device") != profile_device:
            continue
        description = route.get("description")
        if not description:
            continue
        info = route.get("info", [])
        port = dict(zip(info[1::2], info[2::2]))
        product = port.get("device.product.name")
        device_props = device.get("props", {})
        if not product and device_props.get("device.bus") == "usb":
            product = device_props.get("device.product.name")
        return f"{description} — {product}" if product else description

    return props.get("node.description") or props["node.name"]


def audio_devices(direction):
    objects = json.loads(run("pw-dump"))
    hardware = {
        item["id"]: item.get("info", {})
        for item in objects
        if item.get("type") == "PipeWire:Interface:Device"
    }
    current = ""
    for item in objects:
        for entry in item.get("metadata", []):
            if entry.get("key") == "default.audio." + direction:
                current = entry.get("value", {}).get("name", "")

    devices = bluetooth_devices() if direction == "sink" else []
    for item in objects:
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        props = item.get("info", {}).get("props", {})
        if props.get("media.class") != ("Audio/Sink" if direction == "sink" else "Audio/Source"):
            continue
        node = props["node.name"]
        address = re.search(r"bluez_output\.([0-9A-Fa-f_]{17})", node)
        device = next((d for d in devices if address and d["address"] == address[1].replace("_", ":").upper()), None)
        if device is None:
            is_airplay = node.startswith("raop_sink.")
            key = node.split(".local")[0] if is_airplay else node
            device = {
                "key": key,
                "name": device_name(props, hardware),
                "kind": "AirPlay" if is_airplay else "Audio",
                "is_connected": True,
            }
            devices.append(device)
        device["node"] = item["id"]
        device["is_current"] = node == current
    return devices


def select_device(device, direction):
    if device.get("address") and device.get("node") is None:
        run("bluetoothctl", "power", "on")
        run("bluetoothctl", "connect", device["address"])
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            candidate = next((d for d in audio_devices(direction) if d["key"] == device["key"]), None)
            if candidate and candidate.get("node") is not None:
                device = candidate
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Bluetooth connected, but its audio output did not appear. Try reconnecting the headphones.")
    if direction == "sink":
        run("wpctl", "set-volume", str(device["node"]), "20%")
    run("wpctl", "set-default", str(device["node"]))


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return default


def remember(device):
    history = read_json(STATE_FILE, {})
    history[device["key"]] = time.time()
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(history))


def connect_worker():
    result_path = Path(sys.argv[2])
    direction = sys.argv[3]
    device = json.loads(sys.argv[4])
    try:
        select_device(device, direction)
        remember(device)
    except (subprocess.SubprocessError, RuntimeError):
        pass
    result = {"is_connecting": False}
    try:
        temporary = result_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(result))
        temporary.replace(result_path)
    except FileNotFoundError:
        pass


def header(key, value):
    print(f"\0{key}\x1f{value}")


def show_menu():
    icons = dict(zip(["Audio", "AirPlay", "Bluetooth"], sys.argv[2:5]))
    result_path = Path(sys.argv[6])
    state = json.loads(os.environ.get("ROFI_DATA") or '{"direction": "sink"}')
    direction = state["direction"]
    action = os.environ.get("ROFI_INFO", "")
    if action == "close":
        return

    connection = read_json(result_path, {})
    is_connecting = connection.get("is_connecting", False)
    if connection and not is_connecting:
        result_path.unlink(missing_ok=True)
    did_change_direction = action == "direction"
    if did_change_direction:
        direction = "source" if direction == "sink" else "sink"
        state = {"direction": direction}
    elif action and action != "refresh":
        state["focus"] = action

    devices = []
    try:
        devices = audio_devices(direction)
        device = next((d for d in devices if d["key"] == action), None)
        if device is not None and not is_connecting:
            if device.get("address") and device.get("node") is None:
                result_path.write_text(json.dumps({"is_connecting": True}))
                subprocess.Popen(
                    [sys.executable, __file__, "--connect", str(result_path), direction, json.dumps(device)],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                is_connecting = True
            else:
                select_device(device, direction)
                remember(device)
                devices = audio_devices(direction)
    except (subprocess.SubprocessError, RuntimeError):
        pass

    history = read_json(STATE_FILE, {})
    devices.sort(key=lambda d: (
        not d.get("is_current", False),
        not d["is_connected"],
        -history.get(d["key"], 0),
        d["name"].casefold(),
    ))
    header("prompt", "Audio output" if direction == "sink" else "Audio input")
    header("no-custom", "true")
    header("keep-selection", "true")
    header("keep-filter", "false" if did_change_direction else "true")
    header("data", json.dumps(state))
    focus_index = next((i for i, d in enumerate(devices) if d["key"] == state.get("focus")), None)
    if focus_index is not None:
        header("new-selection", focus_index)
    for device in devices:
        icon = sys.argv[1] if device.get("is_current") else icons[device["kind"]]
        row = device["name"] + "\0icon\x1f" + icon + "\x1finfo\x1f" + device["key"]
        if is_connecting:
            row += "\x1fnonselectable\x1ftrue"
        print(row)
    switch = "Switch to inputs" if direction == "sink" else "Switch to outputs"
    for label, action in [(switch, "direction"), ("Refresh", "refresh"), ("Close", "close")]:
        print(label + "\0info\x1f" + action + "\x1fpermanent\x1ftrue")


def main():
    if sys.argv[1] == "--connect":
        connect_worker()
    elif len(sys.argv) > 5 and sys.argv[5] == "--mode":
        show_menu()
    else:
        with tempfile.TemporaryDirectory(prefix="audio-menu-") as directory:
            command = shlex.join([
                sys.executable, __file__, *sys.argv[1:5], "--mode", str(Path(directory) / "connection.json"),
            ])
            subprocess.run([
                "rofi", "-show", "audio", "-modes", "audio:" + command,
                "-no-case-sensitive", "-show-icons", "-no-sort",
                "-theme-str", 'entry { placeholder: "Search devices…"; }',
            ], check=True)


if __name__ == "__main__":
    main()
