# Getting the game (and mods) to players

> **The bundled games were removed on 21 September 2026** and will be rebuilt for 1.0 (see
> `docs/roadmap.md`). Examples below that name `vanilla`, `hearthhold`, `industry`, `arcana`, `guild`,
> `skyblock` or `oneblock` describe how things *were*, and still illustrate the capability correctly -
> but you cannot run them as written. The mod the tests use now is `tests/mods/proving`, which uses
> every capability the engine has and is the best worked example there is.

How a build reaches a Mac, how it updates itself, and how mods are found, installed, configured and
chosen for a world. Written before alpha 2 so the first public release already works this way.

## 1. What a release publishes

`tools/make_release.sh` builds everything and writes the two files the game reads:

```
Quarrowen-<version>-mac-arm64.zip     the app
mods/<id>-<version>.zip                one zip per mod (base, vanilla, arcana, industry, guild,
                                       skyblock, oneblock)
update.json                            {version, notes, builds: {macos: {url, sha256, size}}}
mods.json                              the mod index: [{id, version, url, sha256, size}]
```

Both JSON files carry a checksum for every download. Nothing is installed without matching it.

## 2. Where it is published: GitHub Pages

A plain static site, so a kid can open one page and press Download:

```
https://quarrowen.com/
  index.html            what it is, Download for Mac, "first launch" instructions
  update.json           the updater's manifest (same file the release attaches)
  mods.json             the mod index
  v<version>/...        the zips
```

**The repository is public** (2026-09-16), so Pages and release assets both download without an
account - a private repository's release assets need a token, which a game cannot carry. The address is
baked into the client (`engine/client/updater.gd`), never taken from a server, and `project.godot`'s
`quarrowen/update_manifest_url` can point a fork somewhere else.

`tools/publish_site.sh` pushes the page, `update.json` and `mods.json` to the `gh-pages` branch, and
with `--with-release` attaches the zips to the GitHub release (release assets do not count against the
repository size, which matters at ~62 MB per build). Without a release it serves the zips from the
branch instead.

## 2a. Signing the app for macOS

Two different signatures, easily confused:

- **The app bundle** is signed with an **Apple Developer ID Application** certificate and notarized by
  Apple, so macOS opens it without the right-click dance. This is about the operating system trusting the
  download. `tools/package_mac.sh` does it when the certificate is in the keychain (and falls back to an
  ad-hoc signature, with a message, when it is not).
- **The update manifest** is signed with the project's own release key (§2b), which is about the *game*
  trusting an update. Neither replaces the other.

```sh
xcrun notarytool store-credentials quarrowen-notary --apple-id <you@example.com> \
  --team-id <TEAM ID> --password <app-specific password>   # once
tools/make_release.sh                                        # signs, hardens, notarizes, staples
```

`QUARROWEN_SKIP_NOTARIZE=1` signs without the (slow, online) notarization step, for a quick local build.
The Team ID is in App Store Connect under Membership details; `security find-identity -v -p codesigning`
shows the certificate once it is installed.

**Two things expire.** The signing certificate lasts five years (the current one to **17 September 2031**,
tracked in PROGRESS.md), and after that releases keep building but stop being trusted until a new one is
made. The notarization credentials are tied to an app-specific password: revoke that password in the
Apple ID settings and `store-credentials` has to be run again.

**A Developer ID certificate carries the name of whoever owns the account**, and `codesign -dv` on any
downloaded build shows it. That is how macOS tells a player who signed the thing they are about to run,
so it cannot be hidden; an individual account therefore publishes under a personal name, and only an
organisation account shows a company instead.

**Installing the certificate on a new machine** needs Apple's *Developer ID Certification Authority*
intermediate as well (apple.com/certificateauthority, "Developer ID - G2"). Without it the certificate is
in the keychain but not valid, and `security find-identity -v` lists nothing at all - which looks exactly
like the certificate failing to install.

## 2b. Signing a release

The manifest is signed, and a client only installs an update whose manifest one of its built-in release
keys signed. Without this, whoever controlled the website or its DNS could hand every player a build: the
checksum in the manifest only proves the download matches *that manifest*.

```sh
godot --headless --path . -s tools/release_key.gd -- new     # once: writes ~/.config/quarrowen/release_key.pem
                                                             # and prints the public half for RELEASE_KEYS
tools/make_release.sh                                        # signs update.json automatically when the key is there
```

- The **private key never leaves the maintainer's machine** and is not in this repository. Back it up; losing
  it means shipping a build with a new key before releases can resume.
