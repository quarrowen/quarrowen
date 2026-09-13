// Adventurers' Guild: a VoxelCraft mod written in JavaScript.
//
// Shows off the JavaScript mod API: blocks with 3D models, items, recipes, a world-generation ore
// pass, interactive server-driven UI, per-player saved data, per-mod world storage, events (including
// cancelling breaks and rewriting drops), commands, timers and interoperation with other mods.
//
//   /guild kit      quest board + tools in your hotbar
//   /guild meteor   call down a meteor near you now
//   /guild top      the guild leaderboard
//   /guild bounty   summon a bounty monster worth extra coins (needs a mod with vanilla:zombie)

const METEOR_INTERVAL = 240; // seconds between meteor showers
const ACTIVE_QUEST_UI = "tracker";
const BOARD_UI = "board";

const QUESTS = [
  { id: "artisan", title: "Artisan", text: "Craft 3 items", stat: "crafted", goal: 3, reward: 4 },
  { id: "builder", title: "Apprentice Builder", text: "Place 20 blocks", stat: "placed", goal: 20, reward: 3 },
  { id: "breaker", title: "Stone Breaker", text: "Break 30 blocks", stat: "broken", goal: 30, reward: 5 },
  { id: "prospector", title: "Gold Rush", text: "Mine 3 gold ore", stat: "gold", goal: 3, reward: 8 },
  { id: "pathfinder", title: "Pathfinder", text: "Travel 150 blocks", stat: "travel", goal: 150, reward: 6 },
  { id: "stargazer", title: "Stargazer", text: "Touch a fallen meteorite", stat: "meteor", goal: 1, reward: 10 },
  { id: "hunter", title: "Monster Hunter", text: "Defeat 3 monsters", stat: "hunted", goal: 3, reward: 7 },
];
const BOUNTY_MOB = "vanilla:zombie";

