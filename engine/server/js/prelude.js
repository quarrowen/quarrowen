// Quarrowen JavaScript mod API. Evaluated before a mod's main module.
//
// A mod is an ES module exporting `setup(api)`:
//
//   export function setup(api) {
//     const ruby = api.registerBlock("ruby_ore", { textures: "textures/ruby.png", light: 5 });
//     api.on("block_broken", (ev) => { if (ev.block === ruby) ev.player.showTitle("Shiny!"); });
//   }
//
// Every call crosses into the engine as JSON, so values are plain data: positions are {x, y, z},
// players are Player objects, block/item ids are numbers. Types: engine/server/js/quarrowen.d.ts.
"use strict";

(() => {
  const callbacks = new Map();
  let nextCallback = 1;

  const register = (fn) => {
    if (typeof fn !== "function") throw new TypeError("expected a function");
    const id = nextCallback++;
    callbacks.set(id, fn);
    return id;
  };

  const host = (method, ...args) => {
    const reply = JSON.parse(__host_call(method, JSON.stringify(args, toHost)));
    if (reply !== null && typeof reply === "object" && "__error" in reply) {
      throw new Error(`${method}: ${reply.__error}`);
    }
    return revive(reply?.value ?? null);
  };

  const format = (value) => {
    if (typeof value === "string") return value;
    if (value instanceof Error) return `${value.message}\n${value.stack ?? ""}`;
    try { return JSON.stringify(value, toHost) ?? String(value); } catch { return String(value); }
  };

  const toHost = (_key, value) =>
    value instanceof Player ? { __player: value.id } : value instanceof Entity ? { __entity: value.id } : value;

  const revive = (value) => {
    if (Array.isArray(value)) return value.map(revive);
    if (value !== null && typeof value === "object") {
      if ("__player" in value) return new Player(value.__player, value.name);
      if ("__entity" in value) return new Entity(value.__entity, value.type, value.kind, value.item, value.count);
      const out = {};
      for (const [k, v] of Object.entries(value)) out[k] = revive(v);
      return out;
    }
    return value;
  };

  class Player {
    constructor(id, name) {
      this.id = id;
      this.name = name;
    }
    get position() { return host("player.position", this.id); }
    get eyePosition() { return host("player.eyePosition", this.id); }
    get yaw() { return host("player.yaw", this.id); }
    get lookDirection() { return host("player.lookDirection", this.id); }
    get online() { return host("player.online", this.id); }
    /** Adds items, optionally with item data (wear, xp, custom name, lore, modifiers). */
    give(item, count = 1, data = {}) { return host("player.give", this.id, item, count, data); }
    /** Whether this many would fit. Refuse a sale rather than dropping paid-for goods on the floor. */
    hasRoom(item, count = 1) { return host("player.hasRoom", this.id, item, count); }
    hasPermission(permission) { return host("player.hasPermission", this.id, permission); }
    transferTo(server, arrival = "", data = {}) { return host("player.transferTo", this.id, server, arrival, data); }
    /** {item, count, data} in slot 0-35 (backpack) or an equipment slot index (see equipmentSlot). */
    getItem(slot) { return host("player.getItem", this.id, slot); }
    setItemData(slot, data) { host("player.setItemData", this.id, slot, data); }
    get selectedSlot() { return host("player.selectedSlot", this.id); }
    equipmentSlot(name) { return host("player.equipmentSlot", this.id, name); }
    damageItem(slot, amount = 1, reason = "use") { host("player.damageItem", this.id, slot, amount, reason); }
    get stats() { return host("player.stats", this.id); }
    getStat(name) { return host("player.getStat", this.id, name); }
    /** op "add" or "multiply" (0.2 = +20%); seconds 0 = until removed. */
    addModifier(id, stat, amount, op = "add", seconds = 0) { host("player.addModifier", this.id, id, stat, amount, op, seconds); }
    removeModifier(id) { host("player.removeModifier", this.id, id); }
    /** Teams share station trays and projects ("" = no team). */
    setTeam(name) { host("player.setTeam", this.id, String(name)); }
    knowsRecipe(id) { return host("player.knowsRecipe", this.id, id); }
    /** Teaches a recipe id ("mod:name"); returns true if it was new. */
    learnRecipe(id) { return host("player.learnRecipe", this.id, id); }
    /** Opens the guidebook at a page ("" = where they left off). */
    openGuide(page = "") { host("player.openGuide", this.id, page); }
    startTutorial(name) { return host("player.startTutorial", this.id, name); }
    stopTutorial() { host("player.stopTutorial", this.id); }
    /** Completes the current tutorial step (for "manual" goals). */
    advanceTutorial() { host("player.advanceTutorial", this.id); }
    tutorialState() { return host("player.tutorialState", this.id); }
    showTip(name) { return host("player.showTip", this.id, name); }
    /** Flags unlock guide pages with unlock: {flag}. Saved per player. */
    setGuideFlag(flag, on = true) { host("player.setGuideFlag", this.id, flag, on); }
    hasGuideFlag(flag) { return host("player.hasGuideFlag", this.id, flag); }
    unlockGuidePage(page, notify = true) { return host("player.unlockGuidePage", this.id, page, notify); }
    team() { return host("player.team", this.id); }
    /** Server cosmetics: names without a ":" are this mod's. */
    grantCosmetic(name) { host("player.grantCosmetic", this.id, name); }
    revokeCosmetic(name) { host("player.revokeCosmetic", this.id, name); }
    hasCosmetic(name) { return host("player.hasCosmetic", this.id, name); }
    cosmetics() { return host("player.cosmetics", this.id); }
    /** The look others see: {skin, body, wear: {category: {id, color}}, show_armor}. */
    avatar() { return host("player.avatar", this.id); }
    /** Avatar data laid over this player's look (team uniforms, disguises); {} clears. */
    setAvatarOverride(values) { host("player.setAvatarOverride", this.id, values); }
    refreshStats() { host("player.refreshStats", this.id); }
    take(item, count = 1) { return host("player.take", this.id, item, count); }
    countOf(item) { return host("player.countOf", this.id, item); }
    teleport(position) { host("player.teleport", this.id, position); }
    sendMessage(text) { host("player.sendMessage", this.id, String(text)); }
    showTitle(text, subtitle = "", seconds = 3) { host("player.showTitle", this.id, String(text), String(subtitle), seconds); }
    showUi(id, spec) { host("player.showUi", this.id, id, spec); }
    hideUi(id) { host("player.hideUi", this.id, id); }
    isCreative() { return host("player.isCreative", this.id); }
    isAdmin() { return host("player.isAdmin", this.id); }
    setCreative(enabled) { host("player.setCreative", this.id, !!enabled); }
    setHotbar(items) { host("player.setHotbar", this.id, items); }
    /** Persistent per-player data, namespaced to this mod. */
    getData(key, fallback = null) { return host("player.getData", this.id, key, fallback); }
    setData(key, value) { host("player.setData", this.id, key, value); }
    kick(reason) { host("player.kick", this.id, reason); }
    get health() { return host("player.health", this.id); }
    get maxHealth() { return host("player.maxHealth", this.id); }
    get dead() { return host("player.isDead", this.id); }
    setHealth(value) { host("player.setHealth", this.id, value); }
    heal(amount) { host("player.heal", this.id, amount); }
    damage(amount, cause = "magic", attacker = null) { return host("player.damage", this.id, amount, cause, attacker); }
    /** A sound only this player hears (not positioned). */
    playSound(name, volume = 1, pitch = 1) { host("player.playSound", this.id, name, volume, pitch); }
    drop(item, count = 1) { host("player.drop", this.id, item, count); }
    push(impulse) { host("player.push", this.id, impulse); }
    /** Where the player respawns; null restores the game's default. */
    setSpawnPoint(position) { host("player.setSpawnPoint", this.id, position); }
  }

  class Entity {
    constructor(id, type, kind, item, count) {
      this.id = id;
      this.type = type;
      this.kind = kind;
      this.item = item;
      this.count = count;
    }
    get alive() { return host("entity.alive", this); }
    get position() { return host("entity.position", this); }
    set position(value) { host("entity.setPosition", this, value); }
    get velocity() { return host("entity.velocity", this); }
    set velocity(value) { host("entity.setVelocity", this, value); }
    get health() { return host("entity.health", this); }
    get maxHealth() { return host("entity.maxHealth", this); }
    push(impulse) { host("entity.push", this, impulse); }
    damage(amount, attacker = null, cause = "magic") { return host("entity.damage", this, amount, attacker, cause); }
    heal(amount) { host("entity.heal", this, amount); }
    remove() { host("entity.remove", this); }
    /** Walk toward a position (mobs); null resumes normal behaviour. */
    setGoal(position) { host("entity.setGoal", this, position); }
    getData(key, fallback = null) { return host("entity.getData", this, key, fallback); }
    setData(key, value) { host("entity.setData", this, key, value); }
    // Mob AI
    get target() { return host("entity.target", this); }
    /** Attack this player or entity now (null forgets the current target). */
    setTarget(target) { host("entity.setTarget", this, target); }
    addThreat(source, amount) { host("entity.addThreat", this, source, amount); }
    /** Override AI settings for this mob only (aggression, attacks, phases, ...). */
    tune(values) { host("entity.tune", this, values); }
    alert(position) { host("entity.alert", this, position); }
    setHome(position, leash = -1) { host("entity.setHome", this, position, leash); }
    /** Start a named attack against the current target now. */
    attack(name) { return host("entity.attack", this, name); }
    get behavior() { return host("entity.behavior", this); }
    moveTo(position, speed = 1, radius = 0.8) { host("entity.moveTo", this, position, speed, radius); }
    stop() { host("entity.stop", this); }
    lookAt(position) { host("entity.lookAt", this, position); }
  }

  const api = {
    Player,
    Entity,
    info: (...parts) => host("info", parts.map(format).join(" ")),
    /** Log levels: debug lines appear with `/log level <mod> debug`; errors are grouped and shown to admins. */
    debug: (...parts) => host("debug", parts.map(format).join(" ")),
    warn: (...parts) => host("warn", parts.map(format).join(" ")),
    error: (...parts) => host("error", parts.map(format).join(" "), new Error().stack ?? ""),
    // Content
    registerBlock: (name, def) => host("registerBlock", name, def),
    registerItem: (name, def) => host("registerItem", name, def),
    /** options: {station: "crafting_table"} to require a station block. */
    registerRecipe: (inputs, output, count = 1, options = {}) => host("registerRecipe", inputs, output, count, options),
    /** {title, groups: [{name, count, columns, label, take_only, accepts: [items] | "fuel"}], progress: [{name, label, color}]} */
    registerContainer: (name, def) => host("registerContainer", name, def),
    /** {title, tiers: [{block, title, kit, grants}], workshop: {radius, upgrades: [{block, title, max, grants}]},
     *  multiblock: {core, pattern, legend, title}, grants}; grants {features, tier, speed, quality, pull_radius, hints} */
    registerStation: (name, def) => host("registerStation", name, def),
    /** A crafting minigame recipes and assemblies name as `skill`: {title, type: "timing" | "hold" | "sequence", verb,
     *  rounds, speed, zone, cool, team, duration, window}. */
    registerMinigame: (name, def) => host("registerMinigame", name, def),
    /** Tools from parts: materials {display_name, item, color, tier, speed, durability, damage, handle, trait},
     *  part types {display_name, sprite, cost, station}, assemblies {display_name, icon, slots, tool_type, damage, cooldown, sweep, station}. */
    registerMaterial: (name, def) => host("registerMaterial", name, def),
    registerPartType: (name, def) => host("registerPartType", name, def),
    registerAssembly: (name, def) => host("registerAssembly", name, def),
    getStation: (position) => host("getStation", position),
    openContainer: (player, position) => host("openContainer", player, position),
    /** [{item, count, data}] per slot. */
    containerItems: (position) => host("containerItems", position),
    setContainerItem: (position, slot, item, count, data = {}) => host("setContainerItem", position, slot, item, count, data),
    /** Returns how many did not fit. */
    addToContainer: (position, item, count, data = {}, group = "") => host("addToContainer", position, item, count, data, group),
    containerState: (position) => host("containerState", position),
    setContainerState: (position, state) => host("setContainerState", position, state),
    setContainerProgress: (position, bar, value) => host("setContainerProgress", position, bar, value),
    setFuel: (item, seconds) => host("setFuel", item, seconds),
    getFuel: (item) => host("getFuel", item),
    registerProcess: (kind, input, output, count = 1, seconds = 10) => host("registerProcess", kind, input, output, count, seconds),
    getProcess: (kind, item) => host("getProcess", kind, item),
    block: (name) => host("block", name),
    item: (name) => host("item", name),
    itemName: (id) => host("itemName", id),
    itemDisplayName: (id) => host("itemDisplayName", id),
    blockName: (id) => host("blockName", id),
    isSolid: (id) => host("isSolid", id),
    getDrops: (id) => host("getDrops", id),
    addOrePass: (def) => host("addOrePass", def),
    // World
    getBlock: (pos) => host("getBlock", pos),
    getLoadedBlock: (pos) => host("getLoadedBlock", pos),
    setBlock: (pos, id, { keepData = false, state = 0 } = {}) => host("setBlock", pos, id, keepData, state),
    fill: (from, to, id) => host("fill", from, to, id),
    getBlockState: (pos) => host("getBlockState", pos),
    getBlockData: (pos) => host("getBlockData", pos),
    setBlockData: (pos, data) => host("setBlockData", pos, data),
    clearBlockData: (pos) => host("clearBlockData", pos),
    findBlockData: (block = -1) => host("findBlockData", block),
    surfaceY: (x, z) => host("surfaceY", x, z),
    seesSky: (pos) => host("seesSky", pos),
    setPhysics: (values) => host("setPhysics", values),
    setWorldTime: (timeOfDay, dayLength = -1) => host("setWorldTime", timeOfDay, dayLength),
    timeOfDay: () => host("timeOfDay"),
    daylight: () => host("daylight"),
    facingFromYaw: (yaw) => host("facingFromYaw", yaw),
    // Players & server
    players: () => host("players"),
    findPlayer: (name) => host("findPlayer", name),
    broadcast: (text) => host("broadcast", String(text)),
    setServerInfo: (values) => host("setServerInfo", values),
    showCrafting: (player) => host("showCrafting", player),
    // Entities, sounds & gameplay
    registerEntity: (name, def) => host("registerEntity", name, def),
    registerSound: (name, files, options = {}) => host("registerSound", name, files, options),
    playSound: (name, position, volume = 1, pitch = 1) => host("playSound", name, position, volume, pitch),
    spawnEntity: (type, position, options = {}) => host("spawnEntity", type, position, options),
    spawnProjectile: (type, from, velocity, owner = null) => host("spawnProjectile", type, from, velocity, owner),
    dropItem: (item, count, position) => host("dropItem", item, count, position),
    entities: (center, radius, type = "") => host("entities", center, radius, type),
    addSpawnRule: (rule) => host("addSpawnRule", rule),
    /** Makes this game's world from registered biomes: options {sea_level, snow_level}. */
    useBiomeGenerator: (options = {}) => host("useBiomeGenerator", options),
    registerBiome: (name, def) => host("registerBiome", name, def),
    registerFeature: (name, def) => host("registerFeature", name, def),
    /** Structures: a template file in the mod (saved with /struct save) or template data, structure sets, loot tables. */
    registerStructureTemplate: (name, source) => host("registerStructureTemplate", name, source),
    registerStructure: (name, def) => host("registerStructure", name, def),
    registerLootTable: (name, def) => host("registerLoot", name, def),
    /** Loot: what a mob, block, chest or reward gives. Pools roll on their own; an entry is an item, another table, or empty. */
    registerLoot: (name, def) => host("registerLoot", name, def),
    /** More ways of saying somebody died, for a cause or for one of your own mobs. "%s" is the player, a second "%s" is what did it. */
    addDeathMessages: (key, lines) => host("addDeathMessages", key, lines),
    extendLoot: (name, def) => host("extendLoot", name, def),
    rollLoot: (name, context = {}) => host("rollLoot", name, context),
    lootSources: (item) => host("lootSources", item),
    setLootRate: (multiplier) => host("setLootRate", multiplier),
    setLootBoost: (target, factor, seconds = 0) => host("setLootBoost", target, factor, seconds),
    /** Guidebook: chapters and pages of blocks (text, heading, items, recipe, entity, image, tip, link, keys). */
    /** Debug drawing, shown to admins with the dev overlay's Draw toggle on (F8). Shapes expire after `seconds`. */
    draw: {
      box: (min, max, color = "#ffcc00", seconds = 2, label = "") => {
        host("debugDraw", { type: "box", min, max, color, seconds });
        if (label) host("debugDraw", { type: "text", position: { x: (min.x + max.x) / 2, y: Math.max(min.y, max.y) + 0.3, z: (min.z + max.z) / 2 }, text: label, color, seconds });
      },
      line: (from, to, color = "#ffcc00", seconds = 2) => host("debugDraw", { type: "line", from, to, color, seconds }),
      text: (position, text, color = "#ffffff", seconds = 2) => host("debugDraw", { type: "text", position, text: String(text), color, seconds }),
      path: (points, color = "#60ff90", seconds = 2) => host("debugDraw", { type: "path", points, color, seconds }),
      sphere: (center, radius = 0.5, color = "#6090ff", seconds = 2) => host("debugDraw", { type: "sphere", center, radius, color, seconds }),
    },
    /** Player creations (skins, accessories, models): policy {enabled, accept, kinds, library, max_per_player,
     *  max_bytes_per_player, report_hide}, review lists and moderation. */
    setUgcPolicy: (values) => host("setUgcPolicy", values),
    ugcList: (filter = "approved") => host("ugcList", filter),
    networkServers: () => host("networkServers"),
    /** Is this mod the game being played, or is another game using it as a foundation? Guard anything
     *  that speaks for the whole game - a welcome, a corner panel - with this. */
    /** Registers a music track. `attribution` is required - say who made it and under what licence,
     *  because running a server means redistributing it. The file is fetched lazily, so it never
     *  delays a join. options: {attribution (required), volume, loop}. */
    registerMusic: (name, file, options = {}) => host("registerMusic", name, file, options),
    /** Starts a track for one player, or everybody when player is null. Asking for the track already
     *  playing does nothing, so this is safe to call on every biome or time change.
     *  options: {fade, restart}. */
    playMusic: (player, name, options = {}) => host("playMusic", player, name, options),
    /** Fades the music out for one player, or everybody when player is null. options: {fade}. */
    stopMusic: (player, options = {}) => host("stopMusic", player, options),
    isGame: () => host("isGame"),
    /** Is this block id a liquid? */
    isLiquid: (block) => host("isLiquid", block),
    /** What a ray hits: {hit, position, normal, block}. By default it looks through water the way a
     *  player's crosshair does; pass {liquids: true} when the water itself is the target. */
    raycast: (origin, direction, maxDistance = 5, options = {}) =>
      host("raycast", origin, direction, maxDistance, options),
    /** The id of the game being played, whichever mod this is. */
    gameId: () => host("gameId"),
    registerPermission: (permission, description, roles = []) => host("registerPermission", permission, description, roles),
    playerRoles: (playerId) => host("playerRoles", playerId),
    setPlayerRole: (playerId, role, on = true) => host("setPlayerRole", playerId, role, on),
    setArrivalPoint: (id, position) => host("setArrivalPoint", id, position),
    ugcGet: (id) => host("ugcGet", id),
    ugcSetStatus: (id, status, reason = "") => host("ugcSetStatus", id, status, reason),
    ugcTrust: (playerId, on = true) => host("ugcTrust", playerId, on),
    ugcBan: (playerId, on = true, reason = "") => host("ugcBan", playerId, on, reason),
    registerGuideChapter: (name, def = {}) => host("registerGuideChapter", name, def),
    registerGuidePage: (name, def) => host("registerGuidePage", name, def),
    /** Tutorials (steps with goals completed by real actions) and one-time contextual tips. */
    registerTutorial: (name, def) => host("registerTutorial", name, def),
    registerTip: (name, def) => host("registerTip", name, def),
    /** A milestone: a tutorial-shaped goal counted for the life of the world, paid out once. */
    registerMilestone: (name, def) => host("registerMilestone", name, def),
    getBiome: (position) => host("getBiome", position),
    /** Mobs of each spawn category allowed around each player: { monster, animal, ambient, misc }. */
    setSpawnCaps: (caps) => host("setSpawnCaps", caps),
    setGameplay: (values) => host("setGameplay", values),
    getGameplay: (rule) => host("getGameplay", rule),
    makeNoise: (position, radius, source = null) => host("makeNoise", position, radius, source),
    registerEquipmentSlot: (name, def = {}) => host("registerEquipmentSlot", name, def),
    registerStat: (name, base) => host("registerStat", name, base),
    /** A cosmetic players can wear here; see CosmeticDef. Returns the full name or "". */
    registerCosmetic: (name, def) => host("registerCosmetic", name, def),
    registerCosmeticCategory: (name, def = {}) => host("registerCosmeticCategory", name, def),
    /** {allow_builtin, allow_colors, armor: "player" | "armor" | "cosmetics", blocked, uniform} */
    setCosmeticsPolicy: (values) => host("setCosmeticsPolicy", values),
    /** Particles, light flash, shake and sound as data; see EffectDef. Returns the id or -1. */
    registerEffect: (name, def) => host("registerEffect", name, def),
    /** handler(ctx) with ctx {position, block, state, ticks, reason: "random" | "scheduled", payload};
     *  options {interval: seconds (default 30), catch_up: true}. */
    registerBlockTick: (block, handler, options = {}) => host("registerBlockTick", block, register(handler), options),
    scheduleBlockTick: (position, seconds, payload = {}) => host("scheduleBlockTick", position, seconds, payload),
    /** 0-15: block light or daylight-scaled sky light (estimate). */
    getLight: (position) => host("getLight", position),
    getLightLevels: (position) => host("getLightLevels", position),
    worldClock: () => host("worldClock"),
    breakBlock: (position, drop = true) => host("breakBlock", position, drop),
    /** options: {color, scale, direction: {x,y,z} | [x,y,z], duration, follow: entity | player} */
    playEffect: (name, position, options = {}) => host("playEffect", name, position, options),
    /** An explosion: power ~3 is a mob blast. options: { source, break_blocks, drop_chance, damage, effect, sound }. */
    explode: (position, power, options = {}) => host("explode", position, power, options),
    /** A mob behaviour for mobs listing it in ai.behaviors. score(mob, ctx) -> number each think;
     *  update(mob, ctx) while it runs. ctx: {target, can_see_target, target_distance, health, behavior, arrived}. */
    registerMobBehavior: (name, { score, update, stop } = {}) =>
      host("registerMobBehavior", name, register(score), register(update), stop ? register(stop) : -1),
    // Events, commands, timers
    on: (event, handler, priority = 0) => host("on", event, register(handler), priority),
    /** Where a player who has never played here starts: handler(playerId) -> {x, y, z}. Runs before the
     *  world around it loads, so it is also where to build what they should open their eyes on. */
    setSpawnHandler: (handler) => host("setSpawnHandler", register(handler)),
    /** Where a returning player comes back to: handler(playerId, saved) -> {x, y, z}, or nothing to
     *  leave them where they logged out. A different question from setSpawnHandler - a lobby wants
     *  everybody in the lobby every time, a story wants only the first arrival placed. */
    setRejoinHandler: (handler) => host("setRejoinHandler", register(handler)),
    command: (name, description, handler, { admin = false } = {}) =>
      host("command", name, description, register(handler), admin ? "admin" : ""),
    after: (seconds, fn) => host("after", seconds, register(fn)),
    every: (seconds, fn) => host("every", seconds, register(fn)),
    cancel: (taskId) => host("cancel", taskId),
    // Persistent per-mod storage, saved with the world
    storage: {
      get: (key, fallback = null) => host("storageGet", key, fallback),
      set: (key, value) => host("storageSet", key, value),
    },
  };

  globalThis.console = {
    log: (...parts) => api.info(...parts),
    info: (...parts) => api.info(...parts),
    debug: (...parts) => api.debug(...parts),
    warn: (...parts) => api.warn(...parts),
    error: (...parts) => api.error(...parts),
  };

  globalThis.__setup = (_json) => {
    const exports = globalThis.__exports ?? {};
    const setup = exports.setup ?? exports.default;
    if (typeof setup !== "function") throw new Error("a JavaScript mod must export function setup(api)");
    try {
      setup(api);
    } catch (e) {
      return JSON.stringify({ __error: String(e?.message ?? e), stack: String(e?.stack ?? "") });
    }
    return "null";
  };

  // Engine -> script: invokes a registered callback. Events are plain objects; the fields handlers
  // may change (cancelled, drops, amount, damage, keep_inventory, keep, message, position) are sent back.
  globalThis.__dispatch = (json) => {
    const { id, args } = JSON.parse(json);
    const fn = callbacks.get(id);
    if (!fn) return JSON.stringify({ value: null });
    const revived = revive(args);
    let result;
    try {
      result = fn(...revived);
    } catch (e) {
      return JSON.stringify({ __error: String(e?.message ?? e), stack: String(e?.stack ?? "") });
    }
    const first = revived[0];
    const event = first !== null && typeof first === "object" && !(first instanceof Player) && !Array.isArray(first)
      ? { cancelled: first.cancelled, drops: first.drops, amount: first.amount, damage: first.damage,
          keep_inventory: first.keep_inventory, keep: first.keep, message: first.message, position: first.position,
          stats: first.stats }
      : null;
    return JSON.stringify({ value: result ?? null, event }, toHost);
  };
})();