- The **public halves** live in `engine/client/updater.gd` (`RELEASE_KEYS`), so they travel with each build.
- **Rotating:** add the new public key alongside the old one, ship that build, *then* start signing with the
  new key, and drop the old entry a release or two later. The updater accepts any listed key.
- A build whose `RELEASE_KEYS` are empty (anything up to 0.38.0) accepts an unsigned manifest, so the
  transition costs nothing; from the first build that carries a key, an unsigned or badly signed manifest is
  ignored with a message rather than installed.

## 3. Updating

The client checks the manifest when the menu opens (Settings → Network turns it off, Settings →
Account has a "Check for updates" button). When a newer version exists the menu banner offers it:
download → checksum → a small script waits for the game to quit, unpacks the zip, swaps the app,
clears the macOS quarantine flag and starts the new one. A failed swap puts the old app back.

Servers never hand the client a download address. A server can only say which protocol version it
needs; the client then offers the update from its own pinned source.

### Releasing from CI

A release can be cut by CI, so no particular machine has to be awake. It runs **only on a `v*` tag** and
**only after a human approves it**, because the certificate signs software as a named person: a leaked
Developer ID means somebody can ship malware that macOS tells your children came from you.

The gate is *reaching the job*, not hiding the values. Any step inside a job that can read a secret can
print it, so the protection that matters is the approval on the `release` environment.

**Naming an `environment:` in the workflow does not by itself gate anything.** GitHub creates a missing
environment implicitly, with no protection rules, and the job then runs unattended - which is exactly
what happened the first time a tag was pushed with this job in place. The approval exists only once
somebody adds required reviewers to that environment by hand. So the job is also switched off by a
repository variable, and both have to be done deliberately:

- **`SIGN_IN_CI` = `true`** (Settings → Secrets and variables → Actions → Variables). Without it the job
  is skipped, which is how it ships.
- **Required reviewers on the `release` environment.** Check them: Settings → Environments → release
  should list at least one reviewer. An environment with no protection rules is not a gate.

**Set up once.**

1. **An environment called `release`** - repository Settings → Environments → New environment → add
   yourself under *Required reviewers*. Without the reviewers it is not a gate at all (see above), so
   check the environment afterwards and confirm it lists one.

2. **An App Store Connect API key** for notarisation, at appstoreconnect.apple.com → Users and Access →
   Integrations → App Store Connect API → **+**, with the *Developer* role. Download the `.p8` **once**
   (Apple will not show it again) and note the Key ID and Issuer ID. An API key rather than the
   app-specific password in your keychain: it is scoped to notarisation and revocable on its own, where
   an app-specific password authenticates as your whole Apple Account.

3. **Your Developer ID certificate as a `.p12`** - Keychain Access → My Certificates → right-click
   *Developer ID Application: …* → Export, and give it a strong password.

4. **Six repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | What goes in it |
   |---|---|
   | `MACOS_CERT_P12` | `base64 -i cert.p12 \| pbcopy` |
   | `MACOS_CERT_PASSWORD` | the password you gave the export |
   | `NOTARY_KEY_P8` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
   | `NOTARY_KEY_ID` | the Key ID, e.g. `A1B2C3D4E5` |
   | `NOTARY_ISSUER_ID` | the Issuer ID (a UUID) |
   | `RELEASE_SIGNING_KEY` | the contents of `~/.config/quarrowen/release_key.pem` |

5. **The variable `SIGN_IN_CI` set to `true`**, on the Variables tab beside the secrets. This is the
   switch; everything above is inert without it.

   That last one is the key the *game* checks, not macOS: it signs `update.json` and `mods.json` so a
   client will not install an update the project did not publish. Losing it means shipping a build with a
   new key before updates can resume (§2b), so keep the original where it is as well.

Then a release is: push a `v*` tag, approve the run, and the images, the signed app, the disk image, the
GitHub release and the site all follow. Delete the local copies of the `.p12` and `.p8` afterwards - they
are in GitHub now, and a spare copy in Downloads is one more place to lose them from.

**Rotating or revoking.** The API key can be revoked in App Store Connect and replaced by changing one
secret. A leaked certificate is revoked at developer.apple.com → Certificates, which invalidates future
signatures; builds already notarised keep working, because the ticket is stapled into them.

Signing on a Mac by hand still works exactly as before (`tools/make_release.sh` with a keychain profile),
and is what to fall back on if CI is unavailable.

### Cutting a release

In this order, because the middle step is what the children actually feel:

