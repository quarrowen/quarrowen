// Adventurers' Guild: a VoxelCraft mod written in JavaScript.
//
// Shows off the JavaScript mod API: blocks with 3D models, items, recipes, a world-generation ore
// pass, interactive server-driven UI, per-player saved data, per-mod world storage, events (including
// cancelling breaks and rewriting drops), commands, timers and interoperation with other mods.
//
//   /guild kit      quest board + tools in your hotbar
//   /guild meteor   call down a meteor near you now
//   /guild top      the guild leaderboard
//   /guild bounty   summon an elite bounty monster worth extra coins (needs a mod with vanilla:zombie)
//   /guild goblin   release a treasure goblin that grabs dropped coins and runs away with them

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

  // --- Cosmetics: a cape for members who have completed three quests -----------------------------
  const CAPE = api.registerCosmetic("guild_cape", {
    category: "back", display_name: "Guild cape", color: "#3a6a3a", unlocked: false,
    description: "Guild: complete three quests.",
    boxes: [
      { from: [-4.5, -12, 0.2], size: [9, 17, 0.8] },
      { from: [-4.5, 4, 0.2], size: [9, 1, 1.2], color: "#e8c040" },
      { from: [-1.5, -3, 1], size: [3, 3, 0.3], color: "#e8c040" },
    ],
  });

  // --- Prospector's Pick: a tool that levels up from the blocks it mines -------------------------
  // Built only from engine pieces: the block_broken event, item data (xp, level, name, lore) and
  // per-item stat modifiers. Each level mines 20% faster; level 3 adds a chance of double gold.
  const PICK_LEVELS = [5, 20, 60, 150];
  const pick = api.registerItem("prospector_pick", {
    display_name: "Prospector's Pick", icon: "textures/prospector_pick.png", durability: 500,
    tool: { type: "pickaxe", tier: 2, speed: 4 }, weapon: { damage: 3, cooldown: 0.5 },
    lore: ["Learns the rock as you mine it."],
  });
  api.registerRecipe({ "guild:gold_coin": 6, "base:stone_pickaxe": 1 }, "guild:prospector_pick");
  const pickLevel = (xp) => PICK_LEVELS.filter((needed) => xp >= needed).length;

  // --- Treasure goblin: engine AI plus a behaviour written in JavaScript --------------------------
  // It is skittish (the engine makes it flee from nearby players) and greedy: the custom "loot"
  // behaviour sends it after dropped gold coins, which it keeps until someone catches it.
  api.registerEntity("goblin", {
    kind: "mob", model: "models/goblin.glb", width: 0.5, height: 1.0, health: 12, speed: 4.2,
    ai: { preset: "passive", skittish: 7, intelligence: 0.9, agility: 0.8, group: "goblins", behaviors: ["guild:loot"] },
  });
  const nearestCoin = (mob) =>
    api.entities(mob.position, 14).find((e) => e.kind === "item" && e.item === ids.coin) ?? null;
  api.registerMobBehavior("loot", {
    score: (mob, ctx) => (ctx.behavior === "flee" ? 0 : nearestCoin(mob) ? 0.8 : 0),
    update: (mob) => {
      const coin = nearestCoin(mob);
      if (!coin) return;
      const here = mob.position;
      const at = coin.position;
      if (Math.hypot(here.x - at.x, here.z - at.z) < 1.2) {
        mob.setData("loot", mob.getData("loot", 0) + coin.count);
        coin.remove();
        api.playSound("guild:coin", here);
      } else {
        mob.moveTo(at, 1.2, 0.5);
      }
    },
  });
  api.on("entity_death", ({ entity }) => {
    if (entity.type !== "guild:goblin") return;
    const loot = entity.getData("loot", 0);
    api.dropItem(ids.coin, 2 + loot * 2, entity.position); // caught it: double the stolen coins
  });

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
          if (player.getData("completed", 0) >= 3 && !player.hasCosmetic(CAPE)) {
            player.grantCosmetic(CAPE);
            player.sendMessage("The Guild grants you its cape! Wear it from Esc > Customize avatar.");
          }
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

  api.on("block_broken", ({ player, block, item, slot, harvested, position }) => {
    progress(player, "broken");
    if (block === ids.goldOre) progress(player, "gold");
    if (item !== pick || !harvested) return;
    const stack = player.getItem(slot);
    if (stack.item !== pick) return; // it broke on this block
    const data = { ...stack.data, xp: (stack.data.xp ?? 0) + 1 };
    const level = pickLevel(data.xp);
    if (level > (stack.data.level ?? 0)) {
      player.showTitle("", `Prospector's Pick reached level ${level}`, 2);
      api.playSound("guild:coin", position, 1, 1.5);
    }
    if (level >= 3 && block === ids.goldOre && Math.random() < 0.25) api.dropItem(ids.coin, 1, position);
    data.level = level;
    data.name = level > 0 ? `Prospector's Pick +${level}` : "Prospector's Pick";
    data.modifiers = level > 0 ? [{ stat: "mining_speed", amount: 0.2 * level, op: "multiply" }] : [];
    const next = PICK_LEVELS[level];
    data.lore = [next ? `Experience ${data.xp} / ${next}` : `Experience ${data.xp} (max level)`];
    player.setItemData(slot, data);
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

  api.command("guild", "kit | meteor | top | coins | bounty | goblin - Adventurers' Guild", (player, args) => {
    const sub = args[0] ?? "";
    const cheat = sub === "meteor" || (sub === "kit" && !player.isCreative());
    if (cheat && !player.isAdmin()) {
      player.sendMessage(`Only admins can use /guild ${sub} here.`);
      return;
    }
    switch (sub) {
      case "kit":
        if (player.isCreative()) {
          player.setHotbar([ids.board, api.block("base:planks"), api.block("base:stone"), ids.goldOre, pick]);
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
        if (mob) {
          // An elite: tuned tougher and smarter than its kind, and it already knows who to hunt.
          mob.tune({ aggression: 0.9, intelligence: 0.9, agility: 0.4, chase_speed: 1.5 });
          mob.setTarget(player);
        }
        player.sendMessage(mob ? "An elite bounty monster appeared! Defeat it for 5 coins." : `No ${BOUNTY_MOB} on this server.`);
        break;
      }
      case "goblin": {
        if (!player.isAdmin()) {
          player.sendMessage("Only admins can release goblins.");
          break;
        }
        const here = player.position;
        api.spawnEntity("guild:goblin", { x: here.x + 5, y: here.y + 0.5, z: here.z });
        for (let i = 0; i < 3; i++) api.dropItem(ids.coin, 1, { x: here.x + 8 + i * 2, y: here.y + 1, z: here.z + 3 });
        player.sendMessage("A treasure goblin is after the coins! Catch it before it runs off.");
        break;
      }
      case "coins":
        player.sendMessage(`You carry ${coins(player)} gold coins.`);
        break;
      default:
        player.sendMessage("Usage: /guild kit | meteor | top | coins | bounty | goblin");
    }
  });
}
