# Quarrowen hub

The public server list, short invite codes, news, and friends and parties for the game's menu.

```sh
cargo run --release                      # http://0.0.0.0:24600, data in ./hub-data
HUB_ALLOW_PRIVATE=1 cargo run --release  # a LAN or local hub that also lists private addresses
docker build -t quarrowen-hub . && docker run -p 24600:24600 -v hub-data:/data quarrowen-hub
```

Game servers list themselves with `--hub=https://hub.example.org` (optionally `--public-address=` and
`--tags=`); players set the same address in Settings → Network. Put `news.json` (`[{"title", "body"}]`)
in the data directory for the menu's "What's new" panel.

How listings stay honest: each announce is signed with the server's identity key, and the hub checks
the address with the game's UDP status query, asking the server to sign a fresh nonce. An address is
only listed for the key that answers from it, so nobody can list someone else's server or take over
its entry and invite code. Listings expire 95 seconds after the last heartbeat (servers send one every
30 seconds and remove themselves on shutdown).

Friends and parties: players sign in with their game identity key (the hub's nonce, signed as
`quarrowen-hub-login:<hub url>:<nonce>`, so neither a game server nor another hub can obtain a valid
sign-in). Each player gets a friend code (`ABCD-EFGH`); friendships are stored in SQLite, while sessions,
presence (online, and the server when the player shares it) and parties (up to 8, the leader's server
visible to members) are kept in memory. Set `HUB_PUBLIC_URL` to the address players use, so sign-ins
made for another address are refused.

Behind a reverse proxy (TLS), set `HUB_TRUST_PROXY=1` so the client address comes from
`X-Forwarded-For`. The API is described at the top of `src/main.rs`.
