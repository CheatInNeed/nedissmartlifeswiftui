# LampBar

A tiny macOS menu bar app that controls a Tuya-based smart lamp (built for a Nedis SmartLife
ceiling lamp) **locally over your own network** – no cloud round trip when you use it.

- On/off, brightness, warm-to-cold white, colour picker, colour presets and a white button
- Sliders respond live while you drag
- Shows the current lamp state whenever the menu opens
- Menu bar icon switches between an empty and a filled light bulb
- "Start at login" checkbox, no Dock icon

```
LampBar.app (SwiftUI)  ──runs──▶  lamp.py (TinyTuya)  ──LAN, Tuya protocol 3.3/3.4/3.5──▶  lamp
```

The Tuya protocol is encrypted with a per-device **local key**, so the one-time setup is
getting that key. After that, everything works without the cloud.

> The app's own labels are in Danish ("Loftslampe", "Start ved login", "Afslut"). They are plain
> strings in the UI code in [`app/LampBar.swift`](app/LampBar.swift) if you want to change them.

## Requirements

- macOS 14 or newer (Apple Silicon or Intel)
- **Xcode** (the full app from the App Store, not just the Command Line Tools – only Xcode ships
  the SwiftUI macro plugin the build needs)
- Python 3 (`python3 --version`)
- A Tuya-based lamp on the same network as your Mac, paired in the Smart Life or Nedis SmartLife app
- A free account at <https://iot.tuya.com> (only needed once, to fetch the local key)

## Setup

### 1. Get the code and build

```bash
git clone https://github.com/CheatInNeed/nedissmartlifeswiftui.git
cd nedissmartlifeswiftui
bash app/build.sh
```

`build.sh` does three things: it creates a Python venv with TinyTuya in `~/.local/share/lamp/venv`,
copies `lamp.py` next to it, and builds `build/LampBar.app`. It also warns that your config file is
missing – that is step 3.

### 2. Find your lamp's credentials

You need four values: **device ID**, **local key**, **IP address** and **protocol version**.

**2a. Give the lamp a fixed IP.** In your router's DHCP settings, reserve an address for the
lamp's MAC address (shown in the app under device information). Otherwise the IP can change
and the app stops working.

