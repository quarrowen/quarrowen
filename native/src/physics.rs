//! Port of engine/shared/player_physics.gd (players) and engine/shared/entity_physics.gd (entities).
//! Keep them in lockstep with the GDScript versions: the client predicts players with the same step
//! the server runs, so any divergence shows up as rubber-banding.

use godot::builtin::{Vector2, Vector3};

use crate::world::NativeVoxelWorld;

const DT: f32 = 1.0 / 60.0;
const HALF_WIDTH: f32 = 0.3;
const HEIGHT: f32 = 1.8;
const MAX_SUBSTEP: f32 = 0.45;
const SKIN: f32 = 0.001;
const EDGE: f32 = 0.0001;
const LIQUID_ACCEL: f32 = 20.0;
/// Crouching and flying, mirroring PlayerPhysics.
const SNEAK_SPEED: f32 = 0.3;
const FLY_SPEED: f32 = 10.0;
const FLY_SPRINT: f32 = 1.8;
const FLY_RISE: f32 = 8.0;

pub struct Body {
    pub position: Vector3,
    pub velocity: Vector3,
    pub on_ground: bool,
}

pub struct Input {
    pub move_input: Vector2,
    pub yaw: f32,
    pub jump: bool,
    pub sprint: bool,
    pub sneak: bool,
    pub flying: bool,
}

pub struct Rules {
    walk_speed: f32,
    sprint_speed: f32,
    gravity: f32,
    jump_velocity: f32,
    terminal_velocity: f32,
    ground_accel: f32,
    air_accel: f32,
    swim_speed: f32,
    sink_speed: f32,
}

impl Rules {
    /// Same order as PlayerPhysics.Rules.TUNABLES; missing values fall back to engine defaults.
    pub fn from_slice(v: &[f32]) -> Self {
        let at = |i: usize, default: f32| v.get(i).copied().unwrap_or(default);
        Rules {
            walk_speed: at(0, 4.3),
            sprint_speed: at(1, 5.6),
            gravity: at(2, 32.0),
            jump_velocity: at(3, 9.0),
            terminal_velocity: at(4, 60.0),
            ground_accel: at(5, 60.0),
            air_accel: at(6, 12.0),
            swim_speed: at(7, 3.0),
            sink_speed: at(8, 2.0),
        }
    }
}

/// A collision box: half width (x/z) and height, feet at the position.
#[derive(Clone, Copy)]
pub struct Size {
    pub half_width: f32,
    pub height: f32,
}

const PLAYER: Size = Size { half_width: HALF_WIDTH, height: HEIGHT };

/// Result flags of an entity step.
pub struct EntityStep {
    pub blocked: bool,
    pub in_liquid: bool,
}

/// One entity step (EntityPhysics.step): gravity, liquid drag, airborne drag, collision.
pub fn step_entity(s: &mut Body, size: Size, world: &NativeVoxelWorld, dt: f32, gravity: f32, drag: f32) -> EntityStep {
    if collides(s.position, size, world) {
        s.position.y += 0.25;
        s.velocity = Vector3::ZERO;
        s.on_ground = false;
        return EntityStep { blocked: false, in_liquid: false };
    }
    let in_liquid = world.is_liquid(
        s.position.x.floor() as i32,
        (s.position.y + (size.height * 0.5).min(0.4)).floor() as i32,
        s.position.z.floor() as i32,
    );
    if in_liquid {
        s.velocity.y = move_toward(s.velocity.y, -1.5, 12.0 * dt);
        let damp = (1.0 - 3.0 * dt).max(0.0);
        s.velocity.x *= damp;
        s.velocity.z *= damp;
    } else {
        s.velocity.y = (s.velocity.y - gravity * dt).max(-60.0);
        if drag > 0.0 && !s.on_ground {
            let damp = (1.0 - drag * dt).max(0.0);
            s.velocity.x *= damp;
            s.velocity.z *= damp;
        }
    }
    let motion = s.velocity * dt;
    let largest = motion.x.abs().max(motion.y.abs()).max(motion.z.abs());
    let steps = ((largest / MAX_SUBSTEP).ceil() as i32).max(1);
    let mut part = motion / steps as f32;
    s.on_ground = false;
    let mut blocked = false;
    for _ in 0..steps {
        if move_axis(s, 1, part.y, size, world) {
            if part.y < 0.0 {
                s.on_ground = true;
            }
            s.velocity.y = 0.0;
            part.y = 0.0;
        }
        if move_axis(s, 0, part.x, size, world) {
            s.velocity.x = 0.0;
            part.x = 0.0;
            blocked = true;
        }
        if move_axis(s, 2, part.z, size, world) {
            s.velocity.z = 0.0;
            part.z = 0.0;
            blocked = true;
        }
    }
    EntityStep { blocked, in_liquid }
}

