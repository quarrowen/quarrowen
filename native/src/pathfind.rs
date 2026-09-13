//! Voxel A* for mobs of any size, line-of-sight rays and straight-walk checks. Twin of
//! engine/server/ai/pathfinder.gd: keep the rules identical (the GDScript version only has a
//! smaller node budget).
//!
//! A node is the cell holding the minimum corner of a mob's footprint: a mob `width` cells wide
//! and `height` cells tall standing at node (x, y, z) occupies x..x+width, y..y+height, z..z+width.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};

use crate::world::NativeVoxelWorld;

pub struct Agent {
    pub width: i32,
    pub height: i32,
    pub step_up: i32,
    pub max_drop: i32,
    pub can_swim: bool,
}

pub const STATUS_NONE: f32 = 0.0;
pub const STATUS_FOUND: f32 = 1.0;
pub const STATUS_PARTIAL: f32 = 2.0;

const DIRS: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
const DIAGONAL: f32 = std::f32::consts::SQRT_2;
const STEP_UP_COST: f32 = 0.6;
const DROP_COST: f32 = 0.35;
const SWIM_COST: f32 = 2.5;
/// Extra cost for cells next to a drop the mob could not survive, so paths keep away from edges.
const EDGE_COST: f32 = 0.6;

#[derive(Copy, Clone, PartialEq)]
struct Open {
    f: f32,
    g: f32,
    node: (i32, i32, i32),
}

impl Eq for Open {}

impl Ord for Open {
    fn cmp(&self, other: &Self) -> Ordering {
        // Min-heap on f, ties broken toward larger g (deeper nodes finish sooner).
        other.f.partial_cmp(&self.f).unwrap_or(Ordering::Equal).then_with(|| self.g.partial_cmp(&other.g).unwrap_or(Ordering::Equal))
    }
}

impl PartialOrd for Open {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl NativeVoxelWorld {
    /// Every cell of the mob's box is free of solid blocks (and of hazards).
    fn box_clear(&self, x: i32, y: i32, z: i32, a: &Agent) -> bool {
        for dy in 0..a.height {
            for dz in 0..a.width {
                for dx in 0..a.width {
                    let b = self.block(x + dx, y + dy, z + dz);
                    if self.solid_at(b) || self.hazard_at(b) {
                        return false;
                    }
                }
            }
        }
        true
    }

    /// The mob can stand here: its box is clear and something under the footprint holds it up
    /// (or it swims). Hazards underfoot are not standable.
    pub fn can_stand(&self, x: i32, y: i32, z: i32, a: &Agent) -> bool {
        if !self.box_clear(x, y, z, a) {
            return false;
        }
        let mut supported = false;
        for dz in 0..a.width {
            for dx in 0..a.width {
                let below = self.block(x + dx, y - 1, z + dz);
                if self.hazard_at(below) {
                    return false;
                }
                if self.solid_at(below) && below != crate::UNLOADED {
                    supported = true;
                }
                if a.can_swim && self.liquid_at(self.block(x + dx, y, z + dz)) {
                    supported = true;
                }
            }
        }
        if !supported {
            return false;
        }
        if !a.can_swim {
            for dz in 0..a.width {
                for dx in 0..a.width {
                    if self.liquid_at(self.block(x + dx, y, z + dz)) {
                        return false;
                    }
                }
            }
        }
        true
    }

    fn in_liquid(&self, x: i32, y: i32, z: i32, a: &Agent) -> bool {
        (0..a.width).any(|dz| (0..a.width).any(|dx| self.liquid_at(self.block(x + dx, y, z + dz))))
    }

    /// True if stepping off this node sideways would fall further than the mob tolerates.
    fn near_edge(&self, x: i32, y: i32, z: i32, a: &Agent) -> bool {
        for (dx, dz) in DIRS.iter().take(4) {
            let (nx, nz) = (x + dx, z + dz);
            if !self.box_clear(nx, y, nz, a) {
                continue;
            }
            let mut depth = 0;
            while depth <= a.max_drop && !self.column_has_floor(nx, y - 1 - depth, nz, a) {
                depth += 1;
            }
            if depth > a.max_drop {
                return true;
            }
        }
        false
    }

    fn column_has_floor(&self, x: i32, y: i32, z: i32, a: &Agent) -> bool {
        (0..a.width).any(|dz| (0..a.width).any(|dx| {
            let b = self.block(x + dx, y, z + dz);
            (self.solid_at(b) && b != crate::UNLOADED) || self.liquid_at(b)
        }))
    }