1. `tools/run_tests.sh` and `QW_NATIVE=0 PORT_BASE=25700 tools/run_tests.sh` - both suites.
2. Bump `GAME_VERSION` in `engine/shared/protocol.gd`, and `VERSION` too if anything the client and
   server must agree on has changed (RPCs, or the block shape table).
3. Write the release notes in PROGRESS.md, and regenerate the save fixture for the new version
   (`tools/make_save_fixture.tscn -- --out=tests/fixtures/saves/<version>`).
4. **Bump the pinned image in `deploy/server/.env.example`** (`QW_IMAGE`, `QW_HUB_IMAGE`). It is pinned
   so a server never moves on its own; the cost of that is remembering to move it here.
5. Tag `v<version>` and push it. CI builds both server images from the tag alone, and waits for approval
   before signing anything.
6. Bring the family server up on the new version (edit its `.env`, `docker compose pull && up -d`)
   **before** approving the release. A client that updates itself cannot join a server still on the old
   protocol, so publishing first locks everyone out for as long as the server takes to follow.
7. Approve the `release` job (Actions → the run → Review deployments). It signs, notarizes, staples,
   attaches the files to the GitHub release and publishes the site. By hand instead:
   `tools/make_release.sh && tools/publish_site.sh --with-release` on a Mac with the certificate.
8. Download the app from the site and open it, on a Mac that has never seen this build. Gatekeeper's
   verdict on the real download is the only one that counts.

## 4. Mods: the problem

Today the app carries `base`, `vanilla` and the add-ons inside `Quarrowen.app/Contents/Resources/mods`,
and a dedicated server keeps its own copy in `/mods`. That covers the bundled games, but not:

- a player wanting a mod that does not ship with the game,
- a host choosing which mods a *local* world runs beyond the bundled list,
- a mod needing settings (difficulty, rates, feature switches) without editing its code.

Joining a server never needs an install: mods run on the server, and clients already download the
textures, models and sounds they need. The mod list matters for **hosting**.

## 5. Mods: the plan (Factorio-style)

### 5.1 Where mods live

| Place | What it is |
|---|---|
| inside the app | the mods that ship with a release; refreshed on update |
| `user://mods/` | mods the player installed; survives updates, per computer |
| a server's `/mods` volume | what that server runs (already how the Docker image works) |

`ModLoader.search_dirs` already looks in all three, so nothing changes in the engine's loading.

### 5.2 The in-game mod list (menu → Mods) — done, 0.39.0

A sidebar page with three tabs, next to Play and Multiplayer:

- **Installed**: everything found, with version, what kind of mod it is, and where it came from. Remove
  works only on mods in `user://mods` - the ones inside the app come back with every update anyway, and
  it warns first when another installed mod depends on it.
- **Available**: the entries from `mods.json` that are not installed, with size. Install downloads,
  checks the checksum, and unpacks into `user://mods/<id>/`.
- **Updates**: an installed mod with a newer version in the index. Only mods the player installed appear
  here; a bundled mod is updated by updating the game.

Dependencies come from the index (`depends`) and are installed first, in order; a dependency the index
does not offer stops the install with a plain message instead of leaving a mod that cannot load.

`mods.json` is built by `mod_tool -- index` from the packed zips themselves, so what the list claims and
what it ships cannot drift, and it is **signed with the release key** exactly like `update.json`: a
checksum only proves a download matches *that list*, so the list itself has to be the project's.

### 5.3 Choosing mods for a world

The New world dialog already picks a game (vanilla, skyblock, One Block) plus add-ons. It grows into:
the game list is every installed mod with `"game": true`, the add-on list every other installed mod, and
the choice is saved in `world.json` (it already is). Nothing changes for servers: their mod list stays
`QW_MODS` in the compose file, and the same zips drop into their `/mods` folder.

### 5.4 Safety

A GDScript mod is code that runs on whoever hosts the world. So:

- the **curated index** (`mods.json` from our own site) is what the browser offers by default;
- installing from a file or another address is behind an "Advanced" toggle with a plain warning that a
  mod can do anything the game can;
- JavaScript mods stay sandboxed (they already are) - the natural home for community content;
- every download is checksummed against the index, and an installed mod records where it came from.

## 6. Mod settings (done, 0.39.0)

Mods expose values a host can change without touching code (spawn rates, whether a feature is on, a
difficulty). A mod declares a schema and reads values; it never draws a screen:

