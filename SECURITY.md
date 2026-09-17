# Reporting a security problem

Please report anything that looks like a security bug **privately**, not as a public issue:

- GitHub → the **Security** tab → *Report a vulnerability* (private vulnerability reporting), or
- open a normal issue saying only "security report, please get in touch" with no details, and wait to be
  contacted.

This is a hobby project run by one person, so there is no bounty and no guaranteed response time, but
reports are taken seriously and you will get an answer.

## What is worth reporting

- Anything that lets a server run code on a player's machine, read their files, or take their identity key.
- Anything that lets a player run code on a server they joined, or act as another player.
- A way to make a client install something the project did not sign (see "Updates" below).
- A mod escaping the JavaScript sandbox.

## What is not a vulnerability

- A GDScript mod doing anything it likes **on the machine hosting the world**. GDScript mods are code, and
  installing one is trusting its author; this is why the in-game list only offers the curated index by
  default, and why JavaScript mods are the sandboxed option.
- An admin command doing admin things, or a server owner seeing data from their own server.

## How updates are protected

The game only installs an update whose manifest is signed by a release key built into that build
(`engine/client/updater.gd`), fetched over HTTPS from an address compiled into the client - never one a
server supplies - and the download must match the checksum in the signed manifest. The private key is not
in this repository. If you believe a release was published that the maintainer did not sign, report it.

## Reporting content, not code

Players can paint skins and build accessories in the game and share them with a server, which may pass
them on to other players there. A server run from this project is therefore capable of holding pictures
its operator did not make.

- **If something of yours is being shared without permission**, open an issue saying which server and
  which creation, or use the private reporting route above if you would rather not say it in public. The
  maintainer runs one small family server; anything hosted there will be taken down on request.
- **In game**, any player can report a creation they can see (including as *copied*), and enough reports
  hide it until an admin has looked. Admins have a review screen, and `--ugc=approval` makes every
  creation wait for a person before anyone else sees it.
- **Servers are independent.** Anyone can run this software, and the project has no control over what
  other people's servers hold.
