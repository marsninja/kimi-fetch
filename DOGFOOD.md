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
- Nothing documents that `os.system` returns the raw POSIX wait status
  (exit code × 256) on the native path. Python-congruent, yes, but the guide's
  stdlib table is exactly where a one-liner would prevent the classic
  `rc == 1` bug.
