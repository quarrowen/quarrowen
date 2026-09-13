//! Port of engine/shared/player_physics.gd. Keep the two in lockstep: the client predicts with the
//! same step the server runs, so any divergence shows up as rubber-banding.

use godot::builtin::{Vector2, Vector3};

use crate::world::NativeVoxelWorld;

const DT: f32 = 1.0 / 60.0;
const HALF_WIDTH: f32 = 0.3;
const HEIGHT: f32 = 1.8;
const MAX_SUBSTEP: f32 = 0.45;
const SKIN: f32 = 0.001;
const EDGE: f32 = 0.0001;
const LIQUID_ACCEL: f32 = 20.0;

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

pub fn step(s: &mut Body, input: &Input, world: &NativeVoxelWorld, rules: &Rules) {
    if collides(s.position, world) {
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
    if in_liquid {
        speed *= 0.5;
    }
    let accel = if s.on_ground || in_liquid { rules.ground_accel } else { rules.air_accel };
    let horizontal = move_toward2(
        Vector2::new(s.velocity.x, s.velocity.z),
        Vector2::new(wish_x * speed, wish_z * speed),
        accel * DT,
    );
    s.velocity.x = horizontal.x;
    s.velocity.z = horizontal.y;

    if in_liquid {
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
    s.on_ground = false;
    for _ in 0..steps {
        if move_axis(s, 1, part.y, world) {
            if part.y < 0.0 {
                s.on_ground = true;
            }
            s.velocity.y = 0.0;
            part.y = 0.0;
        }
        if move_axis(s, 0, part.x, world) {
            s.velocity.x = 0.0;
            part.x = 0.0;
        }
        if move_axis(s, 2, part.z, world) {
            s.velocity.z = 0.0;
            part.z = 0.0;
        }
    }
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
fn move_axis(s: &mut Body, i: usize, delta: f32, world: &NativeVoxelWorld) -> bool {
    if delta == 0.0 {
        return false;
    }
    let mut p = s.position;
    let moved = axis(p, i) + delta;
    set_axis(&mut p, i, moved);
    if !collides(p, world) {
        s.position = p;
        return false;
    }
    let value = axis(p, i);
    let snapped = if i == 1 {
        if delta > 0.0 {
            (value + HEIGHT).floor() - HEIGHT - SKIN
        } else {
            value.floor() + 1.0
        }
    } else if delta > 0.0 {
        (value + HALF_WIDTH).floor() - HALF_WIDTH - SKIN
    } else {
        (value - HALF_WIDTH).floor() + 1.0 + HALF_WIDTH + SKIN
    };
    set_axis(&mut p, i, snapped);
    if (snapped - axis(s.position, i)) * delta >= 0.0 && !collides(p, world) {
        s.position = p;
    }
    true
}

fn collides(p: Vector3, world: &NativeVoxelWorld) -> bool {
    let x0 = (p.x - HALF_WIDTH).floor() as i32;
    let x1 = (p.x + HALF_WIDTH - EDGE).floor() as i32;
    let y0 = p.y.floor() as i32;
    let y1 = (p.y + HEIGHT - EDGE).floor() as i32;
    let z0 = (p.z - HALF_WIDTH).floor() as i32;
    let z1 = (p.z + HALF_WIDTH - EDGE).floor() as i32;
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
