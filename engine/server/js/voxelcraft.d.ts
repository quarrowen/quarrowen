// Type declarations for VoxelCraft JavaScript mods. Reference from a mod for editor autocomplete:
//   /// <reference path="../../engine/server/js/voxelcraft.d.ts" />
//   /** @param {import("voxelcraft").Api} api */
//   export function setup(api) { ... }
// or author in TypeScript and compile to main.js.

declare module "voxelcraft" {
  export interface Vec3 { x: number; y: number; z: number; }

  export type BlockId = number;
  /** Block ids (1-65534) double as their items; other items start at 65536. */
  export type ItemId = number;

  export interface BlockDef {
    display_name?: string;
    /** One texture for all faces, or per-face paths relative to the mod folder. */
    textures?: string | { all?: string; side?: string; top?: string; bottom?: string } | string[];
    render?: "opaque" | "cutout" | "translucent" | "invisible" | "model";
    solid?: boolean;
    liquid?: boolean;
    breakable?: boolean;
    placeable?: boolean;
    /** Light emitted, 0-15. */
    light?: number;
    /** Right-click fires block_interact instead of placing. */
    interactive?: boolean;
    /** glTF (.glb) model path; the block renders as that model. */
    model?: string;
    orientation?: "none" | "horizontal";
    connect_group?: string;
    model_arm?: string;
    sway?: boolean;
    /** Item name dropped when broken, "" for nothing, or [[itemId, count], ...]. */
    drops?: string | [ItemId, number][];
    /** Sound names ("base:stone", or this mod's) for breaking, placing and walking on the block. */
    sounds?: { break?: string; place?: string; step?: string };
    /** Mining: seconds by hand ~ hardness * 1.5; tier of tool needed for drops; effective tool type. */
    hardness?: number; tier?: number; tool?: string;
    hazard?: boolean;
  }

  export interface StatModifier { stat: string; amount: number; op?: "add" | "multiply" }

  export interface ItemDef {
    display_name?: string; icon?: string; max_stack?: number; usable?: boolean;
    /** Uses before it breaks (0 = never). Wear is item data `damage`. */
    durability?: number;
    tool?: { type: string; tier?: number; speed?: number };
    weapon?: { damage?: number; cooldown?: number; reach?: number; crit_chance?: number; knockback?: number; sweep?: number };
    /** Hold use to eat: hunger points (20 = full), saturation, eat_time seconds, always (edible when full), heal,
     *  remainder item, crumb color, effects (timed stat modifiers with a chance). */
    food?: { hunger: number; saturation?: number; eat_time?: number; always?: boolean; heal?: number; remainder?: string; color?: string;
      effects?: { stat: string; amount: number; op?: "add" | "multiply"; seconds?: number; chance?: number; message?: string }[] };
    armor?: { armor?: number; toughness?: number; knockback_resistance?: number };
    equip_slot?: string;
    modifiers?: StatModifier[];
    model?: string;
    lore?: string[];
    /** Emissive glow when held or worn; light = radius in blocks. Item data may override glow, trail and effects. */
    glow?: { color?: string; energy?: number; light?: number };
    /** Ribbon behind the item while swinging. */
    trail?: { color?: string; width?: number; seconds?: number };
    /** Effect names: swing, hit (at the target), use, held (continuous), break. */
    effects?: { swing?: string; hit?: string; use?: string; held?: string; break?: string };
    /** Legacy shorthand for weapon.damage. */
    attack_damage?: number;
  }

  /** Colors are "#rrggbb". An empty id in overrides and uniforms takes a category off. */
  export interface Avatar {
    skin?: string;
    body?: { head?: string; torso?: string; arms?: string; legs?: string };
    wear?: Record<string, { id: string; color?: string }>;
    show_armor?: { head?: boolean; chest?: boolean; legs?: boolean; feet?: boolean };
  }

