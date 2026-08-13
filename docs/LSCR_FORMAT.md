# Decoding Director's compiled Lingo (`Lnam` / `Lctx` / `Lscr`)

**Nothing in this port implements any of this.** The engine runs Lingo from the
**source text** in each cast member's info block; the compiled form is not read.
`ENGINE_TODO.md` carries the gap and the measurement that says decoding it would
recover no behaviour from the six titles under `games/` -- 38,474 members carry a
script, 64 carry a `script_id` with no source text, and 0 of those 64 have a
handler. This document exists for the case that gap names: a **protected** movie
(`.dxr`/`.cxt`/`.dcr`), which ships bytecode with the source stripped. Written
2026-08-13.

Two independent passes went into it -- one deriving the layout from ScummVM and
ProjectorRays, one decoding the whole corpus -- and where they agree the claim is
marked MEASURED. The corpus pass is the stronger evidence: it decoded the handler
table of every one of the 38,474 scripts and found `handlersCount` equal to the
number of `on`/`factory`/`method` declarations in that member's own source text
for **38,410 of 38,410** that have source, with the handler *names* matching
through `Lnam` in every case. A layout that were wrong could not produce that.

A specification for turning a cast member's compiled script into the AST that
`lingo/lingo_interpreter.gd` already runs. Written to be implemented without
re-deriving anything.

## Sources and how to read the confidence markings

| Tag | Meaning |
| --- | --- |
| **[SV]** | ScummVM @ `805f259a19d71eb12db1e3b0b9b24c27ee18e8b6`, `engines/director/lingo/lingo-bytecode.cpp` (`compileLingoV4`, `addNamesV4`) and `cast.cpp:1820` (`Cast::loadLingoContext`). Fetched by `tools/fetch_scummvm_reference.sh`. |
| **[PR]** | ProjectorRays @ `6f9bcebf626b43719abe2affcbbcb041d154d666`, `src/lingodec/{script,context,handler,names}.cpp`, `src/lingodec/enums.h`. Not vendored; `pre-tools/projectorrays-0.2.0.exe` is a Windows binary, not source. |
| **[MEASURED]** | Read out of this corpus's own bytes and checked against a known answer. The tool that did it is described in §6. |

Every offset below that is marked **CONFIRMED** is agreed by [SV] and [PR]
*and* produced correct values on real data. **MEASURED-ONLY** means neither
reference decodes it and this document derived it from the corpus. **UNVERIFIED**
means one source states it and nothing checked it.

All three chunks are **big-endian regardless of the container's endianness**.
[PR] states this explicitly (`stream.endianness = Common::kBigEndian` in both
`Script::read` and `ScriptContext::read`); [SV] gets it from the endian-aware
stream. MEASURED: `games/piposh2/MASTER.CST` begins with the little-endian magic
`XFIR` and stores its mmap tags reversed (`rcsL`, `manL`), yet its `Lscr` header
only decodes when read big-endian — `totalLength` reads 3116, matching the
chunk's actual size, and `literalsOffset 1666 + 73 × 8 = 2250` lands exactly on
`literalsDataOffset`. Read the payload big-endian even when
`director_file.gd` reports the container as little-endian.

---

## 0. The version trap — read this before any offset

The corpus states file version **`0x57E`**. Two different scales are in play and
the two reference implementations branch on *different ones*.

| Scale | Value for this corpus | Where it comes from |
| --- | --- | --- |
| Raw file version | `0x57E` | `DRCF`/`VWCF` payload offset 36, big-endian u16 |
| Humanized version | **700** | `humanVersion(0x57E)` — `reference/scummvm/util.cpp:1316` |

`humanVersion` is a descending ladder: `0x57E` is `>= kFileVer700 (0x4C8)` and
`< kFileVer800 (0x582)`, so it lands on **700**. **These movies are D7, not D5.**
The task brief and `AGENTS.md:138` both say "D5 layout"; that phrase is about the
*cast member* reader, which branches at `>= kFileVer500` and therefore takes its
later arm. For Lingo it is the wrong label and will mislead anyone who then
compares 700 against `kFileVer500 = 0x4B1`.

### The version is per container, and `piposh2` is mixed

**Do not take a single version for a title.** MEASURED over `games/piposh2`, by
reading each container's own `DRCF`/`VWCF` version word:

| Stated version | Humanized | Containers with `Lscr` |
| --- | --- | --- |
| `0x57E` | 700 | 59 |
| `0x73A` | 850 | 2 (`DAY1.dir`, `HEZSAVE.DIR`) |
| none | — | 12 (external casts: `.cst`/`.cxt`) |

So `piposh2` contains **both** 700 and 850 containers, and the three
version-dependent quantities below differ between them. `container_versions.gd`
already hedges this ("Piposh 2's are mostly `0x57E`"); for Lingo, "mostly" is not
good enough, because the two need different structure sizes.

**External casts carry no config chunk at all**, so their version cannot be read
from the file. It has to come from the owning movie, or be detected (see the
detection trick at the end of this section).

### The three version-dependent quantities

| Quantity | `< 500` | `500`–`849` (700 here) | `>= 850` |
| --- | --- | --- | --- |
| Literal record size, i.e. the *table* stride | **6** (u16 type) | **8** (u32 type) | **8** |
| Handler record size | 42 | **42** | **46** (extra u32 at +42) |
| **Operand divisor** (`variableMultiplier`) | 6 | **8** | **1** |

**Rows 1 and 3 are different quantities that happen to be equal at 700.** That
coincidence is a trap, and [SV] falls into it: [SV] uses one value,
`constEntrySize`, for both. At 850 they diverge — the literal table still has
8-byte records, but the operand divisor becomes 1 — so [SV]'s conflation produces
a table read correctly and then indexed eight times too far.

The divisor is a **single** quantity shared by two different operand kinds:
[PR] applies `variableMultiplier()` to `pushcons` operands
(`handler.cpp:717`, `bytecode.obj / variableMultiplier()`) *and* to
`getparam`/`getlocal`/`setparam`/`setlocal` operands (`handler.cpp:748-778`).
Do not implement two divisors.

Sources and how each row is settled:

- **Literal record size.** `version >= kFileVer500` [SV] (raw) and
  `version >= 500` [PR] (humanized); both true at `0x57E`. At 850 [PR] keeps the
  u32 type, so the record stays 8 bytes. MEASURED at 700 (§4.1); at 850 the
  8-byte table stride is **inferred from [PR]** and not independently measured,
  because the operand divisor of 1 means the operands no longer reveal the
  stride.
- **Handler record size.** [PR] `Handler::readRecord` appends
  `uint32 stackHeight` when `script->version >= 850`. **[SV] has no
  `stackHeight` handling at all** and reads 42 bytes unconditionally, so [SV] is
  correct at 700 and **wrong at 850**. MEASURED both ways — decisively in
  `DAY1.dir` (`0x73A`), which has 5 scripts with two or more handlers: **all 5
  close at stride 46 and 0 of 5 close at stride 42**, using the handler-1 test
  below. `BYAIR.cst` (`0x57E`) closes at 42 (§3).
- **Operand divisor.** [PR] `Handler::variableMultiplier()` returns `1` for
  `>= 850`, `8` for `>= 500`, `6` otherwise. **[SV] has no `== 1` arm** — its
  `findVarV4` offers only 6 or 8 — so again [SV] is wrong at 850. MEASURED both
  ways and on both operand kinds (§4.1, §4.2).

The pattern is worth stating plainly: **[SV] is a correct reference for the 700
containers and an incorrect one for the 850 containers, and this corpus has
both.** Follow [PR] on all three rows.

**Detecting the sizes instead of trusting a version** (useful for external
casts, and a good assertion everywhere): in any script with two or more
handlers, handler 0's record gives `lineOffset + lineCount`, and handler 1's
`compiledOffset` must equal that (or that plus one, for 2-byte alignment). Try
42 and 46 and keep the one that closes. Separately, every handler record
satisfies `argumentOffset == compiledOffset + compiledLength` and
`localsOffset == argumentOffset + argumentCount * 2`; a record that fails either
was read at the wrong stride. Both checks are MEASURED to hold across
`games/piposh2`, and the second is what caught a stride error while this document
was being written. The first discriminates cleanly: on `DAY1.dir`'s five
multi-handler scripts it answers 5/5 at stride 46 and 0/5 at stride 42.
(`HEZSAVE.DIR`, the other `0x73A` container, has no script with two handlers, so
it cannot discriminate — which is also why `BYAIR.cst`, with its single handler,
could not have revealed the 42-vs-46 question on its own.)

