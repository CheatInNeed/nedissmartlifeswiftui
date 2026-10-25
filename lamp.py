#!/usr/bin/env python3
"""CLI for controlling a Nedis SmartLife (Tuya) ceiling lamp locally via TinyTuya.

All output is JSON. On failure {"error": "..."} is printed to stdout and the exit code is non-zero.

Commands:
    lamp.py status                on/off, mode, brightness %, colourtemp %, rgb
    lamp.py on
    lamp.py off
    lamp.py brightness <0-100>
    lamp.py temp <0-100>          0 = warm, 100 = cold
    lamp.py color <hex>           e.g. #FF8800

Device ID, IP, local key and protocol version are read from a config file outside
the repo (default ~/.config/lamp/config.json, override with $LAMP_CONFIG).
"""

import colorsys
import json
import os
import sys

try:
    import tinytuya
except ImportError:
    print(json.dumps({"error": "tinytuya is not installed in the Python environment running lamp.py"}))
    sys.exit(2)


# Data point numbers (Tuya "v2" bulb schema, verified against the lamp)
DP_SWITCH = "20"      # bool
DP_MODE = "21"        # "white" | "colour" | "scene" | "music"
DP_BRIGHT = "22"      # 10-1000
DP_TEMP = "23"        # 0-1000 (0 = warm, 1000 = cold)
DP_COLOUR = "24"      # HSV-hex: HHHH SSSS VVVV (H 0-360, S/V 0-1000)

BRIGHT_MIN = 10
BRIGHT_MAX = 1000
TEMP_MAX = 1000


def fail(msg, code=1):
    print(json.dumps({"error": msg}))
    sys.exit(code)


def config_path():
    return os.environ.get(
        "LAMP_CONFIG", os.path.expanduser("~/.config/lamp/config.json")
    )


def load_config():
    path = config_path()
    try:
        with open(path) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        fail(f"config file not found: {path}")
    except (OSError, ValueError) as e:
        fail(f"could not read config ({path}): {e}")
    for key in ("device_id", "ip", "local_key", "version"):
        if not cfg.get(key):
            fail(f"config is missing the field '{key}' in {path}")
    return cfg


def connect(cfg):
    d = tinytuya.BulbDevice(cfg["device_id"], cfg["ip"], cfg["local_key"])
    try:
        d.set_version(float(cfg["version"]))
    except (TypeError, ValueError):
        fail(f"ugyldig protokolversion i config: {cfg['version']!r}")
    d.set_socketTimeout(5)
    d.set_socketPersistent(False)
    return d


def read_dps(d):
    """Fetch status and return the dps dict, or fail cleanly."""
    data = d.status()
    if not isinstance(data, dict) or "dps" not in data:
        err = data.get("Error") if isinstance(data, dict) else None
        if err:
            fail(f"the lamp did not respond correctly: {err} "
                 "(check IP, local key and that the lamp is online)")
        fail("the lamp did not respond (timeout or offline)")
    return data["dps"]


def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def parse_percent(arg, name):
    try:
        pct = int(round(float(arg)))
    except (TypeError, ValueError):
        fail(f"{name} must be a number between 0 and 100, got {arg!r}")
    return clamp(pct, 0, 100)


def bright_raw_to_pct(raw):
    try:
        raw = int(raw)
    except (TypeError, ValueError):
        return None
    pct = round((raw - BRIGHT_MIN) / (BRIGHT_MAX - BRIGHT_MIN) * 100)
    return clamp(pct, 0, 100)


def bright_pct_to_raw(pct):
    return int(round(pct / 100 * (BRIGHT_MAX - BRIGHT_MIN) + BRIGHT_MIN))


def temp_raw_to_pct(raw):
    try:
        raw = int(raw)
    except (TypeError, ValueError):
        return None
    return clamp(round(raw / TEMP_MAX * 100), 0, 100)


def temp_pct_to_raw(pct):
    return int(round(pct / 100 * TEMP_MAX))