```gdscript
api.register_settings({
    "monster_rate": {"label": "How many monsters", "type": "float", "default": 1.0, "min": 0.0, "max": 3.0,
                     "help": "Multiplies how often monsters appear."},
    "keep_tools":   {"label": "Keep tools when you die", "type": "bool", "default": true},
    "difficulty":   {"label": "Difficulty", "type": "choice", "default": "normal",
                     "choices": [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]},
})

var rate: float = api.setting("monster_rate")      # read anywhere, including while the mod starts
api.on("settings_changed", func(ev): ...)          # react while the server runs
```

Types: `bool`, `int`, `float` (`min`/`max`/`step`), `choice` (`choices: [[value, label]]`) and `text`.
A malformed entry is dropped with a warning instead of taking the server down, and a value that does not
fit (out of range, not one of the choices) is clamped or refused rather than stored.

**The server owns the values** - a setting is not client UI. All three ways in change the same thing on
the server, and the last one wins:

1. the schema's `default`;
2. `mod_settings.json` in the server's data folder, or `--mod-settings=<path or inline JSON>` /
   `QW_MOD_SETTINGS` for compose - for a dedicated server nobody logs into:
   ```json
   { "vanilla": { "monsters": "few", "day_minutes": 5 } }
   ```
3. what an admin changed in game, kept in the world's `world.json` under `mod_settings`, so a world
   carries its own rules and a backup restores them. Values from the file are *not* copied into the
   world, so removing a line from the file takes effect again.

Admins change them two ways, both checked against their role on the server: `/modsettings [mod] [key
value|reset]`, and a section per mod in the Server settings screen, built from the schema - no new UI
work per mod. A value for a mod that is not loaded this session is kept, not dropped.

**Per-player client preferences** (a mod's HUD position, say) come later through the same schema on the
client's settings screen; the server-side values were the piece that mattered.

## 2c. Building for iPad

`tools/package_ios.sh` produces `build/ios/Quarrowen.xcodeproj`. Godot's iOS export does **not** make
a finished app: it makes an Xcode project that you open, give a signing team to, and run on a device
or archive for TestFlight. The script's job ends where Xcode's begins.

```sh
cp apple.env.example apple.env    # once: put your Team ID in it
tools/package_ios.sh              # debug build
tools/package_ios.sh --release
```

**Your Apple Team ID is not in this repository.** `export_presets.cfg` is committed and the repo is
public, so the iOS preset carries an empty `app_store_team_id` and the real one lives in `apple.env`,
which `.gitignore` already covers through its `*.env` rule. The script exports from a throwaway copy
of the project with the value patched in - the same trick `package_mac.sh` uses to keep local editor
addons out of the app. Nothing with your account in it is ever written to a tracked file.

Two settings that are not optional and cost an export attempt each to discover:

- **`min_ios_version` must be 14.0 or above.** Godot 4.7 renders through Metal on iOS and refuses to
  export below 14, with "Metal renderer require iOS 14+".
- **The team id must be set**, even for a debug export that you are going to re-sign in Xcode anyway.

The Rust extension travels with it: `package_ios.sh` builds both `ios` and `ios-sim` frameworks first,
and they land in `Quarrowen/dylibs/native/bin/`. Xcode picks whichever the destination needs.

**Not yet done:** nothing has been run on a device, there is no provisioning profile in the repo and
no TestFlight build has been made.

## 6b. Mods on iPad

The iPad build (milestone 3 in PROGRESS.md) hosts local worlds the same way the Mac does, so **bundled
mods work there**: vanilla, skyblock, One Block and the add-ons ship inside the app and need no install.

Downloading *more* mods on iOS is deliberately left out of that first build. A GDScript mod is code, and
App Store rule 2.5.2 is about apps that download and run code that changes what they do - not a fight
worth having for alpha. The plan when it matters:

- iPad: the bundled mods, and **JavaScript mods** (already sandboxed) as the path for anything fetched;
- Mac: the full list above, GDScript mods included;
- joining a server is unaffected on every platform - its mods run on the server.

## 7. Order of work

1. **Distribution** (before alpha 2): `make_release.sh`, the Pages site, the public distribution repo,
   the download page, and the updater pointed at it. Alpha 2 is then downloaded, not handed over.
2. ~~**Mod settings**: schema, storage in the world, the Server settings section, the data-dir file.~~ Done.
3. ~~**Mod list in game**: installed/available/updates from the index, install and remove, and the New
   world dialog listing installed mods.~~ Done (the New world dialog already lists whatever is installed,
   and now re-reads it after an install).
4. **Community mods**: the advanced install path, and what a public index would need (submissions,
   review, a "verified" mark).
