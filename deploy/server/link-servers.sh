#!/usr/bin/env bash
# Lets players travel between the three worlds: portals, /server <name> and the Worlds panel.
#
#   ./link-servers.sh            # run once after the first `docker compose up -d`
#
# Travel is not the hub. The hub is the server *list*; this is the part that actually moves somebody from
# one world to another. Each world needs a network.json naming the others, and each entry needs that
# server's 32-character id - which is generated on first start, which is why this is a script you run
# afterwards rather than a file checked in beside compose.yaml.
#
# Run it again whenever a world is added, or after deleting a world's volume (a new volume means a new id).
set -euo pipefail
cd "$(dirname "$0")"

# key:container:port - the key is what a player types in /server <key>.
WORLDS=(
  "hearthhold:quarrowen-hearthhold:24565"
  "oneblock:quarrowen-oneblock:24567"
  "skyblock:quarrowen-skyblock:24569"
)
# The address a *player's computer* uses to reach this machine - it is handed to the client, which then
# connects to it itself. So it must not be 127.0.0.1: that is the player's own machine, not this one, and
# the trip fails with "couldn't connect to 127.0.0.1". This guesses the LAN address; set LINK_ADDRESS to
# a hostname or public address if players reach the box some other way.
ADDRESS="${LINK_ADDRESS:-}"
if [ -z "$ADDRESS" ]; then
  ADDRESS="$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1)"
  [ -z "$ADDRESS" ] && ADDRESS="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -z "$ADDRESS" ] && ADDRESS="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
case "$ADDRESS" in
  ""|127.*|localhost)
    echo "Could not work out this machine's address on the network." >&2
    echo "Run it with the address players use to reach this box, e.g." >&2
    echo "  LINK_ADDRESS=192.168.1.20 ./link-servers.sh" >&2
    exit 1 ;;
esac
echo "Players will be sent to $ADDRESS when they travel."

# Whether things in a player's pockets come with them. Off by default: each world is its own game, and
# One Block and Sky Islands are no challenge at all if you arrive with a full chest from somewhere else.
# Nothing is lost either way - each world remembers its own inventory for when you come back.
CARRY_INVENTORY="${CARRY_INVENTORY:-false}"

id_of() { # container
  # The server prints its id on every start (engine/server/transfers.gd).
  docker logs "$1" 2>&1 | grep -oE "Server id [0-9a-f]{32}" | tail -1 | awk '{print $3}'
}

declare -A IDS NAMES PORTS
for world in "${WORLDS[@]}"; do
  IFS=':' read -r key container port <<<"$world"
  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    echo "$container is not running - start everything first: docker compose up -d" >&2
    exit 1
  fi
  id="$(id_of "$container")"
  if [ -z "$id" ]; then
    echo "could not find $container's server id in its log." >&2
    echo "It is printed at every start, so restart it and try again: docker compose restart ${container#quarrowen-}" >&2
    exit 1
  fi
  IDS[$key]="$id"
  NAMES[$key]="$container"
  PORTS[$key]="$port"
  echo "$key: $id"
done

for world in "${WORLDS[@]}"; do
  IFS=':' read -r key container _ <<<"$world"
  # Every world lists the other two. `hop` lets anyone use /server; `admit` lets an arrival past the
  # allowlist, which matters because a child allowed on one world is allowed on all of them.
  entries=""
  for other in "${WORLDS[@]}"; do
    IFS=':' read -r other_key _ other_port <<<"$other"
    [ "$other_key" = "$key" ] && continue
    [ -n "$entries" ] && entries+=","
    entries+=$(printf '"%s":{"name":"%s","address":"%s","port":%s,"id":"%s","send":true,"receive":true,"inventory":%s,"admit":true,"hop":true}' \
      "$other_key" "$other_key" "$ADDRESS" "$other_port" "${IDS[$other_key]}" "$CARRY_INVENTORY")
  done
  printf '{"servers":{%s}}\n' "$entries" >"/tmp/network-$key.json"
  docker cp "/tmp/network-$key.json" "$container:/data/network.json"
  rm -f "/tmp/network-$key.json"
  echo "wrote network.json into $container"
done

echo
echo "Restarting so they read it..."
docker compose restart hearthhold oneblock skyblock
echo
echo "Done. In game: /server oneblock, /server skyblock, /server hearthhold - or build a portal."
if [ "$CARRY_INVENTORY" = "true" ]; then
  echo "Pockets travel between worlds. CARRY_INVENTORY=false ./link-servers.sh to make each world a clean start."
else
  echo "Each world has its own inventory, and remembers it. CARRY_INVENTORY=true ./link-servers.sh if things should travel."
fi