def colour_hex_to_rgb(hexstr):
    """Tuya v2 HSV hex (12 chars) -> [r, g, b] 0-255."""
    if not hexstr or len(hexstr) < 12:
        return None
    try:
        h = int(hexstr[0:4], 16)
        s = int(hexstr[4:8], 16)
        v = int(hexstr[8:12], 16)
    except ValueError:
        return None
    r, g, b = colorsys.hsv_to_rgb(h / 360.0, s / 1000.0, v / 1000.0)
    return [round(r * 255), round(g * 255), round(b * 255)]


def rgb_to_colour_hex(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return "%04x%04x%04x" % (
        round(h * 360),
        round(s * 1000),
        round(v * 1000),
    )


def parse_hex_colour(arg):
    s = arg.lstrip("#").strip()
    if len(s) != 6:
        fail(f"colour must be a hex value like #FF8800, got {arg!r}")
    try:
        r = int(s[0:2], 16)
        g = int(s[2:4], 16)
        b = int(s[4:6], 16)
    except ValueError:
        fail(f"invalid hex colour: {arg!r}")
    return r, g, b


def cmd_status(d):
    dps = read_dps(d)
    on = bool(dps.get(DP_SWITCH, False))
    mode = dps.get(DP_MODE)
    out = {
        "on": on,
        "mode": mode,
        "brightness": bright_raw_to_pct(dps.get(DP_BRIGHT)),
        "colourtemp": temp_raw_to_pct(dps.get(DP_TEMP)),
        "rgb": colour_hex_to_rgb(dps.get(DP_COLOUR)),
    }
    print(json.dumps(out))


def check_set(result):
    if isinstance(result, dict) and result.get("Error"):
        fail(f"kommandoen fejlede: {result.get('Error')}")


def cmd_on(d):
    check_set(d.set_value(DP_SWITCH, True))
    print(json.dumps({"on": True}))


def cmd_off(d):
    check_set(d.set_value(DP_SWITCH, False))
    print(json.dumps({"on": False}))


def cmd_brightness(d, arg):
    pct = parse_percent(arg, "brightness")
    raw = bright_pct_to_raw(pct)
    # The brightness DP applies to white mode; switch to white so the change is visible.
    check_set(d.set_multiple_values({DP_MODE: "white", DP_BRIGHT: raw}))
    print(json.dumps({"brightness": pct}))


def cmd_temp(d, arg):
    pct = parse_percent(arg, "temp")
    raw = temp_pct_to_raw(pct)
    check_set(d.set_multiple_values({DP_MODE: "white", DP_TEMP: raw}))
    print(json.dumps({"colourtemp": pct}))


def cmd_color(d, arg):
    r, g, b = parse_hex_colour(arg)
    hexstr = rgb_to_colour_hex(r, g, b)
    check_set(d.set_multiple_values({DP_MODE: "colour", DP_COLOUR: hexstr}))
    print(json.dumps({"rgb": [r, g, b]}))


def main(argv):
    if not argv:
        fail("missing command (status|on|off|brightness|temp|color)", 2)
    cmd = argv[0]
    cfg = load_config()
    d = connect(cfg)
    try:
        if cmd == "status":
            cmd_status(d)
        elif cmd == "on":
            cmd_on(d)
        elif cmd == "off":
            cmd_off(d)
        elif cmd == "brightness":
            if len(argv) < 2:
                fail("brightness needs a value 0-100", 2)
            cmd_brightness(d, argv[1])
        elif cmd == "temp":
            if len(argv) < 2:
                fail("temp needs a value 0-100", 2)
            cmd_temp(d, argv[1])
        elif cmd == "color":
            if len(argv) < 2:
                fail("color needs a hex value, e.g. #FF8800", 2)
            cmd_color(d, argv[1])
        else:
            fail(f"unknown command: {cmd}", 2)
    except SystemExit:
        raise
    except Exception as e:  # network errors etc. -> clean JSON
        fail(f"unexpected error talking to the lamp: {e}")


if __name__ == "__main__":
    main(sys.argv[1:])