pub fn step(s: &mut Body, input: &Input, world: &NativeVoxelWorld, rules: &Rules) {
    if collides(s.position, PLAYER, world) {
        // Stuck inside a block (terrain changed around us): push upward until free.
        s.position.y += 0.25;
        s.velocity = Vector3::ZERO;
        s.on_ground = false;
        return;
    }

    let mut mv = input.move_input;
    if mv.x * mv.x + mv.y * mv.y > 1.0 {
        mv = normalized2(mv);
    }
    let (sin_yaw, cos_yaw) = (libm::sinf(input.yaw), libm::cosf(input.yaw));
    let wish_x = cos_yaw * mv.x - sin_yaw * mv.y;
    let wish_z = -sin_yaw * mv.x - cos_yaw * mv.y;
    let in_liquid = world.is_liquid(
        s.position.x.floor() as i32,
        (s.position.y + 0.4).floor() as i32,
        s.position.z.floor() as i32,
    );

    let mut speed = if input.sprint && mv.y > 0.0 { rules.sprint_speed } else { rules.walk_speed };
    if input.flying {
        speed = FLY_SPEED * if input.sprint { FLY_SPRINT } else { 1.0 };
    } else if input.sneak && s.on_ground {
        speed *= SNEAK_SPEED;
    }
    if in_liquid && !input.flying {
        speed *= 0.5;
    }
    let accel = if s.on_ground || in_liquid || input.flying { rules.ground_accel } else { rules.air_accel };
    let horizontal = move_toward2(
        Vector2::new(s.velocity.x, s.velocity.z),
        Vector2::new(wish_x * speed, wish_z * speed),
        accel * DT,
    );
    s.velocity.x = horizontal.x;
    s.velocity.z = horizontal.y;

    if input.flying {
        let rise = if input.jump { FLY_RISE } else { 0.0 } - if input.sneak { FLY_RISE } else { 0.0 };
        s.velocity.y = move_toward(s.velocity.y, rise, rules.ground_accel * DT);
    } else if in_liquid {
        let target = if input.jump { rules.swim_speed } else { -rules.sink_speed };
        s.velocity.y = move_toward(s.velocity.y, target, LIQUID_ACCEL * DT);
    } else {
        if input.jump && s.on_ground {
            s.velocity.y = rules.jump_velocity;
        }
        s.velocity.y = (s.velocity.y - rules.gravity * DT).max(-rules.terminal_velocity);
    }

    let motion = s.velocity * DT;
    let largest = motion.x.abs().max(motion.y.abs()).max(motion.z.abs());
    let steps = ((largest / MAX_SUBSTEP).ceil() as i32).max(1);
    let mut part = motion / steps as f32;
    // Crouching on solid ground: a sideways step that would leave nothing underfoot is refused.
    let edge_guard = input.sneak && s.on_ground && !input.flying && !in_liquid;
    s.on_ground = false;
    for _ in 0..steps {
        if move_axis(s, 1, part.y, PLAYER, world) {
            if part.y < 0.0 {
                s.on_ground = true;
            }
            s.velocity.y = 0.0;
            part.y = 0.0;
        }
        let mut before = s.position;
        if move_axis(s, 0, part.x, PLAYER, world) {
            s.velocity.x = 0.0;
            part.x = 0.0;
        } else if edge_guard && !supported(s.position, world) {
            s.position = before;
            s.velocity.x = 0.0;
            part.x = 0.0;
        }
        before = s.position;
        if move_axis(s, 2, part.z, PLAYER, world) {
            s.velocity.z = 0.0;
            part.z = 0.0;
        } else if edge_guard && !supported(s.position, world) {
            s.position = before;
            s.velocity.z = 0.0;
            part.z = 0.0;
        }
    }
}

