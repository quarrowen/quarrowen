# Playing VoxelCraft at home

A family setup: the server runs in Docker on a home Linux machine, and everyone plays from their own Mac
(Apple silicon) on the same home network.

- [1. The server (Ubuntu + Docker)](#1-the-server-ubuntu--docker)
- [2. The Macs](#2-the-macs)
- [3. First game](#3-first-game)
- [4. Admin cheat sheet](#4-admin-cheat-sheet)
- [5. Backups and updates](#5-backups-and-updates)
- [6. When something goes wrong](#6-when-something-goes-wrong)

## 1. The server (Ubuntu + Docker)

You need Docker with the Compose plugin (`docker compose version` should work) and git.

**Get the code.** The repository is private, so sign in first. The GitHub CLI is the easiest:

```sh
sudo apt install gh        # or see https://cli.github.com
gh auth login
gh repo clone omnivoxel-game/voxelcraft
cd voxelcraft/deploy/homelab
```

**Choose names.** Copy the example settings and edit them:

```sh
cp .env.example .env
nano .env
```

- `ADMINS`: your in-game name. Admins can change game modes, teleport, approve skins and manage who may join.
- `ALLOWLIST`: everyone who may join, by the name they will type in the game (for example `Alex,Sam,Robin`).
  Nobody else can get in. You can add people later from inside the game.
- `CREATIONS=approval`: painted skins and hats wait for an admin to approve them before others see them.
- `CHAT_FILTER=on`: swear words in chat are masked.

**Start it** (the first build takes a few minutes; it compiles the server for this machine):

```sh
docker compose up -d --build
docker compose logs -f     # Ctrl+C stops watching, not the server
```

It is ready when the log says `running game`. The server starts again by itself after a reboot.

**Firewall.** If the machine uses `ufw`, open the two game ports (UDP):

```sh
sudo ufw allow 24565:24566/udp
```

Note the machine's address on your network (for example `192.168.1.20`): `hostname -I`.

**Mods live on the server, not inside the image.** The container holds the engine; the mods it loads sit in
`deploy/homelab/mods/` on this machine (created on the first start, filled with the mods the engine shipped
with). To add a game or an add-on, drop its folder there and restart:

```sh
cp -r ~/my_mod deploy/homelab/mods/         # a mod folder with a mod.json inside
nano .env                                   # add it to GAME=vanilla,my_mod
docker compose restart
```

`MODS_DIR` in `.env` moves that folder somewhere else. On each start the mods that came with the engine
(`base`, `vanilla`, the add-ons) are refreshed from the image so an update cannot leave stale content behind;
everything else there is left alone. Set `SEED_MODS=missing` to keep your own edits to the bundled mods, or
`SEED_MODS=never` to manage the whole folder yourself.

## 2. The Macs

**Build the app** once, on the Mac with this project (needs the Godot editor and Rust installed, as for
development):

```sh
tools/package_mac.sh
```

It makes `build/macos/VoxelCraft-<version>-mac-arm64.zip`. Send the zip to each Mac (AirDrop works well).

**Install on each Mac:**

1. Double-click the zip, then drag **VoxelCraft** into **Applications**.
2. The first time, macOS blocks apps that are not from the App Store or a registered developer. Open it anyway:
   right-click (or Control-click) **VoxelCraft** in Applications, choose **Open**, then **Open** again.
   On newer macOS versions, if there is no Open button: try to open it once, then go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   (Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/VoxelCraft.app`.)
3. After that it opens normally.

A MacBook Air runs the game well on the default graphics. If it feels slow, open **Settings → Graphics** and
choose **Fast**.

## 3. First game

1. **You first.** Open VoxelCraft, click the name under **Playing as** at the bottom left and type your admin name
   exactly as in `ADMINS`. The first player to use a name on a server keeps it, so join before sharing.
2. Go to **Multiplayer → LAN**. The server appears there (the name from `SERVER_NAME`). Double-click it.
   If it does not appear, type the server's address (like `192.168.1.20`) in the box at the top and press **Join**.
3. Check you are admin: press **T** and type `/whoami`.
4. **The kids.** On each Mac, set **Playing as** to the name you put in `ALLOWLIST`, then **Multiplayer → LAN** and join.
   Click **Add to favorites** so it is one click next time.

The game starts in creative mode (build freely, no monsters bother you). Each player can switch their own mode
with `/gamemode survival` (a small starter kit, hunger, monsters at night) or `/gamemode creative`. Press **G**
for the guide book and **Esc → Settings** for controls.

## 4. Admin cheat sheet

**Without typing anything:** press Esc → **Server settings…** (admins only). It has the rules as switches
(PvP, keep-inventory, monsters, hunger, fall damage...), the time of day, "everyone plays in
survival/creative", who may join, the cheat checks and a backup button. Everything below still works in chat.


Press **T**, type a command, press Enter. `/help` lists them all.

| Command | What it does |
|---|---|
| `/allow add Name` | let someone join (`/allow remove Name`, `/allow list`) |
| `/players` | who is online |
| `/kick Name` | disconnect someone |
| `/op Name` | make someone an admin (`/deop Name` to undo) |
| `/time day` | make it day (`/time night`, `/time noon`) |
| `/tp Name` | go to a player |
| `/fly` | fly (creative mode, or the "fly" permission). Double-tap jump does it too; jump rises, Shift sinks |
| `/sethome`, `/home` | remember a spot and come back to it (everyone can) |
| `/back` | go to where you last died (your grave holds your things) |
| `/lowgravity` | low gravity for everyone, for big jumps (again to turn it off) |
| `/gameplay mob_spawning false` | no monsters (`true` to bring them back) |
| `/gameplay chat_filter true` | turn the chat filter on or off |
| `/ugc list` | skins and hats waiting for approval; `/ugc approve <id>`, `/ugc trust Name` to skip approval for someone |
| `/backup` | save a backup now |
| `/role give Sam builder` | give someone a role (`/role list` shows them; `/role take` removes) |
| `/perms Sam` | what someone's roles let them do |

Admins also get **Esc → Review creations** to see and approve painted skins with previews, and **Esc → Players and
roles** to give roles (builder, moderator, admin) or kick someone, without typing commands.

## 5. Backups and updates

**Backups** are made every hour while people play (the last 48 are kept) inside the Docker volume. To copy the
whole world out to a folder:

```sh
docker run --rm -v homelab_voxelcraft-data:/data -v "$PWD":/out debian tar czf /out/voxelcraft-world.tgz -C /data .
```

(`docker volume ls` shows the exact volume name.) The volume also holds the server's identity: keep it, or
every Mac will warn that the server's identity changed.

**Worlds survive updates.** Builds, chests, animals and inventories are kept when you update; the server backs a
world up before it upgrades the save format. Always update with the *same* Compose project name you started with,
because the world lives in that project's volume: if you started with plain `docker compose up`, keep using that
from the same folder; if you used `-p voxelcraft`, keep using it. `docker volume ls` shows the volumes
(`homelab_voxelcraft-data` or `voxelcraft_voxelcraft-data`).

**The Macs update themselves.** When the menu opens, the game checks the download page and offers the new
version in a banner; pressing Update downloads it, checks it against the checksum published with the release
and swaps the app (Settings → Network turns the check off, Settings → Account has a "Check for updates"
button). Nothing is ever downloaded from a game server - a server can only say which version it needs.

**Updating.** Server and Macs must run the same version. On the server:

```sh
cd voxelcraft && git pull && cd deploy/homelab && docker compose up -d --build
```

Then publish the release with `tools/make_release.sh` (it builds the app, the mod zips, the download page
and the update manifest - see docs/distribution.md); the Macs pick it up by themselves. `tools/package_mac.sh`
alone still builds just the app if you want to copy it over by hand. Mods update with the
engine: the bundled ones are refreshed in `mods/` on the next start (unless `SEED_MODS` says otherwise), so a
mod change does not need a rebuild - only `docker compose restart`.

## Two worlds and portals (optional)

A second server (Sky Islands, the skyblock game) can run next to the family server, with portals between them.
Players keep their inventory as they travel.

1. Start both: `docker compose -p voxelcraft -f compose.yaml -f compose.two-worlds.yaml up -d --build`
   (and open its ports too: `sudo ufw allow 24567:24568/udp`).
2. Find each server's id in its log: `docker logs voxelcraft | grep "Server id"` and
   `docker logs voxelcraft-sky | grep "Server id"`.
3. Tell each server about the other. Copy `network.example.json`, fill in the *other* server's id and your
   machine's address, and put it in each server's data volume:
   ```sh
   cp network.example.json family-network.json   # "sky": port 24567, id of voxelcraft-sky
   cp network.example.json sky-network.json      # rename "sky" to "family": name, port 24565, id of voxelcraft
   nano family-network.json sky-network.json
   docker cp family-network.json voxelcraft:/data/network.json
   docker cp sky-network.json voxelcraft-sky:/data/network.json
   ```
   Then in game on each server (as admin): `/network reload`, and `/network` to check.
4. **Travel:** `/server sky` (with `"hop": true`, anyone may), or build a portal: place **Portal** blocks (from
   the creative inventory), stand next to them and type `/portal sky`. Walking into it takes you there.
   On the other side, stand where travellers should appear and type `/network arrival dock`, then point portals at
   it with `/portal family dock`.

If a trip cannot finish (the other server is down), coming back gives players their things back.

## 6. When something goes wrong

- **The server is not in the LAN list.** Check the Mac and the server are on the same network (guest Wi-Fi is often
  separate), that `docker compose logs` says `running game`, and the firewall step. Joining by address still works
  when discovery is blocked.
- **"This server is private."** The name is not on the allowlist: `/allow add Name` (check the spelling), or add it
  to `ALLOWLIST` and run `docker compose up -d`.
- **"The name belongs to another player."** Someone else already used that name on this server. Pick another name,
  or remove the old player's entry (ask for help).
- **"Its identity has changed since your last visit."** The server was rebuilt without its data volume, so it has a
  new identity. If you know that is what happened, click **Trust new identity**.
- **Version mismatch.** Update both sides (see above).
- **Everything is slow.** Settings → Graphics → Fast, and close other apps.