    /// Neighbouring nodes with their move cost.
    fn neighbours(&self, n: (i32, i32, i32), a: &Agent, out: &mut Vec<((i32, i32, i32), f32)>) {
        out.clear();
        let (x, y, z) = n;
        for (i, (dx, dz)) in DIRS.iter().enumerate() {
            let (nx, nz) = (x + dx, z + dz);
            let diagonal = i >= 4;
            let base = if diagonal { DIAGONAL } else { 1.0 };
            if diagonal && !(self.box_clear(x + dx, y, z, a) && self.box_clear(x, y, z + dz, a)) {
                continue; // no cutting corners
            }
            if self.can_stand(nx, y, nz, a) {
                out.push(((nx, y, nz), base));
                continue;
            }
            if self.box_clear(nx, y, nz, a) {
                // Walk off the edge: land on the first floor below, if the drop is survivable.
                for k in 1..=a.max_drop {
                    if !self.box_clear(nx, y - k, nz, a) {
                        break;
                    }
                    if self.can_stand(nx, y - k, nz, a) {
                        out.push(((nx, y - k, nz), base + DROP_COST * k as f32));
                        break;
                    }
                }
                continue;
            }
            if diagonal {
                continue; // climbing is only straight
            }
            for k in 1..=a.step_up {
                // Needs headroom above the current node to jump before moving over.
                if !self.box_clear(x, y + k, z, a) {
                    break;
                }
                if self.can_stand(nx, y + k, nz, a) {
                    out.push(((nx, y + k, nz), base + STEP_UP_COST * k as f32));
                    break;
                }
            }
        }
    }

    /// A* from `start` to within `radius` cells of `goal`. Returns (status, nodes), nodes from start
    /// to end. When the goal cannot be reached within `max_nodes` expansions the path leads to the
    /// explored node closest to it (STATUS_PARTIAL).
    pub fn astar(&self, start: (i32, i32, i32), goal: (i32, i32, i32), radius: f32, a: &Agent, max_nodes: usize) -> (f32, Vec<(i32, i32, i32)>) {
        let start = match self.settle(start, a) {
            Some(s) => s,
            None => return (STATUS_NONE, Vec::new()),
        };
        let h = |n: (i32, i32, i32)| {
            let dx = (n.0 - goal.0).abs() as f32;
            let dz = (n.2 - goal.2).abs() as f32;
            let dy = (n.1 - goal.1).abs() as f32;
            dx.max(dz) + (DIAGONAL - 1.0) * dx.min(dz) + dy * 0.5
        };
        let reached = |n: (i32, i32, i32)| {
            let dx = (n.0 - goal.0) as f32;
            let dz = (n.2 - goal.2) as f32;
            (dx * dx + dz * dz).sqrt() <= radius && (n.1 - goal.1).abs() <= 2
        };
        let mut open = BinaryHeap::new();
        let mut came: HashMap<(i32, i32, i32), ((i32, i32, i32), f32)> = HashMap::new();
        came.insert(start, (start, 0.0));
        open.push(Open { f: h(start), g: 0.0, node: start });
        let mut best = start;
        let mut best_h = h(start);
        let mut expanded = 0;
        let mut buffer = Vec::with_capacity(16);
        while let Some(Open { g, node, .. }) = open.pop() {
            if came.get(&node).map_or(false, |(_, known)| *known < g) {
                continue; // stale entry
            }
            if reached(node) {
                return (STATUS_FOUND, self.unwind(&came, node));
            }
            expanded += 1;
            if expanded > max_nodes {
                break;
            }
            let edge = if self.near_edge(node.0, node.1, node.2, a) { EDGE_COST } else { 0.0 };
            self.neighbours(node, a, &mut buffer);
            for &(next, cost) in buffer.iter() {
                let swim = if a.can_swim && self.in_liquid(next.0, next.1, next.2, a) { SWIM_COST } else { 0.0 };
                let tentative = g + cost + swim + edge;
                if came.get(&next).map_or(true, |(_, known)| tentative < *known) {
                    came.insert(next, (node, tentative));
                    let hn = h(next);
                    if hn < best_h {
                        best_h = hn;
                        best = next;
                    }
                    open.push(Open { f: tentative + hn, g: tentative, node: next });
                }
            }
        }
        if best == start {
            return (STATUS_NONE, vec![start]);
        }
        (STATUS_PARTIAL, self.unwind(&came, best))
    }

