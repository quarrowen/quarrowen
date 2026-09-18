# Playing Quarrowen at home

A family setup: the server runs in Docker on a home Linux machine, and everyone plays from their own Mac
(Apple silicon) on the same home network.

- [1. The server (Ubuntu + Docker)](#1-the-server-ubuntu--docker)
- [2. The Macs](#2-the-macs)
- [3. First game](#3-first-game)
- [4. Admin cheat sheet](#4-admin-cheat-sheet)
- [5. Backups and updates](#5-backups-and-updates)
- [6. When something goes wrong](#6-when-something-goes-wrong)

## 1. The server (Ubuntu + Docker)

You need Docker with the Compose plugin (`docker compose version` should work). Nothing else: the server
is a published image, so this machine never compiles anything and does not need the repository.

**Get the three files.** They are all the server needs:

```sh
mkdir -p ~/quarrowen && cd ~/quarrowen
base=https://raw.githubusercontent.com/quarrowen/quarrowen/master/deploy/server
curl -fsSLO "$base/compose.yaml"
curl -fsSL -o .env.example "$base/.env.example"
curl -fsSLO "$base/link-servers.sh" && chmod +x link-servers.sh
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

**Start it.** The images are built by CI from each release tag and published to GitHub Packages, so this
downloads rather than compiles:

```sh
docker compose pull
docker compose up -d
docker compose logs -f     # Ctrl+C stops watching, not the server
```

(If a pull is refused with "denied" or "not found", the package is still private. On GitHub open the
repository's **Packages** and set both `server` and `hub` to public - package settings, change
visibility. It only needs doing once each, and public packages have no storage limit.)

It is ready when the log says `running game`. The server starts again by itself after a reboot.

**Firewall.** If the machine uses `ufw`, open the two game ports (UDP):

```sh
sudo ufw allow 24565:24566/udp
```

Note the machine's address on your network (something like `192.168.1.x`): `hostname -I`.

**Mods live beside each world, not inside the image.** The container holds the engine and a seed copy of
the mods it shipped with; each world has its own mods folder, in a Docker volume of its own. To add a game
or an add-on to one world:

```sh
docker cp ~/my_mod quarrowen-hearthhold:/mods/      # a mod folder with a mod.json inside
nano .env                                           # HEARTHHOLD_MODS=hearthhold,my_mod
docker compose up -d
```

A volume rather than a folder on the host, for two reasons that both showed up the first time this ran: a
host folder is created by Docker as root and the server runs as an ordinary user, so it could not write
its own mods into it; and three worlds refreshing the same folder on start is a race. `docker run --rm -v
quarrowen-mods-hearthhold:/m -v "$PWD":/out debian cp -r /m /out/mods-hearthhold` copies one out to look at.

On each start the mods that came with the engine (`base`, `vanilla`, the add-ons) are refreshed from the
image so an update cannot leave stale content behind; everything else there is left alone. Set
`SEED_MODS=missing` to keep your own edits to the bundled mods, or `SEED_MODS=never` to manage them yourself.

## 2. The Macs

**Build the app** once, on the Mac with this project (needs the Godot editor and Rust installed, as for
development):

```sh
tools/package_mac.sh
```

It makes `build/macos/Quarrowen-<version>-mac-arm64.zip`. Send the zip to each Mac (AirDrop works well).

**Install on each Mac:**

1. Double-click the zip, then drag **Quarrowen** into **Applications**.
2. Open it. A **signed and notarized** build (any release built on a machine with the project's Developer
   ID certificate - see below) opens straight away.
3. An **unsigned** build - one you built yourself without the certificate - is blocked by macOS the first
   time: right-click (or Control-click) **Quarrowen** in Applications, choose **Open**, then **Open**
   again. If there is no Open button: try to open it once, then go to **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway**. (Or, in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Quarrowen.app`.) After that it opens normally.

**Signing a release so nobody has to do step 3** (needs an Apple Developer account, $99/yr):

```sh
# once: a Developer ID Application certificate in your keychain, and a notarytool profile
xcrun notarytool store-credentials quarrowen-notary --apple-id <you@example.com> \
  --team-id <TEAM ID> --password <app-specific password>

tools/make_release.sh            # signs, hardens, notarizes and staples automatically
```

`tools/package_mac.sh` looks for the certificate itself; without one it signs ad hoc and says so, so
building on any other machine still works.

A MacBook Air runs the game well on the default graphics. If it feels slow, open **Settings → Graphics** and
choose **Fast**.

## 3. First game

1. **You first.** Open Quarrowen, click the name under **Playing as** at the bottom left and type your admin name
   exactly as in `ADMINS`. The first player to use a name on a server keeps it, so join before sharing.
2. Go to **Multiplayer → LAN**. The server appears there (the name from `SERVER_NAME`). Double-click it.
   If it does not appear, type the server's address (the one from `hostname -I`) in the box at the top and press **Join**.
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
docker run --rm -v quarrowen-hearthhold:/data -v "$PWD":/out debian tar czf /out/hearthhold-world.tgz -C /data .
```

(`docker volume ls` shows the exact volume name.) The volume also holds the server's identity: keep it, or
every Mac will warn that the server's identity changed.

**Worlds survive updates**, from alpha 4 on: builds, chests, animals and inventories are kept. A world saved
by anything older is refused rather than converted. Each world has its own volume, named outright in the
Compose file (`quarrowen-hearthhold`, `quarrowen-oneblock`, `quarrowen-skyblock`, `quarrowen-hub`), so they
stay put wherever the folder lives or whatever it is called. `docker volume ls` shows what is on the machine.

**The Macs update themselves.** When the menu opens, the game checks the download page and offers the new
version in a banner; pressing Update downloads it, checks it against the checksum published with the release
and swaps the app (Settings → Network turns the check off, Settings → Account has a "Check for updates"
button). Nothing is ever downloaded from a game server - a server can only say which version it needs.

**Coming from before alpha 4.** Nothing is carried across: worlds, players and identity keys all start
again. Alpha 4 moved the client's folder and dropped the code that read older saves, so a world from
alpha 3 or earlier will not load, and each Mac is a new player as far as a server is concerned - add the
children to `ALLOWLIST` again, or let them join once with it turned off. Old data is not deleted, just no
longer read: on a Mac it stays in `~/Library/Application Support/Godot/app_userdata/Quarrowen`, and on the
server in whatever volume it was in.

**Starting one world again.** A world holds its own story: in Hearthhold, once the hearth is lit,
chapter one is done for everyone who joins afterwards. To give a world a clean start without disturbing
anything else:

```sh
docker compose stop hearthhold
docker run --rm -v quarrowen-hearthhold:/data alpine \
  sh -c 'rm -rf /data/hearthhold /data/backups/hearthhold'
docker compose up -d hearthhold
```

Name the world in place of `hearthhold` for the others; the volume and the folder inside it share its
name. **Do not delete the volume itself.** It also holds `identity/`, which is what the Macs pin so they
know the server is the same one - losing it makes every client warn that the server's identity changed -
and `network.json`, which is what lets players travel between the worlds. Removing only the world folder
and its backups keeps both, so nothing needs re-linking and nobody is warned.

A player who has already started a tutorial keeps their place, since progress is saved per player rather
than per world. `/tutorial stop` and then `/tutorial start <id>` begins one again (`/tutorial list`).

**Updating.** Server and Macs must run the same version: a server refuses a client on a different
protocol. `.env` pins the server to an exact version for that reason, so it never moves on its own while
the children are still on the old client. To update, publish the release for the Macs first, then:

```sh
cd ~/quarrowen
nano .env                                  # QW_IMAGE / QW_HUB_IMAGE -> the new version
docker compose pull && docker compose up -d
```

Set them to `:latest` instead if you would rather follow every release automatically - with the caveat
that any `docker compose pull`, whatever you ran it for, then moves all three worlds at once.
Re-download compose.yaml when it changes (rarely).

Then publish the release with `tools/make_release.sh` (it builds the app, the mod zips, the download page
and the update manifest - see docs/distribution.md); the Macs pick it up by themselves. `tools/package_mac.sh`
alone still builds just the app if you want to copy it over by hand. Mods update with the
engine: the bundled ones are refreshed in `mods/` on the next start (unless `SEED_MODS` says otherwise), so a
mod change does not need a rebuild - only `docker compose restart`.

## Three worlds, travel between them, and the hub

`docker compose up -d` starts all three worlds and the hub. Open their ports once:

```sh
sudo ufw allow 24565:24570/udp   # the three worlds (each uses its port and the next one up)
sudo ufw allow 24600/tcp         # the hub
```

**The hub is a server list, not a way to travel.** Each world announces itself to it, so the game's
Multiplayer screen shows Hearthhold, One Block and Sky Islands by name and nobody types an address. That
is all it does. Moving a player from one world to another is a separate thing, below.

**Travel** (portals, `/server <name>`, the Worlds panel) needs each world to know the others' 32-character
server ids, and those only exist once a server has started. So after the first `up`:

```sh
./link-servers.sh
```

It reads each id, writes a `network.json` into each world naming the other two, and restarts them. Run it
again after adding a world, or after deleting a volume - a new volume means a new id. Then in game:

- `/server oneblock`, `/server skyblock`, `/server hearthhold` - anyone may, and inventories come along.
- Or build a **portal**: place Portal blocks (creative inventory), stand next to them and type
  `/portal oneblock`. Walking in takes you there. To choose where travellers arrive, stand on the spot on
  the far side and type `/network arrival dock`, then point portals at it with `/portal hearthhold dock`.
- `/network` lists what this world is linked to, and `/network reload` re-reads the file.

A player on the allowlist is allowed on all three, and an arrival skips the check (`admit`), so nobody is
bounced halfway through a portal.

**What the three are.** Hearthhold is survival with a story: a valley whose light went out, people to find
and houses to build them. One Block gives everyone a single block over the void that becomes something
else each time it is broken, in phases. Sky Islands gives everyone a small island, a cobblestone
generator and a list of challenges. Hearthhold is the one to start a child on.

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

## A word about skins

The game lets children paint a skin, and import a PNG to start from. Anything they wear can be offered to
the server they join, and other players there may then wear it too - which is lovely when it is their own
drawing, and awkward when it is a skin downloaded from a site that belongs to somebody else.

The family server accepts creations automatically (`--ugc=auto`), which suits people who know each other.
For a server with strangers on it, `--ugc=approval` holds every creation until an admin says yes, and
`--ugc=off` turns sharing off entirely. Either way an admin can review, hide and remove creations in game.

## Playing at home

`docs/playtest.md` walks through a family setup: the server in Docker on a home Linux machine
(`deploy/server/compose.yaml` with an allowlist, creations approval and the chat filter), the Mac app
built with `tools/package_mac.sh` (ad-hoc signed; first launch via right-click → Open), joining through
Multiplayer → LAN, and an admin cheat sheet.

Private servers: `--allowlist=Ann,Ben` (or `QW_ALLOWLIST`) lets only those players and admins join; admins
manage it with `/allow list | add <name> | remove <name> | on | off`. A listed name is tied to the first
identity that joins with it. `--chat-filter=on` (the `chat_filter` gameplay rule) masks common swear words
and look-alike spellings in chat and refuses such player names; add words in `<world>/chat_filter.txt`.

### Roles and permissions

Every player has the default role (`member`, or `--default-role=visitor` for look-but-don't-build servers) plus
any roles given to them. Built-in roles, highest first: **owner** (everything; `--admins` names and the local
host), **admin** (everything but making owners), **moderator** (kick, teleport, review creations, the allowlist,
alerts; inherits builder), **builder** (structures; inherits member), **member** (build, interact, chat, creative;
inherits visitor), **visitor** (chat, interact). Permissions are names like `build`, `interact`, `chat`,
`creative`, `ugc.review`, `allowlist.manage`, `dev.tools`, `roles.manage` and `command.<name>` for admin-only
commands; `*` and `group.*` match many, `-name` denies (and wins).

In game: `/role list | info <role> | give|take <player> <role> | create <role> [inherits] | delete <role> |
allow|deny|remove <role> <permission> | tag <role> <tag> [#color] | reset <role>` and `/perms [player]`; `/op`
and `/deop` give and take admin. Admins also get **Players and roles…** in the pause menu (roles as chips, give a
role, kick). Managers can only hand out roles below their own; only owners edit roles. Chat shows the highest
role tag (`[Mod] Sam`, the `role_tags` rule). Mods: `player.has_permission(name)`, `register_permission(name,
description, roles)`, `player_roles(id)`, `set_player_role(id, role, on)` and the `role_changed` event
(JavaScript: `hasPermission`, `registerPermission`, `playerRoles`, `setPlayerRole`). Saved in world.json.

### Anti-cheat

The server simulates movement from inputs, checks reach, break times, attack cooldowns and edit rates, so a
modified client cannot simply fly, teleport or instamine. On top of that, `engine/server/anticheat.gd` watches
for clients pushing past those limits: **timer** (inputs faster than the game runs; the server lets a client take
at most ~5% more steps than ticks, so sped-up inputs gain nothing), **reach**, **fast_break**, **attack_rate**,
**bad_packet** and **flood** (more than 400 messages a second are dropped). Each check keeps a score per player
that decays over time, so lag and the odd early click fade away: past a warning level moderators are told
(`moderation.alerts`), past a kick level the player is kicked. `--anticheat=kick|log|off` (in game `/anticheat
mode ...`), `/anticheat [player]` for scores and recent flags. Players with `anticheat.bypass` (admins) are only
logged; mods can cancel with the `cheat_detected {player, check, score, detail, cancelled}` event.

### Save compatibility

Worlds must keep working across updates, from alpha 4 (0.40.0) on. Chunks save blocks by name, containers and
entities by name, and since save format 2 player inventories and equipment are saved by item name too (`items`
in each player record) - which is what makes adding, removing and reordering blocks safe. A world in an older
format is refused rather than converted: there is no converter, and nothing from before alpha 4 is carried
forward. `tests/save_compat_test.tscn` loads a world written by each release (`tests/fixtures/saves/<version>/`,
made with `tools/make_save_fixture.tscn` from that release's checkout) and checks builds, chest contents,
animals, inventories and worn equipment. Mods: store names (`items.name_of`), never numeric ids, in block data,
player data and storage.

### Server networks: transfers and portals

Servers that trust each other send players between them. Each lists the others in `<data dir>/network.json`
(`{"servers": {"sky": {"name", "address", "port", "id", "send", "receive", "inventory", "admit", "hop"}}}`;
a server's id is printed at startup and by `/network id`). Moving a player (`/transfer <player> <server>
[arrival]`, `/server <name>` when `hop` is on, a **Portal** block pointed with `/portal <server> [arrival]`, or
`player.transfer_to(server, arrival, data)` from mods) signs a two-minute ticket with the source server's
identity key. The client connects to the destination and hands it over; the destination accepts it only from
servers on its list, for this player and this server, once. Arrival points are named with `/network arrival
<id>`. With `inventory` on both sides, inventories travel by item name (unknown items are reported) and the
source keeps a copy until the player turns up, so a failed trip loses nothing. `admit` lets arrivals skip the
allowlist. Events: `player_transfer {player, server, arrival, data, cancelled, reason}` (cancellable, data can be
changed) and `player_arrived {player, from, arrival, data}`; `network_servers()`, `set_arrival_point(id, pos)`.
Example setup: `deploy/server/compose.yaml` (three worlds and a hub) with `deploy/server/link-servers.sh`,
which fills in each server's network.json once the ids exist. See docs/playtest.md.

## Dedicated server & Docker

`scenes/server.tscn` (`engine/server_main.gd`) loads no client code. Every option is a CLI arg or an
environment variable: `QW_PORT`, `QW_MODS`, `QW_MODS_DIR`, `QW_DATA_DIR`, `QW_WORLD`,
`QW_SEED`, `QW_MAX_PLAYERS`, `QW_METRICS`, `QW_ADMINS`, `QW_ADMIN_TOKEN`,
`QW_BACKUP_INTERVAL`, `QW_BACKUP_KEEP`, `QW_RESTORE`, `QW_NAME` and `QW_MOTD` (shown in
server lists) and `QW_QUERY_PORT`: status queries for menus (name, message, game, players, ping)
are answered over UDP on the game port + 1 by default (0 turns them off; rate limited per address).
`QW_HUB` lists the server on a hub (with `QW_PUBLIC_ADDRESS` and `QW_TAGS`).

### Hub service

`services/hub` is a small Rust service (axum, SQLite) for the public server list, short invite codes
menu news, and friends and parties (sign-in with the identity key); see its README. Servers announce every 30 seconds, signed with their identity key, and
the hub proves the address with a signed status query before listing it. Players point the game at a
hub in Settings → Network (or `QW_HUB`). `tools/run_tests.sh` builds it and runs its unit tests and
`tests/hub_test.tscn` (a real hub and game server) when cargo is installed.

```sh
docker build -t quarrowen-server .
docker run -p 24565-24566:24565-24566/udp -v voxel-data:/data -e QW_MODS=vanilla,industry quarrowen-server
docker compose up        # vanilla on 24565, skyblock on 24567 (status on the next port)
```

The image compiles the Rust extension for the target architecture, exports the "Linux Server" preset
and ships the engine only (about 250 MB). **Mods live in the `/mods` volume, not in the image:** on
every start `deploy/entrypoint.sh` refreshes the mods the engine shipped with into `/mods` and leaves
everything else there alone, so a mod is added by dropping its folder (or a packaged zip) in and
restarting - no rebuild. `QW_SEED_MODS=missing` keeps your edits to the bundled mods, `never`
leaves the folder entirely to you. Worlds live in the `/data` volume. SIGTERM and SIGINT trigger a
save before exit, so `docker stop` is safe.
