import html
import json
import select
import socket
import subprocess
import sys
import time

HANDSHAKE = bytes.fromhex("00000400010002000000000000000000")
NOTIFICATIONS = bytes.fromhex("040004000f00ffffffff")
BATTERY_HEADER = bytes.fromhex("040004000400")


def get_devices():
    result = subprocess.run(
        [
            "busctl", "--system", "--json=short", "call", "org.bluez", "/",
            "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    objects = json.loads(result.stdout)["data"][0]
    devices = {}
    for interfaces in objects.values():
        properties = interfaces.get("org.bluez.Device1", {})
        if not properties.get("Connected", {}).get("data", False):
            continue
        address = properties["Address"]["data"]
        battery = interfaces.get("org.bluez.Battery1", {})
        devices[address] = {
            "name": properties.get("Alias", properties["Address"])["data"],
            "percentage": battery.get("Percentage", {}).get("data"),
            "is_airpods_max": "v004cp201f" in (
                properties.get("Modalias", {}).get("data", "").lower()
            ),
        }
    return devices


def connect_airpods(address):
    connection = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
    try:
        connection.settimeout(5)
        connection.connect((address, 0x1001))
        connection.sendall(HANDSHAKE)
        time.sleep(0.2)
        connection.sendall(NOTIFICATIONS)
        connection.setblocking(False)
        return connection
    except OSError:
        connection.close()
        raise


def parse_airpods_battery(packet):
    if not packet.startswith(BATTERY_HEADER) or len(packet) < 7:
        return None
    count = packet[6]
    if len(packet) < 7 + count * 5:
        return None
    for index in range(count):
        offset = 7 + index * 5
        component, start, percentage, status, end = packet[offset:offset + 5]
        if (
            component == 1
            and start == 1
            and end == 1
            and percentage <= 100
            and status in (1, 2)
        ):
            return {"percentage": percentage, "is_charging": status == 1}
    return None


def format_output(devices, airpods_batteries):
    percentages = []
    lines = []
    for address, device in sorted(devices.items(), key=lambda item: item[1]["name"].casefold()):
        battery = airpods_batteries.get(address, {})
        percentage = device["percentage"]
        if percentage is None:
            percentage = battery.get("percentage")
        name = html.escape(device["name"])
        if percentage is None:
            lines.append(f"{name}: battery unavailable")
            continue
        percentages.append(percentage)
        charging = " · Charging" if battery.get("is_charging") else ""
        lines.append(f"{name}: {percentage}%{charging}")
    if not percentages:
        return {"text": ""}
    lowest = min(percentages)
    return {
        "text": f"{lowest}%",
        "tooltip": "\n".join(lines),
        "percentage": lowest,
    }


def main():
    devices = {}
    connections = {}
    airpods_batteries = {}
    next_refresh = 0
    previous_output = None

    while True:
        if time.monotonic() >= next_refresh:
            try:
                devices = get_devices()
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                print(f"Bluetooth battery: {error}", file=sys.stderr)
                devices = {}

            for address in list(connections):
                if address not in devices:
                    connections.pop(address).close()
                    airpods_batteries.pop(address, None)

            for address, device in devices.items():
                if (
                    device["is_airpods_max"]
                    and device["percentage"] is None
                    and address not in connections
                ):
                    try:
                        connections[address] = connect_airpods(address)
                    except OSError as error:
                        print(f"AirPods battery: {error}", file=sys.stderr)
            next_refresh = time.monotonic() + 10

        output = format_output(devices, airpods_batteries)
        if output != previous_output:
            print(json.dumps(output), flush=True)
            previous_output = output

        timeout = max(0, next_refresh - time.monotonic())
        ready, _, _ = select.select(list(connections.values()), [], [], timeout)
        for address, connection in list(connections.items()):
            if connection not in ready:
                continue
            try:
                packet = connection.recv(1024)
            except BlockingIOError:
                continue
            except OSError:
                packet = b""
            if not packet:
                connections.pop(address).close()
                airpods_batteries.pop(address, None)
                continue
            battery = parse_airpods_battery(packet)
            if battery is not None:
                airpods_batteries[address] = battery


if __name__ == "__main__":
    main()