  /** A cosmetic, drawn from data (see engine/shared/cosmetics.gd). Regions use the 64x64 skin layout;
   *  boxes are in skin pixels at the category's attachment point (+y up, -z forward). */
  export interface CosmeticDef {
    category: "face" | "pants" | "shoes" | "shirt" | "jacket" | "hair" | "hat" | "glasses" | "back" | string;
    display_name?: string; description?: string;
    /** Default tint; paint/boxes/pixels without a color use the tint. */
    color?: string; tint?: boolean;
    paint?: { region: string; rows?: [number, number]; sides?: ("front" | "back" | "left" | "right" | "top" | "bottom")[]; color?: string; shade?: number }[];
    pixels?: { rows: string[]; palette?: Record<string, string> };
    boxes?: { from: Vec3Array; size: Vec3Array; color?: string; shade?: number }[];
    texture?: string; model?: string;
    model_transform?: { position?: Vec3Array; rotation?: Vec3Array; scale?: number };
    /** Armor slots it replaces when shown (hats: ["head"]). */
    covers?: ("head" | "chest" | "legs" | "feet")[];
    /** false: only players granted it may wear it. */
    unlocked?: boolean;
  }
  export type Vec3Array = [number, number, number];
  export interface StationGrants { features?: string[]; tier?: number; speed?: number; quality?: number; pull_radius?: number; hints?: number }
  export interface StationDef {
    title?: string; grants?: StationGrants;
    tiers?: { block: string; title?: string; kit?: string; grants?: StationGrants }[];
    workshop?: { radius?: number; upgrades: { block: string; title?: string; max?: number; grants?: StationGrants }[] };
    /** Layers bottom to top, rows separated by "|"; "C" core, "." any block, " " air. */
    multiblock?: { core: string; pattern: string[]; legend: Record<string, string>; title?: string };
  }

  /** See engine/shared/effect_registry.gd. Colors "#rrggbb" or "#rrggbbaa". */
  export interface EffectDef {
    emitters?: {
      amount?: number; burst?: boolean; lifetime?: number; speed?: [number, number]; direction?: Vec3Array;
      spread?: number; gravity?: number; drag?: number; size?: [number, number]; colors?: string[];
      shape?: "point" | "sphere" | "box"; radius?: number; extents?: Vec3Array;
      texture?: "soft" | "spark" | "star" | "square" | string; blend?: "add" | "mix";
    }[];
    light?: { color?: string; energy?: number; range?: number; seconds?: number };
    shake?: { strength?: number; seconds?: number; radius?: number };
    sound?: string;
    /** Seconds continuous emitters run (0 = one burst, -1 = until stopped). */
    duration?: number;
    range?: number;
  }
  export interface EffectOptions { color?: string; scale?: number; direction?: Vec3 | Vec3Array; duration?: number; follow?: Entity | Player }

  /** Per-item data (engine keys; mods add their own). */
  export interface ItemData { damage?: number; name?: string; lore?: string[]; modifiers?: StatModifier[]; glow?: ItemDef["glow"]; trail?: ItemDef["trail"]; effects?: ItemDef["effects"]; [key: string]: unknown }
  export interface ItemStack { item: ItemId; count: number; data: ItemData }

  export interface EntityDef {
    display_name?: string;
    kind?: "mob" | "projectile" | "object";
    /** glTF model; parts named leg_a/leg_b/arm_a/arm_b swing while walking. Faces -Z. */
    model?: string;
    /** Billboard texture when there is no model (projectiles). */
    sprite?: string;
    glow?: boolean;
    width?: number; height?: number; scale?: number;
    health?: number; speed?: number; gravity?: number; drag?: number; knockback_resistance?: number;
    ai?: MobAi["preset"] | MobAi;
    /** Projectile damage on hit. */
    damage?: number;
    lifetime?: number;
    /** [[item name, count, chance?], ...] dropped on death. */
    drops?: [string, number, number?][];
    sounds?: { hurt?: string; death?: string; ambient?: string; attack?: string };
    /** Saved with the world (otherwise despawns when no player is near). */
    persistent?: boolean;
  }

  export interface SpawnRule {
    entity: string; time?: "night" | "day" | "any"; on?: string[];
    category?: "monster" | "animal" | "ambient" | "misc"; light?: [number, number]; place?: "any" | "surface" | "underground";
    group?: [number, number]; biomes?: string[];
    max_nearby?: number; max_total?: number; chance?: number; min_distance?: number; max_distance?: number;
  }

