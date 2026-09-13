//! JavaScript runtime for server mods (QuickJS-NG via rquickjs).
//!
//! Sandboxed by construction: only ECMAScript built-ins exist (no filesystem, network or process
//! access). Each runtime has a memory cap and every call into JavaScript gets a time budget, after
//! which the engine interrupts the script. The mod API itself lives in GDScript
//! (engine/server/js_mod.gd); JavaScript reaches it through one bridge function, `__host_call`,
//! exchanging JSON strings.

use std::cell::Cell;
use std::rc::Rc;
use std::time::{Duration, Instant};

use godot::prelude::*;
use rquickjs::{CatchResultExt, Context, Ctx, Function, Module, Runtime};

const MEMORY_LIMIT: usize = 64 * 1024 * 1024;
const STACK_LIMIT: usize = 1024 * 1024;
const DEFAULT_BUDGET_MS: u64 = 250;

#[derive(GodotClass)]
#[class(base = RefCounted)]
pub struct NativeJsRuntime {
    runtime: Runtime,
    context: Context,
    deadline: Rc<Cell<Option<Instant>>>,
    budget_ms: u64,
    busy: Cell<bool>,
}

#[godot_api]
impl IRefCounted for NativeJsRuntime {
    fn init(_base: Base<RefCounted>) -> Self {
        let runtime = Runtime::new().expect("QuickJS runtime");
        runtime.set_memory_limit(MEMORY_LIMIT);
        runtime.set_max_stack_size(STACK_LIMIT);
        let deadline: Rc<Cell<Option<Instant>>> = Rc::new(Cell::new(None));
        let watch = deadline.clone();
        runtime.set_interrupt_handler(Some(Box::new(move || watch.get().is_some_and(|d| Instant::now() > d))));
        let context = Context::full(&runtime).expect("QuickJS context");
        Self { runtime, context, deadline, budget_ms: DEFAULT_BUDGET_MS, busy: Cell::new(false) }
    }
}

#[godot_api]
impl NativeJsRuntime {
    /// Milliseconds a single call into JavaScript may run before it is interrupted.
    #[func]
    fn set_time_budget_ms(&mut self, ms: i64) {
        self.budget_ms = ms.clamp(1, 10_000) as u64;
    }

    /// Installs `__host_call(method, argsJson) -> resultJson`, which invokes `host(method, argsJson)`.
    #[func]
    fn set_host(&mut self, host: Callable) {
        self.context.with(|ctx| {
            let bridge = Function::new(ctx.clone(), move |method: String, args: String| -> String {
                let mut call_args = VarArray::new();
                call_args.push(&GString::from(method.as_str()).to_variant());
                call_args.push(&GString::from(args.as_str()).to_variant());
                match host.callv(&call_args).try_to::<GString>() {
                    Ok(result) => result.to_string(),
                    Err(_) => "{\"__error\":\"host returned no result\"}".to_string(),
                }
            });
            if let Ok(bridge) = bridge {
                let _ = ctx.globals().set("__host_call", bridge);
            }
        });
    }

    /// Runs a classic script (used for the API prelude). Returns "" on success or the error.
    #[func]
    fn eval_script(&self, name: GString, source: GString) -> GString {
        let name = name.to_string();
        self.guarded(|ctx| {
            ctx.eval::<(), _>(source.to_string()).catch(&ctx).map_err(|e| format!("{name}: {e}"))
        })
        .err()
        .map(|e| GString::from(e.as_str()))
        .unwrap_or_default()
    }

    /// Evaluates an ES module and stores its namespace in `globalThis.__exports`. Returns "" or the error.
    #[func]
    fn load_module(&self, name: GString, source: GString) -> GString {
        let name = name.to_string();
        self.guarded(|ctx| {
            let run = || -> rquickjs::Result<()> {
                let (module, promise) = Module::declare(ctx.clone(), name.clone(), source.to_string())?.eval()?;
                promise.finish::<()>()?;
                ctx.globals().set("__exports", module.namespace()?)?;
                Ok(())
            };
            run().catch(&ctx).map_err(|e| format!("{name}: {e}"))
        })
        .err()
        .map(|e| GString::from(e.as_str()))
        .unwrap_or_default()
    }

    /// Calls global function `name` with one string argument and returns its string result. Errors
    /// (exceptions, time budget exceeded, re-entrancy) come back as `{"__error": "..."}`.
    #[func]
    fn call_function(&self, name: GString, argument: GString) -> GString {
        let name = name.to_string();
        let result = self.guarded(|ctx| {
            let run = || -> rquickjs::Result<String> {
                let function: Function = ctx.globals().get(name.as_str())?;
                function.call((argument.to_string(),))
            };
            run().catch(&ctx).map_err(|e| e.to_string())
        });
        // Let promises (async mod code) make progress.
        while self.runtime.is_job_pending() {
            if self.runtime.execute_pending_job().is_err() {
                break;
            }
        }
        match result {
            Ok(value) => GString::from(value.as_str()),
            Err(error) => GString::from(format!("{{\"__error\":{}}}", json_string(&error)).as_str()),
        }
    }

    /// Bytes currently allocated by the JavaScript heap.
    #[func]
    fn memory_used(&self) -> i64 {
        self.runtime.memory_usage().memory_used_size
    }
}

impl NativeJsRuntime {
    fn guarded<R>(&self, f: impl FnOnce(Ctx) -> Result<R, String>) -> Result<R, String> {
        if self.busy.get() {
            return Err("re-entrant call into JavaScript (a host call triggered another script callback)".into());
        }
        self.busy.set(true);
        self.deadline.set(Some(Instant::now() + Duration::from_millis(self.budget_ms)));
        let result = self.context.with(f);
        self.deadline.set(None);
        self.busy.set(false);
        result
    }
}

fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