    fn unwind(&self, came: &HashMap<(i32, i32, i32), ((i32, i32, i32), f32)>, end: (i32, i32, i32)) -> Vec<(i32, i32, i32)> {
        let mut path = vec![end];
        let mut current = end;
        while let Some((parent, _)) = came.get(&current) {
            if *parent == current {
                break;
            }
            current = *parent;
            path.push(current);
        }
        path.reverse();
        path
    }

    /// Nearest standable node at or just below/above a position (mobs mid-jump or on slabs).
    pub fn settle(&self, n: (i32, i32, i32), a: &Agent) -> Option<(i32, i32, i32)> {
        for dy in [0, -1, 1, -2, 2, -3] {
            if self.can_stand(n.0, n.1 + dy, n.2, a) {
                return Some((n.0, n.1 + dy, n.2));
            }
        }
        None
    }

    /// The mob can walk in a straight line between two nodes on the same level without falling.
    pub fn walk_line(&self, from: (i32, i32, i32), to: (i32, i32, i32), a: &Agent) -> bool {
        if from.1 != to.1 {
            return false;
        }
        let dx = (to.0 - from.0) as f32;
        let dz = (to.2 - from.2) as f32;
        let steps = (dx.abs().max(dz.abs()) * 3.0).ceil() as i32;
        if steps == 0 {
            return true;
        }
        for i in 0..=steps {
            let t = i as f32 / steps as f32;
            // Sample the footprint cells a box centred on the line would overlap.
            let cx = from.0 as f32 + 0.5 * a.width as f32 + dx * t;
            let cz = from.2 as f32 + 0.5 * a.width as f32 + dz * t;
            let half = 0.5 * a.width as f32 - 0.05;
            let (x0, x1) = ((cx - half).floor() as i32, (cx + half).floor() as i32);
            let (z0, z1) = ((cz - half).floor() as i32, (cz + half).floor() as i32);
            let single = Agent { width: 1, height: a.height, step_up: 0, max_drop: 0, can_swim: a.can_swim };
            let mut supported = false;
            for z in z0..=z1 {
                for x in x0..=x1 {
                    if !self.box_clear(x, from.1, z, &single) {
                        return false;
                    }
                    let below = self.block(x, from.1 - 1, z);
                    if self.hazard_at(below) {
                        return false;
                    }
                    if self.solid_at(below) && below != crate::UNLOADED {
                        supported = true;
                    }
                }
            }
            if !supported {
                return false;
            }
        }
        true
    }

    /// True if nothing that blocks sight lies strictly between the two points.
    pub fn sight_line(&self, from: [f32; 3], to: [f32; 3]) -> bool {
        let d = [to[0] - from[0], to[1] - from[1], to[2] - from[2]];
        let length = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
        if length < 0.0001 {
            return true;
        }
        let dir = [d[0] / length, d[1] / length, d[2] / length];
        let mut cell = [from[0].floor() as i32, from[1].floor() as i32, from[2].floor() as i32];
        let target = [to[0].floor() as i32, to[1].floor() as i32, to[2].floor() as i32];
        let mut step = [0i32; 3];
        let mut t_max = [f32::INFINITY; 3];
        let mut t_delta = [f32::INFINITY; 3];
        for i in 0..3 {
            if dir[i] > 0.0 {
                step[i] = 1;
                t_max[i] = (from[i].floor() + 1.0 - from[i]) / dir[i];
                t_delta[i] = 1.0 / dir[i];
            } else if dir[i] < 0.0 {
                step[i] = -1;
                t_max[i] = (from[i] - from[i].floor()) / -dir[i];
                t_delta[i] = -1.0 / dir[i];
            }
        }
        let mut guard = 0;
        loop {
            if cell == target {
                return true;
            }
            let axis = if t_max[0] < t_max[1] && t_max[0] < t_max[2] { 0 } else if t_max[1] < t_max[2] { 1 } else { 2 };
            if t_max[axis] > length {
                return true;
            }
            cell[axis] += step[axis];
            t_max[axis] += t_delta[axis];
            if cell != target && self.sight_blocked_at(self.block(cell[0], cell[1], cell[2])) {
                return false;
            }
            guard += 1;
            if guard > 512 {
                return false;
            }
        }
    }
}