  export interface Gameplay {
    item_drops?: "entity" | "inventory"; keep_inventory?: boolean; pvp?: boolean;
    fall_damage?: boolean; natural_regeneration?: boolean; mob_spawning?: boolean;
  }

  export class Entity {
    readonly id: number;
    readonly type: string;
    readonly kind: string;
    /** Dropped item stacks: the item and count. */
    readonly item: ItemId;
    readonly count: number;
    readonly alive: boolean;
    position: Vec3;
    velocity: Vec3;
    readonly health: number;
    readonly maxHealth: number;
    push(impulse: Vec3): void;
    damage(amount: number, attacker?: Player | Entity | null, cause?: string): boolean;
    heal(amount: number): void;
    remove(): void;
    setGoal(position: Vec3 | null): void;
    getData<T = unknown>(key: string, fallback?: T): T;
    setData(key: string, value: unknown): void;
    readonly target: Player | Entity | null;
    setTarget(target: Player | Entity | null): void;
    addThreat(source: Player | Entity, amount: number): void;
    tune(values: MobAi): void;
    alert(position: Vec3): void;
    setHome(position: Vec3, leash?: number): void;
    attack(name: string): boolean;
    readonly behavior: string;
    moveTo(position: Vec3, speed?: number, radius?: number): void;
    stop(): void;
    lookAt(position: Vec3): void;
  }

  export interface MobAttack {
    name?: string;
    type?: "melee" | "ranged" | "leap" | "charge" | "slam" | "summon" | "custom";
    damage?: number; range?: number; min_range?: number; cooldown?: number; windup?: number; recovery?: number;
    knockback?: number; weight?: number; arc?: number; radius?: number;
    projectile?: string; projectile_speed?: number; spread?: number; count?: number;
    entity?: string; max_summons?: number; speed?: number; duration?: number;
    health_below?: number; health_above?: number; sound?: string;
    /** Full effect names: during the wind-up (follows the mob) and when the attack lands. */
    windup_effect?: string; effect?: string;
  }

  /** Engine mob AI settings; see engine/server/ai/mob_config.gd. */
  export interface MobAi {
    preset?: "hostile" | "neutral" | "passive" | "archer" | "boss" | "wander" | "none";
    temperament?: "hostile" | "neutral" | "passive" | "none";
    aggression?: number; courage?: number; intelligence?: number; agility?: number;
    sight_range?: number; fov?: number; hearing_range?: number; memory?: number; reaction_time?: number;
    group?: string; enemy_groups?: string[]; alert_radius?: number; chase_speed?: number;
    wander_speed?: number; wander_radius?: number; preferred_range?: [number, number]; skittish?: number;
    leash?: number; reset_on_leash?: boolean; regen?: number; step_up?: number; max_drop?: number; can_swim?: boolean;
    attack_interval?: number; attacks?: MobAttack[];
    phases?: { health_below: number; message?: string; speed_multiplier?: number; aggression?: number; attacks?: MobAttack[]; add_attacks?: MobAttack[] }[];
    boss?: { name?: string; bar_range?: number };
    behaviors?: string[];
  }

  export interface MobContext {
    target: Player | Entity | null; can_see_target: boolean; target_distance: number;
    health: number; behavior: string; arrived: boolean;
  }

  export interface OrePassDef {
    ore: string; replace?: string; veins?: number; size?: number; min_y?: number; max_y?: number; chance?: number;
  }

  export type UiElement =
    | { type: "label"; text: string; size?: number; color?: string }
    | { type: "button"; text: string; action: string; disabled?: boolean }
    | { type: "progress"; value: number; max: number }
    | { type: "image"; asset: string; size?: number }
    | { type: "vbox" | "hbox"; children: UiElement[] }
    | { type: "spacer"; size?: number };

  export interface UiSpec {
    anchor?: "top_left" | "top_right" | "bottom_left" | "bottom_right" | "center" | "center_top" | "center_left" | "center_right";
    modal?: boolean;
    children: UiElement[];
  }

