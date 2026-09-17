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
# The address the other servers use to reach this machine. They are all on one box, so its own is right.
ADDRESS="${LINK_ADDRESS:-127.0.0.1}"

# Every world is on this machine, so carrying inventories between them is safe and is what the children
# will expect. Change to false to make each world a clean start.
CARRY_INVENTORY="${CARRY_INVENTORY:-true}"

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