/// Solid ground just under the player's box (the crouch edge guard).
fn supported(position: Vector3, world: &NativeVoxelWorld) -> bool {
    let y = (position.y - 0.08).floor() as i32;
    let z0 = (position.z - HALF_WIDTH).floor() as i32;
    let z1 = (position.z + HALF_WIDTH - EDGE).floor() as i32;
    let x0 = (position.x - HALF_WIDTH).floor() as i32;
    let x1 = (position.x + HALF_WIDTH - EDGE).floor() as i32;
    for z in z0..=z1 {
        for x in x0..=x1 {
            if world.is_solid(x, y, z) {
                return true;
            }
        }
    }
    false
}

fn axis(v: Vector3, i: usize) -> f32 {
    match i {
        0 => v.x,
        1 => v.y,
        _ => v.z,
    }
}

fn set_axis(v: &mut Vector3, i: usize, value: f32) {
    match i {
        0 => v.x = value,
        1 => v.y = value,
        _ => v.z = value,
    }
}

/// Moves along one axis; on collision snaps flush against the blocking voxel.
fn move_axis(s: &mut Body, i: usize, delta: f32, size: Size, world: &NativeVoxelWorld) -> bool {
    if delta == 0.0 {
        return false;
    }
    let mut p = s.position;
    let moved = axis(p, i) + delta;
    set_axis(&mut p, i, moved);
    if !collides(p, size, world) {
        s.position = p;
        return false;
    }
    let value = axis(p, i);
    let snapped = if i == 1 {
        if delta > 0.0 {
            (value + size.height).floor() - size.height - SKIN
        } else {
            value.floor() + 1.0
        }
    } else if delta > 0.0 {
        (value + size.half_width).floor() - size.half_width - SKIN
    } else {
        (value - size.half_width).floor() + 1.0 + size.half_width + SKIN
    };
    set_axis(&mut p, i, snapped);
    if (snapped - axis(s.position, i)) * delta >= 0.0 && !collides(p, size, world) {
        s.position = p;
    }
    true
}

fn collides(p: Vector3, size: Size, world: &NativeVoxelWorld) -> bool {
    let x0 = (p.x - size.half_width).floor() as i32;
    let x1 = (p.x + size.half_width - EDGE).floor() as i32;
    let y0 = p.y.floor() as i32;
    let y1 = (p.y + size.height - EDGE).floor() as i32;
    let z0 = (p.z - size.half_width).floor() as i32;
    let z1 = (p.z + size.half_width - EDGE).floor() as i32;
    for y in y0..=y1 {
        for z in z0..=z1 {
            for x in x0..=x1 {
                if world.is_solid(x, y, z) {
                    return true;
                }
            }
        }
    }
    false
}

fn normalized2(v: Vector2) -> Vector2 {
    let len = libm::sqrtf(v.x * v.x + v.y * v.y);
    if len == 0.0 {
        v
    } else {
        Vector2::new(v.x / len, v.y / len)
    }
}

/// Matches Godot's Vector2.move_toward.
fn move_toward2(from: Vector2, to: Vector2, delta: f32) -> Vector2 {
    let d = Vector2::new(to.x - from.x, to.y - from.y);
    let len = libm::sqrtf(d.x * d.x + d.y * d.y);
    if len <= delta || len < 0.00001 {
        to
    } else {
        Vector2::new(from.x + d.x / len * delta, from.y + d.y / len * delta)
    }
}

/// Matches Godot's move_toward for scalars.
fn move_toward(from: f32, to: f32, delta: f32) -> f32 {
    if (to - from).abs() <= delta {
        to
    } else {
        from + (to - from).signum() * delta
    }
}