  export class Player {
    readonly id: number;
    readonly name: string;
    readonly position: Vec3;
    readonly eyePosition: Vec3;
    readonly yaw: number;
    readonly lookDirection: Vec3;
    readonly online: boolean;
    give(item: ItemId, count?: number, data?: ItemData): number;
    getItem(slot: number): ItemStack;
    setItemData(slot: number, data: ItemData): void;
    readonly selectedSlot: number;
    equipmentSlot(name: string): number;
    damageItem(slot: number, amount?: number, reason?: string): void;
    readonly stats: Record<string, number>;
    getStat(name: string): number;
    addModifier(id: string, stat: string, amount: number, op?: "add" | "multiply", seconds?: number): void;
    removeModifier(id: string): void;
    setTeam(name: string): void;
    knowsRecipe(id: string): boolean;
    learnRecipe(id: string): boolean;
    openGuide(page?: string): void;
    startTutorial(name: string): boolean;
    stopTutorial(): void;
    advanceTutorial(): void;
    tutorialState(): { active: string; step: number; progress: number; done: string[] };
    showTip(name: string): boolean;
    setGuideFlag(flag: string, on?: boolean): void;
    hasGuideFlag(flag: string): boolean;
    unlockGuidePage(page: string, notify?: boolean): boolean;
    team(): string;
    grantCosmetic(name: string): void;
    revokeCosmetic(name: string): void;
    hasCosmetic(name: string): boolean;
    cosmetics(): string[];
    avatar(): Avatar;
    setAvatarOverride(values: Avatar): void;
    refreshStats(): void;
    take(item: ItemId, count?: number): boolean;
    countOf(item: ItemId): number;
    teleport(position: Vec3): void;
    sendMessage(text: string): void;
    showTitle(text: string, subtitle?: string, seconds?: number): void;
    /** UI ids are namespaced to the mod automatically ("board" -> "guild:board"). */
    showUi(id: string, spec: UiSpec): void;
    hideUi(id: string): void;
    isCreative(): boolean;
    isAdmin(): boolean;
    setCreative(enabled: boolean): void;
    setHotbar(items: ItemId[]): void;
    getData<T = unknown>(key: string, fallback?: T): T;
    setData(key: string, value: unknown): void;
    kick(reason: string): void;
    readonly health: number;
    readonly maxHealth: number;
    readonly dead: boolean;
    setHealth(value: number): void;
    heal(amount: number): void;
    damage(amount: number, cause?: string, attacker?: Player | Entity | null): boolean;
    playSound(name: string, volume?: number, pitch?: number): void;
    drop(item: ItemId, count?: number): void;
    push(impulse: Vec3): void;
    setSpawnPoint(position: Vec3 | null): void;
  }