export function setup(api) {
  const ids = {
    coin: api.registerItem("gold_coin", { display_name: "Gold Coin", icon: "textures/gold_coin.png" }),
    goldOre: api.registerBlock("gold_ore", { display_name: "Gold Ore", textures: "textures/gold_ore.png", drops: "guild:gold_coin" }),
    board: api.registerBlock("quest_board", {
      display_name: "Quest Board",
      model: "models/quest_board.glb",
      textures: "textures/quest_board_icon.png",
      interactive: true,
      orientation: "horizontal",
    }),
    meteorite: api.registerBlock("meteorite", {
      display_name: "Meteorite", textures: "textures/meteorite.png", light: 13, interactive: true, drops: "",
    }),
    cooled: api.registerBlock("cooled_meteorite", { display_name: "Cooled Meteorite", textures: "textures/meteorite_cooled.png" }),
  };

  api.registerSound("coin", "sounds/coin.wav", { pitch_variance: 0.05 });

  api.addOrePass({ ore: "guild:gold_ore", replace: "base:stone", veins: 3, size: 4, min_y: 5, max_y: 40, chance: 0.7 });
  api.registerRecipe({ "guild:gold_coin": 4, "base:planks": 2 }, "guild:quest_board");

  // The shop only lists goods from mods that are actually installed on this server.
  const shop = [
    { item: "base:glass", count: 8, price: 1 },
    { item: "base:coal", count: 8, price: 1 },
    { item: "industry:cable", count: 16, price: 2 },
    { item: "industry:battery", count: 1, price: 4 },
    { item: "arcana:mana_shard", count: 4, price: 3 },
    { item: "arcana:wand_of_blink", count: 1, price: 12 },
  ]
    .map((entry) => ({ ...entry, id: api.item(entry.item) }))
    .filter((entry) => entry.id > 0);
  api.info(`guild shop stocks ${shop.length} goods`);

  // --- Per-player quest state (saved with the world) -------------------------------------------

  const state = (player) => player.getData("quest", null);
  const setState = (player, value) => player.setData("quest", value);
  const coins = (player) => player.countOf(ids.coin);

  const offeredQuests = (player) => {
    const done = player.getData("completed", 0);
    // Rotate the offer as the player completes quests; the first offer is always Artisan.
    return [0, 1, 2].map((i) => QUESTS[(done + i) % QUESTS.length]);
  };

  const progress = (player, stat, amount = 1) => {
    const quest = state(player);
    if (!quest) return;
    const def = QUESTS.find((q) => q.id === quest.id);
    if (!def || def.stat !== stat || quest.progress >= def.goal) return;
    quest.progress = Math.min(def.goal, quest.progress + amount);
    setState(player, quest);
    showTracker(player);
    if (quest.progress >= def.goal) {
      player.showTitle("Quest complete!", `${def.title}: return to a Quest Board for ${def.reward} coins`, 3);
    }
  };

  // --- UI --------------------------------------------------------------------------------------

  const showTracker = (player) => {
    const quest = state(player);
    if (!quest) {
      player.hideUi(ACTIVE_QUEST_UI);
      return;
    }
    const def = QUESTS.find((q) => q.id === quest.id);
    player.showUi(ACTIVE_QUEST_UI, {
      anchor: "center_left",
      children: [
        { type: "label", text: `Quest: ${def.title}`, color: "#ffd166" },
        { type: "label", text: `${def.text}  (${Math.floor(quest.progress)}/${def.goal})` },
        { type: "progress", value: quest.progress, max: def.goal },
      ],
    });
  };

  const showBoard = (player) => {
    const quest = state(player);
    const children = [
      { type: "hbox", children: [
        { type: "label", text: "Adventurers' Guild", size: 24, color: "#ffd166" },
        { type: "spacer", size: 24 },
        { type: "image", asset: "guild:textures/gold_coin.png", size: 20 },
        { type: "label", text: `${coins(player)} coins` },
      ] },
    ];
    if (quest) {
      const def = QUESTS.find((q) => q.id === quest.id);
      const complete = quest.progress >= def.goal;
      children.push(
        { type: "label", text: `Active: ${def.title} - ${def.text}`, color: complete ? "#90be6d" : "#ffffff" },
        { type: "progress", value: quest.progress, max: def.goal },
        { type: "hbox", children: [
          { type: "button", text: `Turn in (+${def.reward} coins)`, action: "turn_in", disabled: !complete },
          { type: "button", text: "Abandon", action: "abandon" },
        ] },
      );
    } else {
      children.push({ type: "label", text: "Available quests", color: "#8ecae6" });
      for (const def of offeredQuests(player)) {
        children.push({ type: "hbox", children: [
          { type: "label", text: `${def.title}: ${def.text}  (${def.reward} coins)` },
          { type: "button", text: "Accept", action: `accept:${def.id}` },
        ] });
      }
    }
    children.push({ type: "label", text: "Shop", color: "#8ecae6" });
    for (const [index, entry] of shop.entries()) {
      children.push({ type: "hbox", children: [
        { type: "image", asset: iconFor(entry.item), size: 20 },
        { type: "label", text: `${entry.count} x ${api.itemDisplayName(entry.id)} - ${entry.price} coins` },
        { type: "button", text: "Buy", action: `buy:${index}`, disabled: coins(player) < entry.price },
      ] });
    }
    children.push({ type: "button", text: "Close", action: "close" });
    player.showUi(BOARD_UI, { anchor: "center", modal: true, children });
  };

  const iconFor = (itemName) => ({
    "base:glass": "base:textures/glass.png",
    "base:coal": "base:textures/coal.png",
    "industry:cable": "industry:textures/cable.png",
    "industry:battery": "industry:textures/battery_icon.png",
    "arcana:mana_shard": "arcana:textures/mana_shard.png",
    "arcana:wand_of_blink": "arcana:textures/wand_of_blink.png",
  })[itemName] ?? "guild:textures/gold_coin.png";

  api.on("ui_action", ({ player, ui_id, action }) => {
    if (ui_id !== `guild:${BOARD_UI}`) return;
    const [verb, arg] = action.split(":");
    switch (verb) {
      case "close":
        player.hideUi(BOARD_UI);
        return;
      case "accept": {
        const def = QUESTS.find((q) => q.id === arg);
        if (def && !state(player)) {
          setState(player, { id: def.id, progress: 0, start: player.position });
          player.sendMessage(`Quest accepted: ${def.title}`);
        }
        break;
      }
      case "abandon":
        setState(player, null);
        break;
      case "turn_in": {
        const quest = state(player);
        const def = quest && QUESTS.find((q) => q.id === quest.id);
        if (def && quest.progress >= def.goal) {
          player.give(ids.coin, def.reward);
          setState(player, null);
          player.setData("completed", player.getData("completed", 0) + 1);
          const ledger = api.storage.get("ledger", {});
          ledger[player.name] = (ledger[player.name] ?? 0) + 1;
          api.storage.set("ledger", ledger);
          api.broadcast(`${player.name} completed "${def.title}" for the Guild`);
        }
        break;
      }
      case "buy": {
        const entry = shop[Number(arg)];
        if (entry && player.take(ids.coin, entry.price)) {
          player.give(entry.id, entry.count);
          player.playSound("guild:coin");
          player.sendMessage(`Bought ${entry.count} x ${api.itemDisplayName(entry.id)}`);
        }
        break;
      }
    }
    showTracker(player);
    showBoard(player);
  });

  // --- World events ----------------------------------------------------------------------------

  api.on("block_interact", ({ player, position, block }) => {
    if (block === ids.board) {
      showBoard(player);
    } else if (block === ids.meteorite) {
      api.setBlock(position, ids.cooled);
      player.give(ids.coin, 3);
      player.showTitle("Stardust!", "+3 coins from the meteorite", 2.5);
      progress(player, "meteor");
    }
  });

  api.on("block_break", (ev) => {
    // Guild property: only builders in creative mode may remove quest boards.
    if (ev.block === ids.board && !ev.player.isCreative()) {
      ev.cancelled = true;
      ev.player.sendMessage("The Guild frowns upon vandalism.");
    }
    // Gold mined at night is lucky: double coins.
    if (ev.block === ids.goldOre && api.daylight() < 0.3) {
      ev.drops = [[ids.coin, 2]];
    }
  });

  api.on("block_broken", ({ player, block }) => {
    progress(player, "broken");
    if (block === ids.goldOre) progress(player, "gold");
  });
  api.on("block_placed", ({ player }) => progress(player, "placed"));

  // Monster hunting: any mob a player defeats counts for the quest; bounty monsters pay coins.
  api.on("entity_death", ({ entity, attacker }) => {
    if (!(attacker instanceof api.Player) || entity.kind !== "mob") return;
    progress(attacker, "hunted");
    const bounty = entity.getData("bounty", 0);
    if (bounty > 0) {
      attacker.give(ids.coin, bounty);
      attacker.showTitle("Bounty claimed!", `+${bounty} gold coins`, 2.5);
      api.playSound("guild:coin", entity.position);
    }
  });
  api.on("item_crafted", ({ player }) => progress(player, "crafted"));

  api.on("player_join", ({ player, first_time }) => {
    showTracker(player);
    if (first_time) player.sendMessage("The Adventurers' Guild is recruiting! Craft or /guild kit a Quest Board.");
  });

  // Distance-based quests are checked on a timer rather than every movement tick.
  api.every(1, () => {
    for (const player of api.players()) {
      const quest = state(player);
      if (quest?.id !== "pathfinder" || !quest.start) continue;
      const here = player.position;
      const travelled = Math.hypot(here.x - quest.start.x, here.z - quest.start.z);
      if (travelled > quest.progress) progress(player, "travel", travelled - quest.progress);
    }
  });

  // --- Meteor showers --------------------------------------------------------------------------

  const dropMeteor = (target) => {
    const origin = target.position;
    const angle = Math.random() * Math.PI * 2;
    const distance = 8 + Math.random() * 12;
    const x = Math.floor(origin.x + Math.cos(angle) * distance);
    const z = Math.floor(origin.z + Math.sin(angle) * distance);
    const y = api.surfaceY(x, z);
    if (y < 1 || y > 120) return null;
    const gravel = api.block("base:gravel");
    for (let dx = -1; dx <= 1; dx++) {
      for (let dz = -1; dz <= 1; dz++) {
        if (dx !== 0 || dz !== 0) api.setBlock({ x: x + dx, y, z: z + dz }, gravel);
      }
    }
    const position = { x, y: y + 1, z };
    api.setBlock({ x, y, z }, gravel);
    api.setBlock(position, ids.meteorite);
    api.broadcast(`A meteor fell near ${target.name} at ${x}, ${y + 1}, ${z}!`);
    for (const player of api.players()) player.showTitle("Meteor shower!", `Something landed near ${target.name}`, 3);
    return position;
  };

  api.every(METEOR_INTERVAL, () => {
    const players = api.players();
    if (players.length > 0) dropMeteor(players[Math.floor(Math.random() * players.length)]);
  });

  // --- Commands --------------------------------------------------------------------------------

  api.command("guild", "kit | meteor | top | coins | bounty - Adventurers' Guild", (player, args) => {
    const sub = args[0] ?? "";
    const cheat = sub === "meteor" || (sub === "kit" && !player.isCreative());
    if (cheat && !player.isAdmin()) {
      player.sendMessage(`Only admins can use /guild ${sub} here.`);
      return;
    }
    switch (sub) {
      case "kit":
        if (player.isCreative()) {
          player.setHotbar([ids.board, api.block("base:planks"), api.block("base:stone"), ids.goldOre]);
        } else {
          player.give(ids.board, 1);
        }
        player.sendMessage("Place the Quest Board and right-click it to take quests.");
        break;
      case "meteor": {
        const where = dropMeteor(player);
        if (!where) player.sendMessage("The sky is quiet here.");
        break;
      }
      case "top": {
        const ledger = Object.entries(api.storage.get("ledger", {})).sort((a, b) => b[1] - a[1]).slice(0, 8);
        player.showUi("leaderboard", {
          anchor: "center_right",
          children: [
            { type: "label", text: "Guild leaderboard", size: 20, color: "#ffd166" },
            ...(ledger.length
              ? ledger.map(([name, count], rank) => ({ type: "label", text: `${rank + 1}. ${name} - ${count} quests` }))
              : [{ type: "label", text: "No quests completed yet" }]),
          ],
        });
        api.after(8, () => player.online && player.hideUi("leaderboard"));
        break;
      }
      case "bounty": {
        if (!player.isAdmin()) {
          player.sendMessage("Only admins can post bounties.");
          break;
        }
        const here = player.position;
        const look = player.lookDirection;
        const mob = api.spawnEntity(BOUNTY_MOB, { x: here.x + look.x * 4, y: here.y + 0.5, z: here.z + look.z * 4 }, { data: { bounty: 5 } });
        player.sendMessage(mob ? "A bounty monster appeared! Defeat it for 5 coins." : `No ${BOUNTY_MOB} on this server.`);
        break;
      }
      case "coins":
        player.sendMessage(`You carry ${coins(player)} gold coins.`);
        break;
      default:
        player.sendMessage("Usage: /guild kit | meteor | top | coins | bounty");
    }
  });
}
