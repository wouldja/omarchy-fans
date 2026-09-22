#!/usr/bin/env python3
"""Fan modes for the P870DM-G, through the sager_kbd sysfs device."""

import json
import os
import sys

SYSFS = "/sys/devices/platform/sager_kbd"
STATE_PATH = os.path.expanduser("~/.config/sager-fans/state.json")
MODES = ("auto", "quiet", "performance", "curve", "manual")
POINTS = (45, 60, 72, 82, 92)
DEFAULT_DUTIES = [25, 45, 65, 85, 100]


def clamp(value, low, high):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return low
    return max(low, min(high, number))


def duties_of(value):
    duties = list(DEFAULT_DUTIES)
    if isinstance(value, (list, tuple)):
        for index in range(len(POINTS)):
            if index < len(value):
                duties[index] = clamp(value[index], 0, 100)
    return duties


def normalize(raw):
    state = {
        "mode": "auto",
        "manual": 40,
        "duties": list(DEFAULT_DUTIES),
    }
    if not isinstance(raw, dict):
        return state
    mode = raw.get("mode", "auto")
    state["mode"] = mode if mode in MODES else "auto"
    state["manual"] = clamp(raw.get("manual", 40), 25, 100)
    state["duties"] = duties_of(raw.get("duties"))
    return state


def load_saved():
    try:
        with open(STATE_PATH, encoding="utf-8") as handle:
            return normalize(json.load(handle))
    except (OSError, json.JSONDecodeError):
        return normalize(None)


def save(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    temporary = STATE_PATH + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2)
        handle.write("\n")
    os.replace(temporary, STATE_PATH)


def driver_ready():
    return os.access(os.path.join(SYSFS, "fan_mode"), os.W_OK)


def write_text(name, text):
    with open(os.path.join(SYSFS, name), "w", encoding="utf-8") as handle:
        handle.write(text)


def read_int(name):
    try:
        with open(os.path.join(SYSFS, name), encoding="utf-8") as handle:
            return int(handle.read().strip() or "0")
    except (OSError, ValueError):
        return 0


def read_state():
    data = {}
    try:
        with open(os.path.join(SYSFS, "fan_state"), encoding="utf-8") as handle:
            for line in handle:
                if "=" not in line:
                    continue
                key, value = line.strip().split("=", 1)
                data[key] = value
    except OSError:
        return data
    return data


def state_int(data, key):
    try:
        return int(str(data.get(key, "0")).split()[0])
    except ValueError:
        return 0


def sensors():
    data = read_state()
    return {
        "cpuTemp": state_int(data, "cpu_temp"),
        "gpuTemp": state_int(data, "gpu_temp"),
        "cpuRpm": state_int(data, "cpu_rpm"),
        "gpuRpm": state_int(data, "gpu_rpm"),
        "hwDuty": state_int(data, "hw_duty"),
        "duty": state_int(data, "duty"),
    }


def read_text(name):
    try:
        with open(os.path.join(SYSFS, name), encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def curve_line(duties):
    return " ".join(f"{temp}:{duty}" for temp, duty in zip(POINTS, duties))


def push(state):
    if not driver_ready():
        return False
    try:
        write_text("fan_curve", curve_line(state["duties"]) + "\n")
        write_text("fan_duty", f"{state['manual']}\n")
        write_text("fan_mode", state["mode"] + "\n")
    except OSError:
        return False
    return True


def emit(state, applied=None):
    payload = dict(state)
    payload.update(sensors())
    payload["available"] = driver_ready()
    if applied is not None:
        payload["applied"] = applied
    sys.stdout.write(json.dumps(payload) + "\n")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "get"
    if command == "sensors":
        emit(load_saved())
        return 0
    if command == "get":
        emit(load_saved())
        return 0
    if command == "restore":
        state = load_saved()
        save(state)
        applied = push(state)
        emit(state, applied)
        return 0 if applied or not driver_ready() else 1
    if command == "set":
        try:
            raw = json.loads(sys.argv[2] if len(sys.argv) > 2 else "{}")
        except json.JSONDecodeError:
            sys.stderr.write("set expects a JSON object\n")
            return 2
        state = normalize(raw)
        save(state)
        applied = push(state)
        emit(state, applied)
        return 0 if applied or not driver_ready() else 1
    sys.stderr.write("usage: apply.py get|sensors|restore|set [json]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
