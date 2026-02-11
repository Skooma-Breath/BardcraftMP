# Bardcraft (TES3MP) — Quick Install (server + players)

Downloads / credit

- Original mod (credit): https://www.nexusmods.com/morrowind/mods/56814?tab=files
- TES3MP release (port): https://github.com/Skooma-Breath/Bardcraft-Mp/releases

Server operator steps (what you must do)

1. Download the TES3MP release archive from the GitHub releases link above.
2. In that release, find the `Bardcraft` folder under the release's data files/midi directory (the folder containing MIDI files).
3. Copy that `Bardcraft` folder into your TES3MP server data tree:
   - Paste so it becomes: `server/data/custom/bardcraft/`
   - Typical subfolders: `server/data/custom/bardcraft/custom/` and `.../preset/`
4. Copy the script folder into your server scripts:
   - `server/scripts/custom/bardcraft/` (ensure `init.lua` is present)
5. Register the server script in `server/scripts/customScripts.lua`:
   - Add the line: `Bardcraft = require("custom.bardcraft.init")`
6. Restart the TES3MP server and check logs for “[Bardcraft] Initialized successfully”.

Notes for players (client installation)

- Every player who joins must install the Bardcraft mod client-side (the original mod assets). Download the release (link above) and install using one of your usual mod-install methods. One manual method is described below.

Install a mod manually

- OpenMW uses `openmw.cfg` to list data paths and plugins. Edit that file to add the data path and any plugin names for the mod.
- openmw.cfg locations:
  - Windows: `Documents\My Games\OpenMW\openmw.cfg`
  - Linux: `$XDG_CONFIG_HOME/openmw` or `$HOME/.config/openmw`
  - macOS: `$HOME/Library/Preferences/openmw`
- In `openmw.cfg`:
  - Add a `data=` line giving the full folder path where you extracted the mod files.
- Save `openmw.cfg` and launch OpenMW.

Quick troubleshooting

- No songs loaded on server: confirm `server/data/custom/bardcraft/custom/` (and/or `preset/`) exist and contain MIDI files.
- Server log issues: search server log for `[Bardcraft]` entries to find initialization messages and errors.