  export interface Events {
    player_join: { player: Player; first_time: boolean };
    player_leave: { player: Player };
    tick: { delta: number; tick: number };
    block_break: { player: Player; position: Vec3; block: BlockId; drops: [ItemId, number][]; cancelled: boolean };
    block_broken: { player: Player; position: Vec3; block: BlockId; item: ItemId; slot: number; harvested: boolean };
    block_destroyed: { position: Vec3; block: BlockId; drops: [ItemId, number][] };
    block_place: { player: Player; position: Vec3; block: BlockId; cancelled: boolean };
    block_placed: { player: Player; position: Vec3; block: BlockId };
    block_interact: { player: Player; position: Vec3; block: BlockId; cancelled: boolean };
    container_open: { player: Player; position: Vec3; container: { position: Vec3; type: string; size: number }; cancelled: boolean };
    container_changed: { player: Player; position: Vec3; container: { position: Vec3; type: string; size: number }; slot: number };
    container_close: { player: Player; position: Vec3 };
    item_use: { player: Player; item: ItemId; has_target: boolean; position: Vec3; normal: Vec3; direction: Vec3 };
    item_crafted: { player: Player; item: ItemId; count: number };
    chat: { player: Player; text: string; cancelled: boolean };
    ui_action: { player: Player; ui_id: string; action: string };
    item_drop: { player: Player; item: ItemId; count: number; cancelled: boolean };
    item_pickup: { player: Player; entity: Entity; item: ItemId; count: number; cancelled: boolean };
    player_attack: { player: Player; target: Entity | Player; target_kind: "entity" | "player"; item: ItemId; slot: number; damage: number; critical: boolean; cancelled: boolean };
    player_damage: { player: Player; amount: number; cause: string; attacker: Player | Entity | null; cancelled: boolean };
    player_death: { player: Player; cause: string; attacker: Player | Entity | null; keep_inventory: boolean; message: string };
    player_respawn: { player: Player; position: Vec3 };
    entity_spawned: { entity: Entity };
    entity_removed: { entity: Entity };
    entity_damage: { entity: Entity; amount: number; cause: string; attacker: Player | Entity | null; cancelled: boolean };
    entity_death: { entity: Entity; cause: string; attacker: Player | Entity | null; drops: [ItemId, number][] };
    entity_interact: { player: Player; entity: Entity; item: ItemId };
    entity_natural_spawn: { type: string; position: Vec3; cancelled: boolean };
    item_durability: { player: Player; slot: number; item: ItemId; data: ItemData; amount: number; reason: string; cancelled: boolean };
    item_break: { player: Player; slot: number; item: ItemId; data: ItemData };
    equipment_changed: { player: Player; slot: string; old_item: ItemId; item: ItemId };
    avatar_change: { player: Player; avatar: Avatar };
    player_stats: { player: Player; stats: Record<string, number> };
    mob_target: { entity: Entity; target: Player | Entity; previous: Player | Entity | null; reason: string; cancelled: boolean };
    mob_attack: { entity: Entity; attack: { name: string; type: string; damage: number }; target: Player | Entity; cancelled: boolean };
    mob_phase: { entity: Entity; phase: number; message: string };
    projectile_hit: { entity: Entity; owner: Player | Entity | null; hit: "block" | "entity" | "player"; target: Player | Entity | null;
      position: Vec3; block: Vec3; damage: number; cancelled: boolean; keep: boolean };
  }

  export interface Api {
    info(...parts: unknown[]): void;
    registerBlock(name: string, def: BlockDef): BlockId;
    registerItem(name: string, def: ItemDef): ItemId;
    registerRecipe(inputs: Record<string, number>, output: string, count?: number, options?: { station?: string; tier?: number; needs?: string[]; category?: string; id?: string;
      time?: number; project?: boolean; unlock?: "known" | "pickup" | "blueprint" | "experiment" | "secret"; hint?: string; skill?: string }): void;
    registerStation(name: string, def: StationDef): void;
    registerMinigame(name: string, def: { title?: string; type?: "timing" | "hold" | "sequence"; verb?: string; rounds?: number;
      speed?: number; zone?: number; cool?: number; team?: boolean; duration?: number; window?: number }): void;
    registerMaterial(name: string, def: { display_name?: string; item: string; color?: string; tier?: number; speed?: number; durability?: number;
      damage?: number; handle?: number; trait?: { name: string; description?: string; modifiers?: StatModifier[]; durability_mult?: number;
      speed_mult?: number; damage_add?: number; glow?: ItemDef["glow"] } }): void;
    registerPartType(name: string, def: { display_name?: string; sprite: string; cost?: number; station?: string }): number;
    registerAssembly(name: string, def: { display_name?: string; icon?: string; slots: { name: string; part: string; label?: string }[];
      tool_type?: string; damage?: number; cooldown?: number; reach?: number; sweep?: number; station?: string; skill?: string }): number;
    getStation(position: Vec3): Record<string, unknown>;
    registerContainer(name: string, def: { title?: string; groups: { name: string; count: number; columns?: number; label?: string; take_only?: boolean; accepts?: string[] | "fuel" }[];
      progress?: { name: string; label?: string; color?: string }[] }): boolean;
    openContainer(player: Player, position: Vec3): boolean;
    containerItems(position: Vec3): ItemStack[];
    setContainerItem(position: Vec3, slot: number, item: ItemId, count: number, data?: ItemData): void;
    addToContainer(position: Vec3, item: ItemId, count: number, data?: ItemData, group?: string): number;
    containerState(position: Vec3): Record<string, unknown>;
    setContainerState(position: Vec3, state: Record<string, unknown>): void;
    setContainerProgress(position: Vec3, bar: string, value: number): void;
    setFuel(item: string, seconds: number): void;
    getFuel(item: ItemId): number;
    registerProcess(kind: string, input: string, output: string, count?: number, seconds?: number): void;
    getProcess(kind: string, item: ItemId): { output: ItemId; count: number; seconds: number } | Record<string, never>;
    block(name: string): BlockId;
    item(name: string): ItemId;
    itemName(id: ItemId): string;
    itemDisplayName(id: ItemId): string;
    blockName(id: BlockId): string;
    isSolid(id: BlockId): boolean;
    getDrops(id: BlockId): [ItemId, number][];
    /** World generation hook for JavaScript mods (scripts cannot run on generation threads). */
    addOrePass(def: OrePassDef): void;