**2b. Create a Tuya cloud project** (follow the official
[TinyTuya setup wizard guide](https://github.com/jasonacox/tinytuya#setup-wizard---getting-local-keys)
if the website has changed – labels move around):

1. Sign in at <https://iot.tuya.com> → *Cloud* → *Development* → *Create Cloud Project*.
2. Pick the **data center for your region** (e.g. *Central Europe*). It has to match the data
   center your app account lives in; if linking fails in the next step, try the neighbouring one
   (e.g. *Western Europe*).
3. Make sure the **IoT Core** and **Authorization Token Management** API services are added to the
   project. If the wizard later reports a permission error, also subscribe *Smart Home Basic Service*.
4. Open the project's *Overview* and note the **Access ID** and **Access Secret**.
5. In the project go to *Devices* → *Link App Account* → *Add App Account* and scan the QR code
   with the app (*Me* → scan icon). The QR code expires quickly – refresh it and scan right away.
   Your lamp should then appear under *All Devices*.

   Some OEM apps (such as Nedis SmartLife) cannot be linked. If scanning fails, install the
   **Smart Life** app, remove the lamp from the OEM app, pair it again in Smart Life, and link
   *that* account. Re-pairing creates a new local key, so do it *before* the next step.

**2c. Run the wizard.** Run it in a scratch folder, not in the repo – it writes files containing
your keys:

```bash
mkdir ~/lamp-setup && cd ~/lamp-setup
~/.local/share/lamp/venv/bin/python3 -m tinytuya wizard
```

It asks for the Access ID (*API Key*), the Access Secret, **any device ID** from your account
(in the app: open the lamp → settings → *Device information* → the virtual/device ID) and your
region code (`eu` = Central Europe, `eu-w` = Western Europe, `us`, `us-e`, `in`, `sg`, `cn`).
Answer *Y* when it offers to poll local devices. When it finishes, open `devices.json` and read
your lamp's `id`, `key`, and – if the poll found it – `ip` and `version`.

If `ip` or `version` are empty, scan the network:

```bash
~/.local/share/lamp/venv/bin/python3 -m tinytuya scan
```

Delete `~/lamp-setup` afterwards (it contains your keys) once you have the values.

### 3. Create the config file

The credentials live **outside the repo**, in `~/.config/lamp/config.json`:

```bash
mkdir -p ~/.config/lamp
cp config.example.json ~/.config/lamp/config.json
chmod 600 ~/.config/lamp/config.json
open -e ~/.config/lamp/config.json     # fill in device_id, ip, local_key, version
```

```json
{
  "device_id": "bf...",
  "ip": "192.168.1.50",
  "local_key": "................",
  "version": "3.5"
}
```

Never commit this file; `.gitignore` already excludes `config.json`, `devices.json`,
`tinytuya.json`, `snapshot.json` and `tuya-raw.json`.

### 4. Test the command line

```bash
~/.local/share/lamp/venv/bin/python3 lamp.py status
# {"on": false, "mode": "white", "brightness": 100, "colourtemp": 15, "rgb": [..]}
~/.local/share/lamp/venv/bin/python3 lamp.py on
```

Get this working before touching the app. Errors come back as `{"error": "..."}` with a non-zero
exit code – see [Troubleshooting](#troubleshooting).

**Check the data points.** `lamp.py` assumes the common Tuya "v2" bulb layout: `20` switch,
`21` mode, `22` brightness (10–1000), `23` colour temperature (0–1000), `24` colour (HSV hex).
Verify yours:

```bash
~/.local/share/lamp/venv/bin/python3 -c "
import tinytuya
d = tinytuya.BulbDevice('DEVICE_ID', 'IP', 'LOCAL_KEY'); d.set_version(3.5)
print(d.status())"
```

If the keys under `dps` are `20`–`24`, you are done. Older lamps use `1`–`5` with different value
ranges; for those, change the `DP_*` constants and range constants at the top of `lamp.py` to match.

### 5. Run the app

```bash
cp -R build/LampBar.app /Applications/
open /Applications/LampBar.app
```

A light bulb appears in the menu bar. Tick **Start ved login** in the menu to launch it at login
(macOS registers the app at its current location, so put it in `/Applications` first and don't
move it afterwards).

## Command line reference

```
lamp.py status             on/off, mode, brightness %, colourtemp %, rgb
lamp.py on | off
lamp.py brightness <0-100>
lamp.py temp <0-100>       0 = warm, 100 = cold (also switches to white mode)
lamp.py color <hex>        e.g. '#FF8800' (also switches to colour mode)
```

Set `LAMP_CONFIG=/path/to/config.json` to use a different config file.

## Updating

After pulling changes or editing `lamp.py` or `app/LampBar.swift`, run `bash app/build.sh` again
and re-copy the app to `/Applications` (quit the running one first: menu → *Afslut*).

## If the lamp is paired again – getting a new local key

The local key changes whenever the lamp is removed from the app and paired again (or factory
reset). The app then fails with `Check device key or version` (error 914). To fix it:

1. Pair the lamp in the app and make sure the account is still linked to your Tuya cloud project
   (*Devices* → *All Devices*; link the account again if needed).
2. Re-run the wizard from step 2c and copy the new `key` into `~/.config/lamp/config.json`.
   The device ID usually stays the same; the IP may change if you did not reserve it.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `Check device key or version` / error 914 | Wrong `local_key`, or wrong `version`. Re-check `devices.json`; try `3.4` / `3.3`. If the lamp was re-paired, fetch the key again (above). |
| `lampen svarede ikke (timeout eller offline)` | Wrong IP, lamp offline, or Mac and lamp are not on the same network/VLAN. Check `ping <ip>`. A guest network or "client isolation" blocks it. |
| Works in Terminal but not from the app | macOS may ask for **Local Network** access for the app – allow it (*System Settings → Privacy & Security → Local Network*). |
| Build says Xcode / SwiftUI macro errors | The full Xcode app is required, not only the Command Line Tools. If `/Applications/Xcode.app` is elsewhere, run `sudo xcode-select -s <path>/Contents/Developer`. |
| Wizard says *permission deny* / *no permissions* | The project is missing an API service (see 2b.3) or the data center does not match your account. |
| Menu shows an orange warning | It prints the error from `lamp.py`; run the same command in Terminal to see it in full. |

To remove everything: untick *Start ved login*, delete `LampBar.app`, and
`rm -rf ~/.local/share/lamp ~/.config/lamp`.

## Project layout

```
lamp.py              CLI on top of tinytuya.BulbDevice, JSON in/out
app/LampBar.swift    the whole menu bar app (single file)
app/build.sh         builds build/LampBar.app, installs lamp.py + venv
config.example.json  template for ~/.config/lamp/config.json
requirements.txt     Python dependency (tinytuya)
```
