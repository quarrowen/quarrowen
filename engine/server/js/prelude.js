// VoxelCraft JavaScript mod API. Evaluated before a mod's main module.
//
// A mod is an ES module exporting `setup(api)`:
//
//   export function setup(api) {
//     const ruby = api.registerBlock("ruby_ore", { textures: "textures/ruby.png", light: 5 });
//     api.on("block_broken", (ev) => { if (ev.block === ruby) ev.player.showTitle("Shiny!"); });
//   }
//
// Every call crosses into the engine as JSON, so values are plain data: positions are {x, y, z},
// players are Player objects, block/item ids are numbers. Types: engine/server/js/voxelcraft.d.ts.
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
    info: (...parts) => host("info", parts.map(String).join(" ")),
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
    /** A mob behaviour for mobs listing it in ai.behaviors. score(mob, ctx) -> number each think;
     *  update(mob, ctx) while it runs. ctx: {target, can_see_target, target_distance, health, behavior, arrived}. */
    registerMobBehavior: (name, { score, update, stop } = {}) =>
      host("registerMobBehavior", name, register(score), register(update), stop ? register(stop) : -1),
    // Events, commands, timers
    on: (event, handler, priority = 0) => host("on", event, register(handler), priority),
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
    warn: (...parts) => api.info("warning:", ...parts),
    error: (...parts) => api.info("error:", ...parts),
  };

  globalThis.__setup = (_json) => {
    const exports = globalThis.__exports ?? {};
    const setup = exports.setup ?? exports.default;
    if (typeof setup !== "function") throw new Error("a JavaScript mod must export function setup(api)");
    setup(api);
    return "null";
  };

  // Engine -> script: invokes a registered callback. Events are plain objects; the fields handlers
  // may change (cancelled, drops, amount, damage, keep_inventory, keep, message, position) are sent back.
  globalThis.__dispatch = (json) => {
    const { id, args } = JSON.parse(json);
    const fn = callbacks.get(id);
    if (!fn) return JSON.stringify({ value: null });
    const revived = revive(args);
    const result = fn(...revived);
    const first = revived[0];
    const event = first !== null && typeof first === "object" && !(first instanceof Player) && !Array.isArray(first)
      ? { cancelled: first.cancelled, drops: first.drops, amount: first.amount, damage: first.damage,
          keep_inventory: first.keep_inventory, keep: first.keep, message: first.message, position: first.position,
          stats: first.stats }
      : null;
    return JSON.stringify({ value: result ?? null, event }, toHost);
  };
})();