    getBlock(position: Vec3): BlockId;
    getLoadedBlock(position: Vec3): BlockId;
    setBlock(position: Vec3, id: BlockId, options?: { keepData?: boolean; state?: number }): void;
    fill(from: Vec3, to: Vec3, id: BlockId): void;
    getBlockState(position: Vec3): number;
    /** Returns a copy: call setBlockData to save changes. */
    getBlockData<T = Record<string, unknown>>(position: Vec3): T;
    setBlockData(position: Vec3, data: Record<string, unknown>): void;
    clearBlockData(position: Vec3): void;
    findBlockData(block?: BlockId): Vec3[];
    surfaceY(x: number, z: number): number;
    seesSky(position: Vec3): boolean;
    setPhysics(values: Record<string, number | boolean>): void;
    setWorldTime(timeOfDay: number, dayLength?: number): void;
    timeOfDay(): number;
    daylight(): number;
    facingFromYaw(yaw: number): number;

    players(): Player[];
    findPlayer(name: string): Player | null;
    broadcast(text: string): void;
    setServerInfo(values: { name?: string; description?: string; motd?: string }): void;
    showCrafting(player: Player): void;

    registerEntity(name: string, def: EntityDef): number;
    registerSound(name: string, files: string | string[], options?: { volume?: number; pitch?: number; pitch_variance?: number; range?: number }): number;
    playSound(name: string, position: Vec3, volume?: number, pitch?: number): void;
    spawnEntity(type: string, position: Vec3, options?: { yaw?: number; velocity?: Vec3; data?: Record<string, unknown> }): Entity | null;
    spawnProjectile(type: string, from: Vec3, velocity: Vec3, owner?: Player | Entity | null): Entity | null;
    dropItem(item: ItemId, count: number, position: Vec3): Entity | null;
    entities(center: Vec3, radius: number, type?: string): Entity[];
    addSpawnRule(rule: SpawnRule): void;
    /** Biome generator: data-driven biomes and features (see engine/server/worldgen). */
    useBiomeGenerator(options?: { sea_level?: number; snow_level?: number }): void;
    registerBiome(name: string, def: Record<string, unknown>): void;
    registerFeature(name: string, def: Record<string, unknown>): void;
    registerStructureTemplate(name: string, source: string | Record<string, unknown>): boolean;
    registerStructure(name: string, def: Record<string, unknown>): void;
    registerLootTable(name: string, def: { rolls?: [number, number]; entries: { item: string; count?: [number, number]; weight?: number }[] }): void;
    /** Debug drawing shown to admins with the dev overlay's Draw toggle on (F8). */
    draw: {
      box(min: Vec3, max: Vec3, color?: string, seconds?: number, label?: string): void;
      line(from: Vec3, to: Vec3, color?: string, seconds?: number): void;
      text(position: Vec3, text: string, color?: string, seconds?: number): void;
      path(points: Vec3[], color?: string, seconds?: number): void;
      sphere(center: Vec3, radius?: number, color?: string, seconds?: number): void;
    };
    debug(...parts: unknown[]): void;
    warn(...parts: unknown[]): void;
    error(...parts: unknown[]): void;
    registerGuideChapter(name: string, def?: { title?: string; icon?: string; order?: number; description?: string }): boolean;
    registerGuidePage(name: string, def: GuidePage): boolean;
    registerTutorial(name: string, def: Tutorial): boolean;
    registerTip(name: string, def: { text: string; icon?: string; page?: string; trigger: TutorialGoal }): boolean;
    getBiome(position: Vec3): string;
    setSpawnCaps(caps: { monster?: number; animal?: number; ambient?: number; misc?: number }): void;
    setGameplay(values: Gameplay): void;
    getGameplay<K extends keyof Gameplay>(rule: K): Gameplay[K];
    makeNoise(position: Vec3, radius: number, source?: Player | Entity | null): void;
    registerEquipmentSlot(name: string, def?: { display_name?: string }): void;
    registerStat(name: string, base: number): void;
    registerCosmetic(name: string, def: CosmeticDef): string;
    registerEffect(name: string, def: EffectDef): number;
    registerBlockTick(block: string, handler: (ctx: { position: Vec3; block: BlockId; state: number; ticks: number; reason: "random" | "scheduled"; payload: Record<string, unknown> }) => void,
      options?: { interval?: number; catch_up?: boolean }): void;
    scheduleBlockTick(position: Vec3, seconds: number, payload?: Record<string, unknown>): void;
    getLight(position: Vec3): number;
    getLightLevels(position: Vec3): { sky: number; block: number };
    worldClock(): number;
    breakBlock(position: Vec3, drop?: boolean): void;
    playEffect(name: string, position: Vec3, options?: EffectOptions): void;
    explode(position: Vec3, power: number, options?: { source?: unknown; break_blocks?: boolean; drop_chance?: number; damage?: number; effect?: string; sound?: string }): void;
    registerCosmeticCategory(name: string, def?: { display_name?: string; attach?: string; covers?: string[] }): boolean;
    setCosmeticsPolicy(values: { allow_builtin?: boolean; allow_colors?: boolean; armor?: "player" | "armor" | "cosmetics"; blocked?: string[]; uniform?: Avatar }): void;
    registerMobBehavior(name: string, def: { score: (mob: Entity, ctx: MobContext) => number; update: (mob: Entity, ctx: MobContext) => void; stop?: (mob: Entity) => void }): void;

