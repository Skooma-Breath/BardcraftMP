# TES3MP Bardcraft Port

What this is

- Original mod (credit): https://www.nexusmods.com/morrowind/mods/56814?tab=files
- Server-side TES3MP port of Bardcraft.
- How it works:
     Basically the server scripts parse the midi files and send lots of playsound console commands to the players...

Demo: https://youtu.be/YbxQ0bVf5jA

- Want to try Bardcraft online without setting up a server? You can join my public test server.
- Join my discord server [Fetcher Simulator](https://discord.gg/TSqQTVexe5) for instructions.

TODO's:

- npc band members.
- create a few missing icons and more instruments.

Downloads

- TES3MP release (port): https://github.com/Skooma-Breath/BardcraftMP/releases/download/BardcraftMP/BardcraftMP.zip

Server install

1. Click the big green "Code" button near the top right of the github page and select "Download ZIP". Extract the contents.
2. Copy the server folder into your tes3mp install folder.
3. Add this line to `server/scripts/customScripts.lua`:
   - `require("custom.bardcraft.init")`
4. Chuck any custom midi files into `server/data/custom/bardcraft/custom`
5. Restart the server if it was running.

Player (client) install

- Each player must install the Bardcraft mod assets. Download the release above and install via your preferred method.
- Manual install summary:
  - Edit `openmw.cfg` and add a `data=` line pointing to where you extracted the mod files.
  - for example, if you extracted the mod files to `C:\openmwMods`, add `data=C:\openmwMods\BardcraftMP\Data Files` to `openmw.cfg`.
  - openmw.cfg locations:
    - Windows: `Documents\My Games\OpenMW\openmw.cfg`
    - Linux: `$XDG_CONFIG_HOME/openmw` or `$HOME/.config/openmw`
    - macOS: `$HOME/Library/Preferences/openmw`

Quick usage

- `/bc` — open song browser
- `/stop` — stop performing
- `/play <song> [instrument]` — start performing
- `/band`, `/bandplay <song>`, `/bandstop` — band commands

You will need to be an admin on the server currently to spawn in some instruments and access the reload midi files button in the /bc menu.
To make yourself admin find and edit the `staffrank` value in your `server/data/player/playername.json` file to `2`.
command to spawn in an instrument: `/placeat pid bcw_lute`
Instruments:

- bcw_lute
- bcw_bassflute
- bcw_ocarina
- bcw_drum
- bcw_fiddle_bow
- bca_fiddle_shield

The weapon version of the instruments will automatically be swapped with the armor versions for use with the play animations.
There is a toggle in the admin /bc menu for not requiring the weapon versions to start playing.

Troubleshooting

- No songs loaded: ensure players installed the client mod properly and server was restarted.
- Check server logs for `[Bardcraft]` messages to diagnose issues.