Confirmed: `humanVersion` ladder read from `reference/scummvm/util.cpp:1316`.

---

## 1. `Lnam` — the name table

Every identifier in an `Lscr` (handler names, globals, properties, argument
names, local names, called-handler names, `the` property names) is an index into
this table. There is one `Lnam` per `Lctx`, and the `Lctx` header names which
chunk it is.

Header, from chunk payload offset 0 (payload = after the 8-byte tag+size chunk
header, which `director_file.gd:read_chunk` already strips):

| Off | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | u16 ×4 | unknown | [SV] reads and discards four u16s |
| 8 | u32 | `size` | chunk size; [SV] warns on mismatch but proceeds |
| 12 | u32 | `size` again | |
| **16** | **u16** | **`namesOffset`** | where the string data starts, relative to payload 0 |
| **18** | **u16** | **`namesCount`** | number of strings |

Strings begin at `namesOffset` and are **Pascal strings**: one length byte,
then that many bytes, packed with no padding or alignment. Read `namesCount` of
them consecutively.

Encoding: bytes, not UTF-8. [SV] passes them through `Cast::decodeString` (the
container's code page). This port already has `director/director_codepage.gd`
for exactly that; use it rather than `get_string_from_ascii()`, or Hebrew and
Russian handler names will corrupt. The header is minimum `0x14` = 20 bytes [SV].

**Status: CONFIRMED.** [SV] `addNamesV4` and [PR] `names.cpp` agree on offsets 16
and 18 and on the Pascal-string form. MEASURED: `BYAIR.cst` chunk 340 decodes to
6 names — `["mouseUp", "guard", "playFile", "sound", "soundspath", "play"]` —
which are exactly the identifiers appearing in that member's source text.

---

## 2. `Lctx` — the script context, and the `script_id` → `Lscr` mapping

`script_id` at cast-member info-block offset 16 (big-endian u32, read by
`director/director_cast.gd:385`) does **not** name an `Lscr` chunk. It is a
**1-based index into the `Lctx` entry array**, and the entry holds the chunk id.
Two levels of indirection.

**The tag in this corpus is mostly `LctX`, not `Lctx`.** MEASURED: 454 containers
under `games/` carry `LctX` and 136 carry `Lctx`. ScummVM looks only for `Lctx`,
so a decoder transcribed from it finds no script context in piposh 1 at all. Ask
for both spellings.

Header, from payload offset 0:

| Off | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | i32 | unknown | |
| 4 | i32 | unknown | |
| **8** | **i32** | **`entryCount`** | |
| 12 | i32 | `entryCount` again | |
| **16** | **u16** | **`entriesOffset`** | start of the entry array |
| 18 | i16 | unknown ([SV]: `entrySize`) | see note below |
| 20 | u32 | unknown | |
| 24 | u32 | unknown ([SV]: `fileType`) | |
| 28 | u32 | unknown | |
| **32** | **i32** | **`lnamChunkId`** | the `Lnam` chunk id (an mmap resource id, not an index) |
| 36 | u16 | `validCount` | |
| 38 | u16 | `flags` | |
| **40** | **i16** | **`firstUnused`** | head of the free list, see below |

Header length is `0x2a` = 42 bytes [SV] `hexdump(0x2a)`.

Entry array at `entriesOffset`, **12 bytes per entry**:

| Off | Size | Field |
| --- | --- | --- |
| +0 | u32 | unknown |
| **+4** | **i32** | **`chunkId`** — the `Lscr` chunk id, or `-1` for an empty slot |
| +8 | u16 | `entryFlags` |
| **+10** | **i16** | **`nextUnused`** — free-list link |

### The 1-based trap, stated precisely

[SV] loops `for (int16 i = 1; i <= itemCount; i++)`, reads into `entries[i - 1]`,
and passes `i` as `lctxIndex`. [PR] does the identical thing:
`for (uint32_t i = 1; i <= entryCount; i++) { auto section = sectionMap[i - 1]; ... scripts[i] = script; }`.

So:

```
lscr_chunk_id = entries[script_id - 1].chunkId
```

`script_id == 0` means the member has no script. A `chunkId` of `-1` means the
slot is empty even though a member points at it.

Do **not** use the `scriptNumber` field inside the `Lscr` header (offset 18) for
this. [SV] reads it and then explicitly throws it away with a named
counterexample: *"This field should match the script's index in Lctx, but this is
unreliable (e.g. script 261 in DATA/LEVEL1.DIR in betterd-win has this field
incorrectly set to 263)."* The `Lctx` index is authoritative.

### The free list

`firstUnused` (header +40) heads a singly linked list through each entry's
`nextUnused`. Walk it and mark those entries unused. [SV] then skips them with
three distinguishable cases: unused-and-empty (`chunkId < 0`), unused-but-not-
empty, and used-but-empty. Only `!unused && chunkId >= 0` gets compiled. A
correct decoder should skip unused entries even when they hold a chunk id,
because the chunk is stale.

### A container can have `Lscr` chunks and no `Lctx` at all

Neither reference handles this: [SV] only ever reaches `addCodeV4` from
`loadLingoContext`, so a container without an `Lctx` yields no scripts.

MEASURED: `games/piposh2/MASTER.CST` is an `XFIR` (little-endian) container with
**40 `Lscr` chunks and one `Lnam` (chunk 527) but no `Lctx` in either tag
spelling** (`grep` finds 80 `rcsL` and 2 `manL`, zero `xtcL`). Its 40 members
with `script_id > 0` have ids `1..40` and its `Lscr` chunks are mmap ids
`528..567`, consecutive.

Fallback that works: **`script_id N` → the `N`-th `Lscr` chunk in mmap order**,
and the `Lnam` is the container's only one. MEASURED: `script_id 1` → chunk 528
decodes to a 5-handler script whose first handler is named `jokesfunk`, and
`Lnam` 527's 94 names begin
`["jokesfunk", "runjokes", "cardsfunk", "runcards", "missionfunk", ...]` — the
handler names of that container's scripts, in order.

**Confidence: the fallback is MEASURED to produce coherent output, but it is not
verified handler-by-handler against source text the way §6 is.** It is the only
option available for these containers, and `MASTER.CST` is not a container to get
wrong — `AGENTS.md` notes it holds the globals and the inventory HUD. Verify it
member-by-member before relying on it.

**Status: CONFIRMED.** Every offset above is agreed by [SV] `Cast::loadLingoContext`
and [PR] `ScriptContext::read`, field for field, in the same order. MEASURED on
`BYAIR.cst` chunk 335: `entryCount=4`, `entriesOffset=96`, `lnamChunkId=340`,
`validCount=2`, `flags=0x5`, `firstUnused=3`; entries resolve
`script_id 1 → -1`, `2 → 341`, `3 → 342`, `4 → -1`, and member 61 (`script_id 3`)
reaches chunk 342, whose decode matches its source text (§6). The fields marked
"unknown" above are unknown in *both* references; do not invent meanings for them.

---

## 3. `Lscr` — the script chunk

Header is `0x5c` = 92 bytes [SV] `hexdump(0x5c)`. [PR] `Script::read` annotates
every offset in the source, and [SV] reads the same fields sequentially; the two
agree everywhere except offsets 44–47, noted below.

| Off | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 8 bytes | unknown | [SV] skips 8 |
| 8 | u32 | `totalLength` | = chunk payload size |
| 12 | u32 | `totalLength` again | |
| **16** | **u16** | **`codeStoreOffset`** | start of the bytecode + name-list region |
| 18 | u16 | `scriptNumber` | **unreliable, see §2** |
| 20 | i16 | unknown | |
| **22** | **i16** | **`parentNumber`** | for factories: the parent script's `Lctx` index minus 1; `-1` when none |
| 24 | 12 bytes | unknown | [SV] skips `0xC` |
| 36 | u16 | unknown | [SV]'s `// offset 36` anchor lands here |
| **38** | **u32** | **`scriptFlags`** | table below |
| 42 | i16 | unknown | |
| 44 | i32 | `castId` [PR] | [SV] instead skips 44–45 and reads a u16 `assemblyId` at 46, i.e. the low half of the same big-endian i32. Both call it unreliable and prefer the cast member found by `script_id`. |
| **48** | **i16** | **`factoryNameId`** | `Lnam` index; `-1` when not a factory |
| 50 | u16 | `eventMapCount` | [SV]'s `// offset 50 - contents map` anchor |
| 52 | u32 | `eventMapOffset` | |
| 56 | u32 | `eventMapFlags` | [SV]. [PR] labels this `handlerVectorsSize`; see the discriminating measurement below. |
| **60** | **u16** | **`propertiesCount`** | |
| **62** | **u32** | **`propertiesOffset`** | |
| **66** | **u16** | **`globalsCount`** | |
| **68** | **u32** | **`globalsOffset`** | |
| **72** | **u16** | **`handlersCount`** | |
| **74** | **u32** | **`handlersOffset`** | |
| **78** | **u16** | **`literalsCount`** | |
| **80** | **u32** | **`literalsOffset`** | literal *record table* |
| **84** | **u32** | **`literalsDataCount`** | byte size of the literal data store |
| **88** | **u32** | **`literalsDataOffset`** | literal data store |

The two `// offset` comments [SV] leaves in `compileLingoV4` are a free
self-check: if your field-by-field arithmetic does not put `scriptFlags`'
preceding u16 at 36 and `eventMapCount` at 50, you have slipped a field. Both
land correctly above.

**All offsets in this header and in the handler records are absolute offsets into
the `Lscr` chunk payload.** [SV] subtracts `codeStoreOffset` throughout only
because it copies `[codeStoreOffset, end)` into a separate buffer; do not
reproduce that subtraction if you index the payload directly.
MEASURED: seeking straight to `compiledOffset = 134` in the raw payload yields
correct bytecode (§6), with `codeStoreOffset = 92`.

### `scriptFlags` (offset 38)

From `reference/scummvm/types.h:86`:

| Bit | Name | Meaning for a decoder |
| --- | --- | --- |
| 0x0 | `kScriptFlagUnused` | **Bail out.** [SV] returns null. |
| 0x1 | `kScriptFlagFuncsGlobal` | |
| 0x2 | `kScriptFlagVarsGlobal` | |
| 0x3 | `kScriptFlagUnk3` | |
| **0x4** | **`kScriptFlagFactoryDef`** | This script is a factory. `factoryNameId` is its name; argument 0 of every handler is `me`. |
| 0x5–0x8 | `kScriptFlagUnk5..Unk7`, `kScriptFlagHasFactory` | |
| **0x9** | **`kScriptFlagEventScript`** | Handler 0 is unnamed top-level Lingo, not a handler. [SV] binds it to the generic event; [PR] sets `isGenericEvent`. |
| 0xa | `kScriptFlagEventScript2` | |
| 0xb–0xf | unknown | |

Bit numbers are shift counts: `kScriptFlagFactoryDef = (1 << 0x4) = 0x10`.

### Property and global name lists

Both are flat arrays of **i16 `Lnam` indices**, at `propertiesOffset` and
`globalsOffset`, `count` entries each. `-1` terminates early in the property
list [SV]; out-of-range indices are skipped with a warning. These are the
script-level `property` and `global` declarations.

Note for factories: [PR] drops a property literally named `me` from the property
list. Do the same or a factory grows a spurious `property me`.

**Status: CONFIRMED.** MEASURED on `BYAIR.cst` chunk 342: `codeStoreOffset=92`,
`handlersCount=1 @ 92`, `literalsCount=12 @ 314`, store `184 @ 410`,
`totalLength=598` = the chunk's actual size, `scriptFlags=0`, `parentNumber=-1`,
`factoryNameId=-1`.

### The event map (offsets 50/52/56) — [SV] is right, [PR] is wrong

[SV] describes it as *"an int16 array used to quickly access events. Its first
item is the index of the mouseDown handler or -1, its second the mouseUp handler,
etc. `eventMapFlags & (1 << 0)` indicates there is a mouseDown handler,
`& (1 << 1)` a mouseUp handler."* [PR] instead reads offset 56 as a size.

MEASURED on chunk 342: `eventMapCount=2`, `eventMapOffset=594`, word at
56 = `0x2`, and the two i16 slots at 594 read **`[-1, 0]`**. The script's one
handler is `mouseUp`. Slot 0 (mouseDown) is `-1`, slot 1 (mouseUp) is handler 0,
and bit 1 of `0x2` is set. `594 + 2*2 = 598` = exactly the chunk size.
**[SV]'s reading is confirmed and [PR]'s `handlerVectorsSize` label is a
misread.** A decoder does not need this table — the handler's own `nameId` is
enough — but it is a useful consistency check, and the handler record's
`vectorPos` field is its slot index (MEASURED: `vectorPos=1` for `mouseUp`).

### Literals (the constant store)

Two parts: a **record table** of fixed-size entries at `literalsOffset`, and a
**data store** at `literalsDataOffset` of `literalsDataCount` bytes.

Record, for this corpus (raw version `>= 0x4B1` / humanized `>= 500`):

| Off | Size | Field |
| --- | --- | --- |
| +0 | **u32** | `type` |
| +4 | u32 | `offset` / immediate value |

**Record size is 8 bytes here.** For raw version `< 0x4B1` the `type` is a u16
and the record is **6 bytes**. This size is load-bearing beyond the table itself
— see `pushcons` in §4.

| `type` | Meaning | How to read it |
| --- | --- | --- |
| 1 | String | `offset` is a byte offset into the data store. At that point: u32 `length`, then `length` bytes. The string is `length - 1` bytes plus a NUL [PR]; [SV] equivalently scans to the first NUL within `length`. Decode through the container code page. |
| 4 | Integer | `offset` **is the value**, a signed 32-bit int. No data-store access. |
| 9 | Float | `offset` is a data-store offset. u32 `length`, then `length` bytes: `length == 10` is an Apple SANE 80-bit extended float, `length == 8` is a big-endian IEEE double. Anything else is an error in both references. |

Any other type is unknown to both references.

**Status: CONFIRMED.** MEASURED: the 12 literals of chunk 342 decode to
`["guard1.aif", "guardspk", "guard2.aif", "hezspkguard", "guard3.aif",
"guardspk", "guard4.aif", "guardspk", "guard5.aif", "hezspkguard",
"guard6.aif", "guardspk"]`, which are the twelve string literals of that
member's source text, in source order. Types 4 and 9 are **UNVERIFIED** on this
corpus — this container has no integer or float literal (small integers are
pushed with `pushint`, not `pushcons`).

### Handler records

`handlersCount` records at `handlersOffset`. **42 (`0x2a`) bytes each in a 700
container, 46 in an 850 container** — see §0. [SV] `hexdump(0x2a)` and reads
exactly 42 bytes unconditionally; [PR] names every field and adds the 46th-byte
field for 850+.

| Off | Size | Field | Notes |
| --- | --- | --- | --- |
| **0** | **i16** | **`nameId`** | `Lnam` index. Invalid + `kScriptFlagEventScript` on handler 0 → unnamed top-level script. |
| 2 | u16 | `vectorPos` | slot in the event map |
| **4** | **u32** | **`compiledLength`** | bytecode byte count |
| **8** | **u32** | **`compiledOffset`** | absolute offset into the chunk payload |
| **12** | **u16** | **`argumentCount`** | |
| **14** | **u32** | **`argumentOffset`** | i16 `Lnam` index array |
| **18** | **u16** | **`localsCount`** | |
| **20** | **u32** | **`localsOffset`** | i16 `Lnam` index array |
| **24** | **u16** | **`globalsCount`** | i16 `Lnam` index array — **per-handler `global` declarations** |
| **26** | **u32** | **`globalsOffset`** | |
| 30 | u32 | unknown | |
| 34 | u16 | unknown | |
| **36** | **u16** | **`lineCount`** | |
| **38** | **u32** | **`lineOffset`** | line-number table, §3.1 |
| 42 | u32 | `stackHeight` | **Present only when humanized version >= 850.** [PR] names it and leaves it unused; [SV] does not know it exists. |

The three name lists are read the same way: seek to the offset, read `count`
i16s, look each up in `Lnam`.

**The per-handler globals list at +24/+26 is where `global` declarations
actually live, and [SV] does not read it.** [SV] consumes offsets 24–41 as nine
anonymous `readUint16()` calls and relies on `cb_globalpush`/`cb_globalassign`
carrying the name inline at run time instead. A decoder targeting a *source-like
AST* needs the list, because the port's parser emits a `global` node for the
declaration. MEASURED: chunk 342's single handler has
`globalsCount = 2 → ["guard", "soundspath"]`, matching its
`global guard, soundspath` line exactly, while the *script-level*
`globalsCount` at header +66 is 0. Reading only the header list would drop the
declaration entirely.

Special cases from [SV]:
- Argument 0 of a factory handler whose name index is invalid is `me`.
- An argument or local with an out-of-range index gets a synthetic
  `arg_<n>` / `var_<n>` name rather than failing the handler.

**Status: CONFIRMED** for offsets 0–41 ([SV] byte count + [PR] field names +
MEASURED). The record *size* is MEASURED both ways: 42 in `BYAIR.cst` (`0x57E`),
where the chain `compiledOffset 134 + compiledLength 153 → globalsOffset 288 →
lineOffset 292` closes exactly at stride 42 and would overlap the record itself
at 46; and 46 in `MASTER.CST`, where handler 1's record only decodes when read at
138 = 92 + 46, giving `compiledOffset 340` — exactly where handler 0's line table
ends — and `argumentOffset 910 = 340 + 570`, `localsOffset 912 = 910 + 1*2`,
`lineOffset 916 = 912 + 2*2`. Reading that file at stride 42 produces
`compiledLength = 131071`, which is how the error announces itself.

Two caveats on that evidence, because they matter for what rests on what:

- **The `MASTER.CST` arithmetic depends only on the chunk's internal
  consistency**, not on the member→chunk mapping used to reach it. So the
  46-byte finding does not inherit the unverified status of §2's no-`Lctx`
  fallback.
- **`MASTER.CST` cannot establish the *version* rule**, because it is an external
  cast with no config chunk and so reports version 0. The container that ties 850
  to 46 is **`DAY1.dir`**, which states `0x73A` and closes 5 of 5 at stride 46
  and 0 of 5 at stride 42 (§0).

### 3.1 The line-number table — MEASURED-ONLY

Neither reference decodes this. [PR] reads `lineCount`/`lineOffset` and leaves
`// yet to implement`; [SV] skips the fields entirely. It is decoded here
because it is the only thing that can attach source line numbers to AST nodes,
and every node the port's parser emits carries a `line` field.

**Format: `lineCount` entries, one unsigned byte each, no header. Entry `i` is
the number of bytecode bytes that source line `i` compiled to.** Consecutive
sums give the byte position at which each source line's code begins.

MEASURED on chunk 342: `lineCount = 21`, `lineOffset = 292`, and the 21 bytes
there are

```
0 7 14 6 14 6 14 6 8 0 9 14 6 14 6 8 0 14 6 0 0
```

which sum to 152 against a `compiledLength` of 153 (the trailing 1-byte `ret` is
not attributed to a line). Line by line against the known source:

| Entry | Source line | Bytes | Instructions |
| --- | --- | --- | --- |
| 0 | `global guard, soundspath` | 0 | none — a declaration emits nothing |
| 1 | `if guard = 0 then` | 7 | `getglobal`(2) `pushzero`(1) `eq`(1) `jmpifz`(3) |
| 2 | `sound playFile 1, soundspath & "guard1.aif"` | 14 | `pushsymb`(2) `pushint`(3) `getglobal`(2) `pushcons`(2) `joinstr`(1) `pusharglistnoret`(2) `extcall`(2) |
| 3 | `play frame "guardspk"` | 6 | `pushcons`(2) `pusharglistnoret`(2) `extcall`(2) |
| 8 | `guard = 1` | 8 | `pushint`(3) `setglobal`(2) `jmp`(3) |
| 9 | `else` | 0 | |
| 10 | `if guard = 1 then` | 9 | `getglobal`(2) `pushint`(3) `eq`(1) `jmpifz`(3) |
| 19, 20 | `end if`, `end if` | 0, 0 | |

All 21 entries account for exactly the bytes the disassembly shows at those
positions. Entry 0 corresponds to the first line *inside* the handler; the
`on mouseUp` line itself is not represented.

**Confidence: high but single-sourced.** Verified byte-for-byte against 21 lines
of known source in one handler. It has *not* been checked against a handler with
arguments, a `repeat` loop, or a line compiling to more than 255 bytes — that
last case is the obvious way this format could be wrong, since a single byte
cannot express it. Treat line numbers as best-effort: if the table disagrees
with the byte count, drop the line attribution rather than the handler.

---

## 4. The opcode table

### The size-class rule

A single opcode byte encodes both the operation and its operand width. From
[PR] `Handler::readData`:

```
canonical_opcode = (op >= 0x40) ? (0x40 + (op % 0x40)) : op
```

and the operand width:

| Raw byte | Operand |
| --- | --- |
| `0x00`–`0x3F` | **none** — instruction is 1 byte |
| `0x40`–`0x7F` | **1 byte** |
| `0x80`–`0xBF` | **2 bytes**, big-endian |
| `0xC0`–`0xFF` | **4 bytes**, big-endian |

So `0x41`, `0x81` and `0xC1` are all `pushint` with 1-, 2- and 4-byte operands.
[SV] encodes the same rule differently — a `proto` string per table row (`"B"`,
`"W"`, `"b"`, `"w"`) plus a fallthrough that treats any unknown opcode `< 0x40`
as 1 byte, `< 0x80` as 2, and otherwise as 3 — which means **[SV] cannot decode
the `0xC0`+ four-byte forms at all**; it mis-sizes them as 3 bytes and desyncs
the stream. Use [PR]'s rule.

Signedness (from [PR], and it matters): the operand is read **signed** for
`pushint` (`0x41`) and `pushint16` (`0x6E`), unsigned for everything else.
[SV] agrees via its `"B"`/`"W"` (signed) vs `"b"`/`"w"` (unsigned) protos, and
adds an `n` proto meaning "negate the operand", used only by `endrepeat`.

MEASURED: this corpus emits `0x81 pushint <i16>` even for the constant `1`, and
`0x44 pushcons <u8>`. No `0xC0`+ byte appears in the containers sampled, but
that is not a guarantee.

### Single-byte opcodes (`0x00`–`0x3F`), no operand

| Op | [PR] name | [SV] handler | Stack effect | Lingo |
| --- | --- | --- | --- | --- |
| 0x01 | `ret` | `c_procret` | — | `end` / `exit` |
| 0x02 | `retfactory` | `c_procret` | — | factory return |
| 0x03 | `pushzero` | `cb_zeropush` | → 1 | integer `0` |
| 0x04 | `mul` | `c_mul` | 2 → 1 | `*` |
| 0x05 | `add` | `c_add` | 2 → 1 | `+` |
| 0x06 | `sub` | `c_sub` | 2 → 1 | `-` |
| 0x07 | `div` | `c_div` | 2 → 1 | `/` |
| 0x08 | `mod` | `c_mod` | 2 → 1 | `mod` |
| 0x09 | `inv` | `c_negate` | 1 → 1 | unary `-` |
| 0x0a | `joinstr` | `c_ampersand` | 2 → 1 | `&` |
| 0x0b | `joinpadstr` | `c_concat` | 2 → 1 | `&&` |
| 0x0c | `lt` | `c_lt` | 2 → 1 | `<` |
| 0x0d | `lteq` | `c_le` | 2 → 1 | `<=` |
| 0x0e | `nteq` | `c_neq` | 2 → 1 | `<>` |
| 0x0f | `eq` | `c_eq` | 2 → 1 | `=` |
| 0x10 | `gt` | `c_gt` | 2 → 1 | `>` |
| 0x11 | `gteq` | `c_ge` | 2 → 1 | `>=` |
| 0x12 | `and` | `c_and` | 2 → 1 | `and` |
| 0x13 | `or` | `c_or` | 2 → 1 | `or` |
| 0x14 | `not` | `c_not` | 1 → 1 | `not` |
| 0x15 | `containsstr` | `c_contains` | 2 → 1 | `contains` |
| 0x16 | `contains0str` | `c_starts` | 2 → 1 | `starts` |
| 0x17 | `getchunk` | `c_of` | 3 → 1 | `char x of y` etc. |
| 0x18 | `hilitechunk` | `cb_hilite` | 1 → 0 | `hilite <chunk>` |
| 0x19 | `ontospr` | `c_intersects` | 2 → 1 | `sprite a intersects b` |
| 0x1a | `intospr` | `c_within` | 2 → 1 | `sprite a within b` |
| 0x1b | `getfield` | `c_field` | 1 → 1 (D5+: 2 → 1) | `field <n>` |
| 0x1c | `starttell` | `c_tell` | 1 → 0 | `tell <target>` |
| 0x1d | `endtell` | `c_telldone` | — | `end tell` |
| 0x1e | `pushlist` | `cb_list` | argc+1 → 1 | `[a, b, c]` |
| 0x1f | `pushproplist` | `cb_proplist` | argc+1 → 1 | `[#a: 1, #b: 2]` |
| **0x21** | **`swap`** | **absent in [SV]** | 2 → 2 | no source form |

`0x20` is not assigned in either source. `0x21` is [PR]-only: **[SV] would decode
it as an unimplemented 1-byte instruction and warn**. Not observed in this
corpus.

### Multi-byte opcodes (canonical `0x40`+)

Widths: `0x4x` = 1-byte operand, `0x8x` = 2-byte, `0xCx` = 4-byte.

| Canon | [PR] name | [SV] handler / proto | Operand | Stack effect |
| --- | --- | --- | --- | --- |
| 0x41 | `pushint` | `c_intpush` `"B"` | **signed** immediate | → 1 |
| 0x42 | `pusharglistnoret` | `c_argcnoretpush` `"b"` | count | marks argc; call discards result |
| 0x43 | `pusharglist` | `c_argcpush` `"b"` | count | marks argc; call keeps result |
| **0x44** | **`pushcons`** | **special-cased in [SV]** | **byte offset into the literal record table** | → 1 |
| 0x45 | `pushsymb` | `c_namepush` `"bN"` | name index | → 1 (symbol) |
| 0x46 | `pushvarref` | `cb_varrefpush` `"bN"` | name index | → 1 (varref) |
| 0x48 | `getglobal2` | `cb_globalpush` `"bN"` | name index | → 1. [SV]: "used in event scripts" |
| 0x49 | `getglobal` | `cb_globalpush` `"bN"` | name index | → 1 |
| 0x4a | `getprop` | `cb_thepush` `"bN"` | name index | → 1 — property of `me` |
| 0x4b | `getparam` | `cb_varpush` `"bpaN"` | **arg slot**, see below | → 1 |
| 0x4c | `getlocal` | `cb_varpush` `"bpvN"` | **local slot**, see below | → 1 |
| 0x4e | `setglobal2` | `cb_globalassign` `"bN"` | name index | 1 → 0 |
| 0x4f | `setglobal` | `cb_globalassign` `"bN"` | name index | 1 → 0 |
| 0x50 | `setprop` | `cb_theassign` `"bN"` | name index | 1 → 0 |
| 0x51 | `setparam` | `cb_varassign` `"bpaN"` | arg slot | 1 → 0 |
| 0x52 | `setlocal` | `cb_varassign` `"bpvN"` | local slot | 1 → 0 |
| **0x53** | **`jmp`** | `c_jump` `"jb"` | **forward delta**, see below | — |
| **0x54** | **`endrepeat`** | `c_jump` `"jbn"` | **backward delta** (operand negated) | — |
| **0x55** | **`jmpifz`** | `c_jumpifz` `"jb"` | forward delta | 1 → 0 |
| 0x56 | `localcall` | `cb_localcall` `"b"` | **handler index within this script** | argc+1 → 0 or 1 |
| 0x57 | `extcall` | `cb_call` `"bN"` | name index | argc+1 → 0 or 1 |
| 0x58 | `objcallv4` | `cb_objectcall` `"b"` | var type nibble | argc+2 → 0 or 1 |
| 0x59 | `put` | `cb_v4assign` `"b"` | `(op << 4) | varType` | 2 → 0 |
| 0x5a | `putchunk` | `cb_v4assign2` `"b"` | `(op << 4) | varType` | 2+ → 0 |
| 0x5b | `deletechunk` | `cb_delete` `"b"` | var type | 1+ → 0 |
| 0x5c | `get` | `cb_v4theentitypush` `"b"` | **bank**, see §4.3 | 1+ → 1 |
| 0x5d | `set` | `cb_v4theentityassign` `"b"` | bank | 2+ → 0 |
| 0x5f | `getmovieprop` | `cb_thepush2` `"bN"` | name index | → 1 |
| 0x60 | `setmovieprop` | `cb_theassign2` `"bN"` | name index | 1 → 0 |
| 0x61 | `getobjprop` | `cb_objectfieldpush` `"bN"` | name index | 1 → 1 |
| 0x62 | `setobjprop` | `cb_objectfieldassign` `"bN"` | name index | 2 → 0 |
| 0x63 | `tellcall` | `cb_call` `"bN"` | name index | argc+1 → 0 or 1 |
| **0x64** | **`peek`** | `c_stackpeek` `"b"` | depth | duplicates stack[-1-n] |
| **0x65** | **`pop`** | `c_stackdrop` `"b"` | count | n → 0 |
| 0x66 | `thebuiltin` | `cb_v4theentitynamepush` `"bN"` | name index | argc+1 → 1 |
| 0x67 | `objcall` | `cb_call` `"bN"` | name index | argc+1 → 0 or 1. [SV]: "D5+ objcall" |
| **0x6d** | **`pushchunkvarref`** | **absent in [SV]** | ? | ? |
| **0x6e** | **`pushint16`** | **absent in [SV]** | signed | → 1 |
| **0x6f** | **`pushint32`** | **absent in [SV]** | signed | → 1 |
| **0x70** | **`getchainedprop`** | **absent in [SV]** | name index | 1 → 1 |
| **0x71** | **`pushfloat32`** | **absent in [SV]** | float bits | → 1 |
| **0x72** | **`gettoplevelprop`** | **absent in [SV]** | name index | → 1 |
| **0x73** | **`newobj`** | **absent in [SV]** | name index | argc+1 → 1 |

`0x47`, `0x4d`, `0x5e`, `0x68`–`0x6c` are unassigned in both sources.

The last seven rows are **[PR]-only, D6+ verbose/dot-syntax opcodes**. They are
documented here rather than omitted, but they are **unexercised by this corpus**
and their operand semantics are unverified. [SV] would decode each as an
"unimplemented instruction" and emit a stub. A decoder should emit a recognisable
`unknown_opcode` node rather than guessing, so a title that does use them fails
loudly at one node instead of silently mis-decoding a whole handler.

### 4.1 `pushcons` (0x44) — the operand is a byte offset at 700, an index at 850

In a 700 container the operand is a **byte offset into the literal record
table**; in an 850 container it is a **direct index**. Divide by the shared
operand divisor from §0:

```
literal_index = operand / variable_multiplier   # 8 at 700, 1 at 850, 6 below 500
```

[SV] warns when the operand is not an exact multiple and then divides anyway —
using `constEntrySize`, which is why [SV] is wrong at 850 (§0).

MEASURED at 700: chunk 342's twelve `pushcons` operands are
`0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88` → indices 0–11, and across all
`0x57E` containers of `piposh2` every `pushcons` operand is a multiple of 8. With
a divisor of 6 the divisions would not come out whole, so this also confirms the
8-byte literal record at 700.

MEASURED at 850: in `DAY1.dir` (`0x73A`), read at the correct 46-byte handler
stride, the `pushcons` operands are **consecutive integers `0, 1, 2, … 23`** —
not multiples of anything. Divisor **1**, matching [PR] exactly. Note this means
the operands no longer reveal the literal *table* stride at 850; that it remains
8 is taken from [PR] and is the one unmeasured link in this section.

### 4.2 Argument and local slots (`0x4b`, `0x4c`, `0x51`, `0x52`)

The operand is a **byte offset in a 700 container and a direct index in an 850
one**. Divide by the multiplier to index the handler's argument or local name
list:

| Version (humanized) | Multiplier |
| --- | --- |
| `>= 850` | **1** — the operand is already the index |
| `500`–`849` (most of this corpus) | **8** |
| `< 500` | 6 |

This is [PR] `Handler::variableMultiplier()`. **[SV] has no `1` arm**: its
`findVarV4` offers only 6 or 8, and its `p` proto divides by `constEntrySize`
unconditionally, so it divides an 850 container's operands by 8 and resolves
every local to local 0.

**Status: MEASURED both ways, and this is the one section of this document that
was wrong before it was measured.**

- 700 containers (filtered to `DRCF` version `0x57E`): across 37 handlers with
  arguments or locals, the distinct operands observed are exactly
  `[0, 8, 16, 24, 32, 40, 48, 56]` — **every one a multiple of 8**. A handler
  with `argumentCount=3, localsCount=2` in `AIR1.dir` uses `{0, 8, 16}`,
  i.e. indices `{0, 1, 2}`. Multiplier **8** confirmed.
- 850 containers: operands are small consecutive integers whose range matches the
  count exactly — `localsCount=3` → `{0, 1, 2}`, `localsCount=5` →
  `{0, 1, 2, 3, 4}`, `localsCount=1` → `{0}`, over six independent handlers.
  Multiplier **1** confirmed.

A warning about how to measure this, because the first attempt got the opposite
answer: sampling a title's containers without filtering by version mixes the two
conventions and yields operands that are neither consistently indices nor
consistently multiples of 8. Worse, reading an 850 container at stride 42
desyncs the handler table, and a desynced disassembly emits plausible-looking
small operands. **Filter by version and validate the record chain (§0) before
believing any operand.**

`findVarV4`'s `varType` nibble, used by `objcallv4`, `put`, `putchunk`,
`deletechunk`:

| Type | Meaning |
| --- | --- |
| 1, 2 | global |
| 3 | property / instance variable |
| 4 | argument |
| 5 | local |
| 6 | field (D5+: pops a cast-lib id first) |

### 4.3 `the` entity banks (`0x5c` get, `0x5d` set)

The operand is a **bank** number; the *first argument on the stack* selects the
field within that bank. The pair `(bank << 8) | firstArg` keys the
`lingoV4TheEntity` table in [SV] `lingo-bytecode.cpp:149`, whose rows carry
`(entity, field, writable, argsType)`. `argsType` says what else to pop:
`kTEANOArgs` (nothing), `kTEAItemId` (an id — and for `the cast`/`the field` at
D5+, an id *and* a cast-lib id), `kTEAString`, `kTEAMenuId`,
`kTEAMenuIdItemId`, `kTEAChunk`.

The table is ~180 rows. Do not retype it; read it from
`reference/scummvm/lingo/lingo-bytecode.cpp` after
`tools/fetch_scummvm_reference.sh`. Bank → AST node is in §5.

**Status: the opcode numbers and names are CONFIRMED** where [SV] and [PR] agree
(0x01–0x1f, 0x41–0x67, minus the gaps). Stack effects are from [SV]'s
implementations, single-sourced. Twelve distinct opcodes were MEASURED end to end
in §6.

---

## 5. The target AST

The existing interpreter consumes plain GDScript `Dictionary` nodes keyed
`"node"`. The list below is taken from `lingo/compile/lingo_parser.gd`'s own
constructors (46 node types) and from real output of
`godot --headless --script tools/lingo_parse.gd -- --root piposh2 --file BYAIR.cst --member 61 --dump`.

Top level: `{"script": <key>, "handlers": [<handler>, ...]}`.

Every node also carries `"line": <int>`.

### Node types and their exact fields

| Node | Fields |
| --- | --- |
| `handler` | `name`, `params` (array of names), `body` (array) |
| `global` | `names` (array of strings) |
| `property` | `names` (array of strings) |
| `assign` | `target`, `value` |
| `put` | `mode`, `value`, `target` |
| `put_echo` | `value` |
| `put_echo_many` | `values` |
| `call_stmt` | `call` |
| `call` | `callee`, `args`, `command` (bool) |
| `if` | `cond`, `then` (array), `else` (array or null) |
| `case` | `subject`, `branches` |
| `repeat_while` | `cond`, `body` |
| `repeat_with` | `var`, `from`, `to`, `body` |
| `repeat_in` | `var`, `seq`, `body` |
| `repeat_forever` | `body` |
| `exit_repeat` | — |
| `next_repeat` | — |
| `exit` | — |
| `return` | `value` |
| `tell` | `target`, `body` |
| `when` | `event`, `body` |
| `binary` | `op`, `left`, `right` |
| `unary` | `op`, `value` |
| `var` | `name` |
| `num` | `value` |
| `int` | `value` |
| `str` | `value` |
| `sym` | `value` |
| `list` | `items` |
| `proplist` | `pairs` |
| `dot` | `target`, `prop` |
| `index` | `target`, `index` |
| `chunk` | `kind`, `start`, `stop`, (source) |
| `count` | `unit`, `source` |
| `delete_chunk` | `target` |
| `field` | `name`, `cast` |
| `sprite_ref` | `which` |
| `sprite_number` | `which` |
| `sprite_prop` | `prop`, `which` |
| `member_ref` | `which`, `cast` |
| `member_number` | `which`, `cast` |
| `member_prop` | `prop`, `which`, (cast) |
| `cast_prop` | `prop`, `which` |
| `field_prop` | `prop`, `name`, `cast` |
| `sound_prop` | `prop`, `which` |
| `window_prop` | `prop`, `which` |
| `prop` | `prop`, `words` (lowercased adjectives) — a bare `the <prop>` |
| `prop_of` | `prop`, `target` — `the <prop> of <expr>` |

### Opcode → node, where the mapping is direct

| Opcodes | Node |
| --- | --- |
| 0x04–0x08, 0x0a–0x0d, 0x0e–0x13, 0x15, 0x16 | `binary` with `op` = `* + - / mod & && < <= <> = > >= and or contains starts` |
| 0x09, 0x14 | `unary` with `op` = `-` / `not` |
| 0x41, 0x03, 0x6e, 0x6f | `num` |
| 0x71 | `num` (float) |
| 0x44 type 1 | `str`; type 4 → `num`; type 9 → `num` |
| 0x45 | `sym` |
| 0x49, 0x48 | `var` (name from `Lnam`); the declaration list → `global` |
| 0x4f, 0x4e | `assign` with `target` = `var` |
| 0x4b, 0x4c | `var` (name from the handler's arg/local list) |
| 0x51, 0x52 | `assign` with `target` = `var` |
| 0x4a | `prop`-like read of `me`'s property → `var` (properties are plain names in scope) |
| 0x50 | `assign` to that name |
| 0x5f, 0x60 | `prop` / `assign` to `prop` — movie-level `the <name>` |
| 0x61, 0x62 | `dot` / `assign` to `dot` |
| 0x17 | `chunk` |
| 0x1b | `field` |
| 0x19, 0x1a | `binary` with `op` = `intersects` / `within` |
| 0x1c/0x1d | `tell` |
| 0x1e, 0x1f | `list` / `proplist` |
| 0x18 | a `hilite` `call_stmt` |
| 0x5b | `delete_chunk` |
| 0x56, 0x57, 0x63, 0x67 | `call`; wrapped in `call_stmt` when the argc marker was `0x42` (`pusharglistnoret`) |
| 0x01, 0x02 | end of handler; a mid-handler `ret` is `exit` |
| 0x66 | `prop` (a `the <builtin>` with argc 0) |
| 0x59 | `assign` when the op nibble is 1; `put` with `mode` = after/before for 2/3 |
| 0x5a | same, but `target` is a `chunk` |

`the` entity banks (`0x5c`/`0x5d`) map by bank:

| Bank | Node |
| --- | --- |
| 0x00, 0x07, 0x08 | `prop` / `assign` to `prop` (movie and system properties) |
| 0x00 0x0c–0x0f, 0x01 | `count` or `chunk` (`the last word of`, `the number of chars in`) |
| 0x02, 0x03 | menus — **no node exists** |
| 0x04 | `sound_prop` |
| 0x06 | `sprite_prop` |
| 0x09 | `cast_prop` / `member_prop` |
| 0x0a, 0x0c | `chunk` + a text property — needs `field_prop`/`member_prop` on a `chunk` target |
| 0x0b | `field_prop` |
| 0x0d | `member_prop` (digital video: `loop`, `duration`, `controller`, `directToStage`, `sound`) |

`window_prop` has no bank; `tell <window>` reaches it through `0x1c`.

---

## 6. Worked example — verified against known source

`games/piposh2/PIP2DATA/BYAIR.cst`, cast member **61**, `script_id` **3**. It
carries **both** source text and a compiled script, so the expected answer is
known. (38,396 members do — see §8 — which is what makes the differential oracle
possible.) Its container states `0x57E`, so the 42-byte handler record and the
×8 arg/local multiplier apply.

Chain: member 61 info block offset 16 → `script_id = 3`. `Lctx` is chunk 335;
its entry array at offset 96, entry `3 - 1 = 2`, field +4 → **chunk 342**.
`Lnam` is chunk **340** (from `Lctx` +32), 6 names:

```
0 mouseUp   1 guard   2 playFile   3 sound   4 soundspath   5 play
```

`Lscr` chunk 342, 598 bytes. Header decode:

```
totalLength      598  (= chunk size)
codeStoreOffset   92
scriptNumber       2   (ignored — Lctx index 3 is authoritative)
parentNumber      -1
scriptFlags      0x0   (not a factory, not an event script)
factoryNameId     -1
eventMap           2 slots @ 594, flags 0x2, slots [-1, 0]
properties         0 @ 92
globals            0 @ 92     <-- script-level; the declaration is per-handler
handlers           1 @ 92
literals          12 @ 314, data store 184 bytes @ 410
```

Handler record at 92 (42 bytes):

```
nameId             0  -> "mouseUp"
vectorPos          1  (event-map slot 1 = mouseUp)
compiledLength   153
compiledOffset   134
argumentCount      0
localsCount        0
globalsCount       2  -> ["guard", "soundspath"]
lineCount         21 @ 292
```

Literals: `guard1.aif`, `guardspk`, `guard2.aif`, `hezspkguard`, `guard3.aif`,
`guardspk`, `guard4.aif`, `guardspk`, `guard5.aif`, `hezspkguard`,
`guard6.aif`, `guardspk`.

### Bytes → instructions → Lingo

Bytecode at 134, offsets shown relative to the handler start.

```
   0: 49 01     getglobal 1        ; guard          |  if guard = 0 then
   2: 03        pushzero           |
   3: 0f        eq                 |
   4: 95 00 47  jmpifz 71 -> 75    |
   7: 45 02     pushsymb 2         ; playFile       |  sound playFile 1, soundspath & "guard1.aif"
   9: 81 00 01  pushint 1          |
  12: 49 04     getglobal 4        ; soundspath     |
  14: 44 00     pushcons 0         ; "guard1.aif"   |
  16: 0a        joinstr            |
  17: 42 03     pusharglistnoret 3 |
  19: 57 03     extcall 3          ; sound          |
  21: 44 08     pushcons 8         ; "guardspk"     |  play frame "guardspk"
  23: 42 01     pusharglistnoret 1 |
  25: 57 05     extcall 5          ; play           |
  ...  (guard2/hezspkguard, guard3/guardspk repeat the same two shapes)
  67: 81 00 01  pushint 1          |  guard = 1
  70: 4f 01     setglobal 1        ; guard          |
  72: 93 00 50  jmp 80 -> 152      |  (skip the else)
  75: 49 01     getglobal 1        ; guard          |  else / if guard = 1 then
  77: 81 00 01  pushint 1          |
  80: 0f        eq                 |
  81: 95 00 33  jmpifz 51 -> 132   |
  84: ...       (guard4/guardspk, guard5/hezspkguard)                     |
 124: 81 00 02  pushint 2          |  guard = 2
 127: 4f 01     setglobal 1        ; guard          |
 129: 93 00 17  jmp 23 -> 152      |
 132: ...       (guard6/guardspk)  |  else
 152: 01        ret                |  end
```

The source text stored in the same member's info block is:

```lingo
on mouseUp
  global guard, soundspath
  if guard = 0 then
    sound playFile 1, soundspath & "guard1.aif"
    play frame "guardspk"
    sound playFile 1, soundspath & "guard2.aif"
    play frame "hezspkguard"
    sound playFile 1, soundspath & "guard3.aif"
    play frame "guardspk"
    guard = 1
  else
    if guard = 1 then
      sound playFile 1, soundspath & "guard4.aif"
      play frame "guardspk"
      sound playFile 1, soundspath & "guard5.aif"
      play frame "hezspkguard"
      guard = 2
    else
      sound playFile 1, soundspath & "guard6.aif"
      play frame "guardspk"
    end if
  end if
end
```

**The decode matches the source exactly**: same handler name, same globals, same
twelve literals in order, same three-way branch structure, same nesting. Nothing
in the disassembly is unaccounted for and nothing in the source is missing from
it.

### Jump targets — the rule this example pins down

`target = (byte position of the opcode) + operand`, in handler-relative bytes.

- `jmpifz` at 4, operand 71 → 75, the start of the `else`. ✓
- `jmp` at 72, operand 80 → 152, the `ret`. ✓
- `jmp` at 129, operand 23 → 152, the same `ret`. ✓

Three independent confirmations. Note this is **not** what [SV] appears to do:
[SV] computes `oldTarget = (jump operand index - 1) + jump` in *instruction
index* space, because it is re-emitting into its own instruction array where one
"slot" is one word. Working on raw bytes, use the byte rule above.

`endrepeat` (0x54) is the same rule with the operand **negated** ([SV]'s `n`
proto), giving a backward branch. **UNVERIFIED** — no loop appears in this
handler.

### The AST this should produce

Feeding the same member's source through the existing parser
(`tools/lingo_parse.gd --member 61 --dump`) produces, abbreviated:

```json
{"node": "handler", "name": "mouseUp", "params": [], "body": [
  {"node": "global", "names": ["guard", "soundspath"], "line": 2},
  {"node": "if",
   "cond": {"node": "binary", "op": "=",
            "left": {"node": "var", "name": "guard", "line": 3},
            "right": {"node": "num", "value": 0, "line": 3}, "line": 3},
   "then": [
     {"node": "call_stmt", "call": {"node": "call",
       "callee": {"node": "var", "name": "sound"},
       "args": [{"node": "str", "value": "playFile", "line": 4},
                {"node": "num", "value": 1, "line": 4},
                {"node": "binary", "op": "&",
                 "left": {"node": "var", "name": "soundspath", "line": 4},
                 "right": {"node": "str", "value": "guard1.aif", "line": 4},
                 "line": 4}],
       "command": true, "line": 4}, "line": 4},
     ...
```

Two things a decoder must get right to match this, and both are visible above:

1. `pushsymb 2` decodes to the symbol `playFile`, but the parser emits it as
   `{"node": "str", "value": "playFile"}` — a **`str`, not a `sym`** — because
   `sound playFile 1, ...` is command syntax where the first word is a bare
   keyword. Emitting `sym` here would take a different interpreter path.
2. `pusharglistnoret` (0x42) is what makes `"command": true` and wraps the call
   in `call_stmt`. `pusharglist` (0x43) means the value is used, so the `call`
   node stands alone as an expression.

---

## 7. Where the bytecode has no AST counterpart

Two of these are structural and are the real work. The rest are individual gaps.

### 7.1 Structural: stack machine → expression tree

`swap` (0x21), `peek` (0x64) and `pop` (0x65) have **no AST counterpart and never
will**. They exist because the bytecode is a stack machine and the target is a
tree. Reconstructing expressions by simulating the stack — pushing node
dictionaries instead of values, and letting each opcode pop its operands and push
the node it builds — is the decoder's core loop, not a missing feature. The
worked example above is entirely decodable this way.

`peek` in particular is used for `repeat with` loop counters and `case`
subjects, where one value is consumed several times. A pure stack simulation must
either duplicate the sub-tree or bind it to a synthetic local.

### 7.2 Structural: jumps → structured control flow

`jmp` (0x53), `jmpifz` (0x55) and `endrepeat` (0x54) must become `if` /
`repeat_while` / `repeat_with` / `repeat_in` / `repeat_forever` / `exit_repeat` /
`next_repeat` / `case`. **This is the single largest piece of work and it is not
a table.** Most of [PR]'s 1315-line `src/lingodec/handler.cpp` is this algorithm
(`Handler::parse` and the block/jump bookkeeping around it). Read it rather than
reinventing; a naive decoder produces gotos, and the port's AST has no goto node.

The worked example is the easy case: two nested if/else, forward jumps only.
`repeat` loops and `case` are where this gets hard.

### 7.3 Individual gaps — a new node or a lowering is needed

| Bytecode | Gap |
| --- | --- |
| `newobj` (0x73), `kScriptFlagFactoryDef`, `parentNumber`, `me` as argument 0 | **No `factory` / `method` / `new` node exists** among the 46. Factories are a genuine new-node requirement. `parentNumber` also needs the nesting handled: [PR] attaches a factory script to `scripts[parentNumber + 1]` — note the `+ 1`, the same 1-based offset as §2. |
| Banks 0x02 and 0x03 (`the menu`, `the menuItem`) | No node. [SV] itself stubs `kTEAMenuIdItemId`. Lowest priority — likely absent from this corpus. |
| `getchainedprop` (0x70), `gettoplevelprop` (0x72) | D6+ dot-syntax property access. `dot` may cover `0x70`; `0x72` has no clear target. Unexercised here. |
| `pushchunkvarref` (0x6d) | Meaning unknown in [SV]; [PR] names it but this document has not verified its operand. |
| `getglobal2`/`setglobal2` (0x48/0x4e) vs `getglobal`/`setglobal` (0x49/0x4f) | [SV] maps both pairs to the same handler and only notes "used in event scripts". No AST distinction needed, but the reason for two encodings is unknown. |
| `put` / `putchunk` op nibbles 2 and 3 | The `put` node has a `mode` field, so this lowers cleanly — but the nibble→mode mapping (1 into, 2 after, 3 before) is single-sourced from [SV]. |
| `hilite` (0x18) | No `hilite` node; must become a `call_stmt` on a `hilite` call. |
| An unnamed handler 0 under `kScriptFlagEventScript` | Top-level Lingo outside any handler. The AST's top level is a list of `handler`s only, so this needs a synthetic handler name. [SV] uses the generic event handler name. |
| `unknown_opcode` | Not in the AST at all. Recommend adding one so an unrecognised opcode fails at one node instead of corrupting a handler. |

### 7.4 The `str` vs `sym` decision

Noted in §6 and repeated because it is easy to miss: `pushsymb` does not map
one-to-one onto `sym`. Whether a symbol becomes `sym` or `str` depends on
whether it is the first token of a command-syntax call. Getting this wrong makes
handlers that decode cleanly and then behave differently from the same code
parsed from source. It is the most likely source of a silent fidelity
difference.

---

## 8. What this corpus actually gains — the premise is wrong

The task this document serves was framed as: *65 cast members across the six
titles carry a compiled script (`script_id > 0`) with no source text, so their
code is unreachable.* The count is exactly right. The conclusion is not.

MEASURED across the six roots under `games/` — `piposh`, `piposh-dream`,
`piposh-en`, `piposh-ru`, `piposh2`, `rating` — a total of 651 containers,
counting members with `script_id > 0`:

| Root | With source text | No source text | of those, `Lscr` has handlers |
| --- | --- | --- | --- |
| `piposh` | 8,754 | 14 | 0 |
| `piposh-dream` | 1,746 | 0 | 0 |
| `piposh-en` | 9,422 | 19 | 0 |
| `piposh-ru` | 9,726 | 21 | 0 |
| `piposh2` | 3,307 | 1 | 0 |
| `rating` | 5,441 | 10 | 0 |
| **total** | **38,396** | **65** | **0** |

`14 + 0 + 19 + 21 + 1 + 10 = 65`, matching the count the task was framed around
exactly. That agreement is the evidence that this census measured the intended
population and not some adjacent one.

**Not one of the 65 has any bytecode.** Broken down:

- **64 of 65** are in containers that have **no `Lctx`, no `Lscr` and no `Lnam`
  chunk at all** — verified independently by grepping the raw files for the tag
  in both endian spellings. `games/rating/MAINMENU.dir`,
  `games/piposh/EXCHANGE.dir` and `games/piposh-en/Wrestle1.dir` all return zero
  for every spelling. These are **dangling `script_id` words**: the member record
  claims a script that was stripped from the file in authoring. There is nothing
  to decode.
- **1 of 65** — `piposh2/PIP2DATA/BYAIR.cst` member 60, `script_id` 2 — does
  resolve, to chunk 341, which is a **92-byte header-only `Lscr` with
  `handlersCount = 0`**. An empty script.

So an `Lscr` decoder recovers **zero handlers that the source-text path does not
already reach on this corpus.** Every member that has code has source text.

This does not make the decoder pointless, and per `AGENTS.md`'s "Build Director,
not this game" it should still be built — Director stores compiled Lingo, plenty
of shipped Director titles ship *only* the compiled form, and a general engine
needs to read it. But the justification is **generality, not recovery**, and the
schedule should be set accordingly. Two concrete consequences:

1. **There is no user-visible payoff to point at when it lands.** No room starts
   working. Any harness asserting "N previously-unreachable handlers now run"
   will assert 0. The honest harness is the differential one in §8.1.
2. **A decoder that is wrong will not be noticed by playing the game**, because
   nothing in the game depends on it. That makes the differential oracle the only
   real defence, not a nice-to-have.

### 8.1 The oracle to build first

38,396 members carry **both** source text and a compiled script. Each one is a
free self-checking test: decode the bytecode to an AST, parse the source to an
AST, and compare. That is a very large regression corpus, and it exists precisely
because the corpus has no recovery work to do.

Build that harness before the lowering in §8.2. It is the only thing that will
catch a §7.4-class error, and it is what makes the whole exercise verifiable.

## 8.2 Implementation shape

| File | Contents | Size |
| --- | --- | --- |
| `lingo/compile/lscr_names.gd` | `Lnam` reader | ~40 lines |
| `lingo/compile/lscr_context.gd` | `Lctx` reader + `script_id` → chunk id | ~60 lines |
| `lingo/compile/lscr_reader.gd` | `Lscr` header, literals, handler records, name lists | ~250 lines |
| `lingo/compile/lscr_disasm.gd` | opcode table + size-class decode → flat instruction list | ~200 lines |
| `lingo/compile/lscr_lower.gd` | stack simulation → expression trees; jump structuring → statements | **~700–900 lines** |
| `lingo/compile/lscr_the.gd` | the `lingoV4TheEntity` bank table → property nodes | ~200 lines (mostly data) |
| `tools/lscr_decode.gd` | harness: decode and compare against source where both exist | ~150 lines |

Sections 1–4 are mechanical and can be written directly from this document.
`lscr_lower.gd` is the whole risk and is where the schedule will go. Build the
§8.1 oracle before it.

---

## Summary of confidence

| Section | Status |
| --- | --- |
| §0 version scales, per-container mix | CONFIRMED — source ladder + version read from all 651 containers |
| §0 the three version-dependent sizes | CONFIRMED, measured at both 700 and 850. **Follow [PR], not [SV]** |
| §1 `Lnam` | CONFIRMED, both sources + measured |
| §2 `Lctx`, 1-based mapping | CONFIRMED, both sources + measured |
| §2 no-`Lctx` mmap-order fallback | MEASURED-ONLY, in neither reference; coherent but not verified per handler |
| §3 `Lscr` header | CONFIRMED, both sources + measured |
| §3 event map at +56 | CONFIRMED, and it settles the [SV]/[PR] disagreement in [SV]'s favour |
| §3 literals, string type 1 | CONFIRMED + measured. Types 4 and 9 UNVERIFIED here |
| §3 handler record fields 0–41 | CONFIRMED + measured |
| §3 handler record *size* 42 vs 46 | CONFIRMED — measured both ways in `piposh2` alone |
| §3.1 line table | MEASURED-ONLY, decoded in neither reference; >255-byte lines untested |
| §4 size-class rule | CONFIRMED ([PR]); note [SV] cannot decode the `0xC0`+ forms |
| §4 opcode numbers 0x01–0x67 | CONFIRMED where both agree; 12 opcodes measured end to end |
| §4 opcodes 0x21, 0x6d–0x73 | [PR]-only, UNVERIFIED, unexercised |
| §4.1 `pushcons` divisor | CONFIRMED + measured at both 700 (÷8) and 850 (÷1) |
| §4.1 literal *table* stride at 850 | **UNVERIFIED** — 8 from [PR]; the ÷1 divisor means operands cannot reveal it |
| §4.2 arg/local multiplier | CONFIRMED + measured at both 700 (÷8) and 850 (÷1). **This section was wrong before it was measured** |
| §0 divisor is one shared quantity | CONFIRMED — [PR] applies `variableMultiplier()` to both operand kinds |
| §4.3 `the` bank table | CONFIRMED as data ([SV]); bank→node mapping in §5 is this document's judgement |
| §5 AST node fields | CONFIRMED from the parser's own constructors and real dump output |
| §6 worked example | **CONFIRMED — decode matches known source exactly** |
| §6 jump rule | CONFIRMED on three jumps. `endrepeat` negation UNVERIFIED |
| §7 gap list | Analysis, not measurement |
| §8 corpus census | CONFIRMED — 65 members, 0 with bytecode; 64 verified by raw tag grep |