    on<E extends keyof Events>(event: E, handler: (event: Events[E]) => void, priority?: number): void;
    command(name: string, description: string, handler: (player: Player, args: string[]) => void, options?: { admin?: boolean }): void;
    after(seconds: number, fn: () => void): number;
    every(seconds: number, fn: () => void): number;
    cancel(taskId: number): void;
    storage: { get<T = unknown>(key: string, fallback?: T): T; set(key: string, value: unknown): void };
  }

  export type GuideBlock =
      | { type: "text" | "heading" | "tip"; text: string }
      | { type: "items"; items: string[] }
      | { type: "recipe"; output: string }
      | { type: "entity"; entity: string }
      | { type: "image"; asset: string }
      | { type: "link"; page: string; text?: string }
      | { type: "keys"; action: string; text: string };

  export interface TutorialGoal {
      type: "break" | "place" | "craft" | "pickup" | "eat" | "use_item" | "use_block" | "equip" | "kill" | "breed" | "tame"
          | "learn" | "read" | "unlock_page" | "sleep" | "respawn" | "death" | "damage" | "upgrade" | "assemble" | "event"
          | "have" | "depth" | "reach" | "biome" | "hunger_below" | "health_below" | "night" | "flag" | "manual";
      target?: string | string[];
      count?: number;
      event?: string; who?: string; field?: string;
      below?: number; position?: [number, number, number]; radius?: number; value?: number;
  }

  export interface Tutorial {
      title?: string;
      description?: string;
      order?: number;
      auto_start?: boolean;
      reward?: [string, number][];
      steps: { title: string; text?: string; icon?: string; goal: TutorialGoal;
          hint?: false | { block?: string | string[]; entity?: string | string[]; position?: [number, number, number] };
          page?: string; reward?: [string, number][] }[];
  }

  export interface GuidePage {
      chapter: string;
      title?: string;
      icon?: string;
      order?: number;
      unlock?: { item?: string; recipe?: string; entity?: string; biome?: string; flag?: string; page?: string };
      hint?: string;
      keywords?: string;
      blocks: GuideBlock[];
  }
}
