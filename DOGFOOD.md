# Dogfood notes

Running log of problems hit while building this tool that belong to Jac itself
(compiler, runtime, diagnostics) or to gaps in the `jac guide` skill files —
things that, had they been documented, would have avoided a dead end. Compiler:
jaclang 0.34.6 dev source (jaseci checkout). Every finding below was hit while
building the actual tool or its spike, under
`jac nacompile --gc none --enforce-nogc --assert-no-rc` unless noted.

## Jac issues

### 1. `os.path.getsize` compiles to a broken binary under default GC, E5092 under `--gc none`

`jac-native` promises unsupported stdlib "fails loudly at compile time".
`os.path.getsize(p)` instead compiles cleanly under the default `--gc cycles`
and produces a binary that prints nothing at all (every statement in the
program is silently dead), and only under `--gc none` fails — with an opaque
`E5092: Native lowering failed for expression 'FuncCall'`, not a "module
member not supported" message. Either support it (a downloader wants file
sizes constantly) or fail loudly on both paths.

Workaround used here: `wc -c < file` via `os.system` with output redirected
to a temp file, then read and `int()` it back. Genuinely gross.

### 2. `append()` of any heap element is E1406 under nogc enforcement — but comprehensions are fine

`xs.append(f"x{i}")` on an `own list[str]` is rejected ("retaining or aliasing
semantics"), yet `[f"x{i}" for i in range(3)]` builds the same list legally.
So growable-list code must be contorted into comprehension shape or avoided.
Neither `jac-native-memory` nor E1406's help text mentions that comprehensions
are the sanctioned alternative — the help says "use an owned-compatible
alternative" without naming one. This single gap forced the tool's
architecture into a streaming scan-one-entry-at-a-time design (which turned
out fine, but the checker chose it, not me).

### 3. The membrane treats a *named* string binding differently from the same value inlined in an f-string

Under enforcement:

```jac
d: own str = "/tmp/x";
os.system(d);                    # E1402: 'd' sealed into managed storage
os.system(f"mkdir -p {d}");      # accepted — d interpolated into a temp
```

Passing any named owned/borrowed `str` to `os.system`, `open`, or `f.write`
is E1402, while laundering the identical value through an inline f-string
temporary is accepted — and `print()` accepts named bindings just fine.
The workaround idiom (`sink(f"{x}")`) is load-bearing for any native program
that touches the OS, and is documented nowhere. Also note E1402's help text
suggests `managed(x)`, but `managed()` of a heap value is itself E1406 under
`--gc none` — the two diagnostics point at each other with no legal exit.

### 4. Method calls consume owned receivers *and* owned arguments

`hay.find(pat)` with `hay: own str, pat: own str` moves **both**; any later
use of either is E1301. `jac-native-memory` documents that passing an owned
local to a call consumes it, but not that the receiver of a method call
counts too. A read-only method (`find`, `startswith`, `strip`) consuming its
receiver forces everything into helper functions taking `&str` params.
`len(x)` notably does *not* consume, so some builtins borrow — the
consume-vs-borrow split across builtins/methods is undocumented and only
discoverable by compile error.

### 5. Slicing through a borrowed param yields an "ownerless" local (E1401)

Inside `def f(src: &str)`, the local `p = src[a:b];` is E1401 ("heap-typed
local has no ownership state") even though the help text says locals infer
from a fresh RHS — a slice **is** a fresh string. Annotating
`p: own str = src[a:b];` fixes it. Either the inference should cover this or
the guide should call it out.

### 6. Typed-base enum members are E1401 "heap-typed locals" under nogc enforcement

`enum EntryKind: int { END = 0, FILE = 1 }` — each member is reported as a
heap-typed local with no ownership state, with a help text about annotating
contract positions that cannot apply to an enum declaration. Int-base enums
are therefore unusable in enforced modules; this tool fell back to
`glob ENTRY_END: int = 0;` constants. The native guide advertises typed-base
enums as a supported feature, so the two features contradict each other.

### 7. W6002 lints `str.find` as "JS-idiomatic" — but it's the documented native idiom

Every `src.find(needle, start)` draws `W6002: use 'next() with generator'`.
`find` is in `jac-native`'s supported str-method table, and generators are a
listed *unsupported* feature on the native path — the lint's suggested fix is
a compile error in the codespace it fires in. Silenced project-wide via
`[check.lint] ignore = ["W6002"]`.

**Root cause (traced + fixed upstream).** This is not a native/Python parity
break — runtime parity is intact. W6002 comes from `PortabilityWarnPass`, a
JS-slop detector whose `JS_METHODS` table (`push`, `forEach`, `charAt`, ...)
is matched by method *name* alone, with no receiver or argument test. `find`
is the one entry in that table that is simultaneously a JS Array method
(takes a callback) and a legitimate Python str method (takes a substring) —
the single Python/JS homonym, and this tool happened to be built almost
entirely out of it. Fixed in jaseci branch
`fix/w6002-str-find-false-positive` (commit `2f08b7f9c`): `find` now warns
only when the call is JS-shaped — exactly one argument that is a lambda or a
name resolving to a function symbol — so `s.find("x")`, `s.find(pat)`, and
`s.find(pat, 2)` are clean while `items.find(callback)` still warns. The
`ignore` below stays until CI's pinned release ships the fix. The same
name-only matching can also hit user-defined methods that share a table name
(any object with a `.parse()` or `.assign()` method), which deserves its own
look upstream.

### 8. W5032 "not layout-compatible" fires on `own str` obj fields

`has path: own str;` on a plain obj warns `W5032: field has type 'own str'
which is not layout-compatible`. The ownership contract *requires* the
annotation (dropping it is E1401), so enforced modules cannot avoid this
warning on any obj carrying a string. One of the two diagnostics has to give.

### 9. Imported modules always nacompile under gc=cycles — the zero-RC contract is single-module only

With `main.na.jac` importing `manifest.na.jac`, and *all three* of
`--gc none`, `jac.toml [gc] default = "none"`, and
`[gc.enforce] modules = ["*"]` in effect, a scrubbed build reports:

```
rc-stats [main.na.jac]     gc=none   coverage=100.0% rc-free
rc-stats [manifest.na.jac] gc=cycles coverage=18.4%
```

and `--assert-no-rc` fails with a full page of `__rc_*` symbols. The E140x
*checks* do reach the imported module (jac check flags it as enforced by the
`"*"` pattern), but the emitted code still refcounts — so ownership
annotations are policed and then ignored at codegen. The dep-import path in
`na_compile_pass.impl.jac` builds the child `CompileOptions` from
`self.prog?._compile_options` with a silent `"cycles"` fallback, which is
what appears to be losing the mode. Until this is fixed a zero-RC program
must be a single module; this project collapsed to `main.na.jac` +
`main.impl.jac` (annexes share the module, so decl/impl separation still
works) and got `assert-no-rc ok`.

### 10. Native f-strings drop single-quote characters between two interpolations

Minimal repro (native, any gc mode):

```jac
a: own str = "AA";
b: own str = "BB";
print(f"'{a}' '{b}'");     # prints  'AA BB'   — should be  'AA' 'BB'
print(f"\"{a}\" \"{b}\""); # prints  "AA" "BB" — correct
print(f"x '{a}' y");       # correct — single interpolation is fine
```

The literal segment *between* two placeholders loses its single-quote
characters (double quotes survive). For a program that builds shell commands
this is catastrophic and silent: `curl ... -o '{part}' '{url}'` fuses both
arguments into one quoted blob and curl reports "no URL specified". This
tool now assembles every command by concatenating single-interpolation
pieces through a `qp()` quote helper.

### 11. `os.path.isfile` always returns False on the native path

```jac
with open("/tmp/y.txt", "w") as f { f.write("hi"); }
print(os.path.exists("/tmp/y.txt"));   # 1
print(os.path.isfile("/tmp/y.txt"));   # 0  — wrong, and no compile-time error
```

`jac-native` lists `isfile` in the supported `os.path` subset, but natively it
returns False for every input (Python backend returns True for the same
call). In this tool that silently broke three things at once — the manifest
cache re-fetched every run, finished files were re-downloaded, and `--status`
reported "pending" for files with partials on disk. Switched everything to
`os.path.exists`, which works. Same family as issue 1: the native `os.path`
shims aren't covered by the fail-loudly guarantee, and two of the four
"supported" members are broken.

### 12. The `[dev] jaclang_source` loop is broken in release binaries: ownership pass scheduling error

Installing a release binary (0.34.7) and pointing `[dev] jaclang_source` at a
source checkout — even the exact `v0.34.7` tag, so binary and source match —
fails every `jac check` and `jac nacompile` with:

```
scheduling error: pass OwnershipCheckPass requires analysis 'inference'
which has not run for module ... -- the schedule that reached this point
is missing a declared dependency.
```

Cold or warm cache makes no difference. The dev loop evidently only works
with a zig-linked dev binary (`zig build -Ddev`), which means CI cannot pin
a compiler *source* SHA the way this project wanted to: this repo's CI had
to fall back to the pinned release binary. `ownership_check_pass.jac`
declares `REQUIRES = ('cfg', 'inference')`; whatever registers the
`inference` analysis provider apparently doesn't happen on the
`JAC_NO_PRECOMPILE=1` dev-source path.

### 13. Release binary + newer compiler source: circular import in rc_facts_pass

Same setup as issue 12 but with source at `main` (cfae4422e, one day newer
than the binary):

```
cannot import name 'result_ownership' from partially initialized module
'jaclang.compiler.passes.main.rc_facts_pass' (most likely due to a
circular import)
```

So even if issue 12 were fixed, cross-version dev-source runs hit a real
import cycle in the ownership/RC pass cluster.

## Guide gaps (jac guide / SKILL.md)

- `jac-native-memory` shows single-file toys only. It never shows the shape a
  real enforced program must take: owned values at the top of `with entry`,
  every reusable read behind a `&`-param helper, dynamic strings crossing to
  stdlib sinks only as inline f-string temps. A worked "enforced-module
  idioms" section would have saved most of a day of probing.
- `jac-native` lists the supported `os.path` subset (`join`/`basename`/
  `exists`/`isfile`) but the practical consequence — *there is no way to stat
  a file's size natively* — deserves an explicit callout plus the `wc -c`
  workaround, since the promise that unsupported members fail loudly does not
  hold for `os.path` members (see issue 1).
- `include` is a reserved word (`include: own str = "";` is a parse error
  with an unhelpful `Missing ';'` cascade), but it is absent from
  `jac-core-cheatsheet`'s reserved-keyword list, which names `node`, `edge`,
  `visit`, etc. A downloader naturally wants a variable called `include`;
  the cheatsheet list should be the complete one.
- Nothing documents that `os.system` returns the raw POSIX wait status
  (exit code × 256) on the native path. Python-congruent, yes, but the guide's
  stdlib table is exactly where a one-liner would prevent the classic
  `rc == 1` bug.
