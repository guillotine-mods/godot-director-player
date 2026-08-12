# Lingo's surface

What the language actually exposes, catalogued so that an interpreter written
here can be checked against it rather than grown one missing name at a time.

The port already runs the original's scripts (`lingo/lingo_interpreter.gd`) and
binds them to the engine (`scenes/preview_lingo_host.gd`). What it has never had
is the *other* half of the picture: the list of everything Director offers, so
that a name the game reaches for and the port answers with VOID can be told apart
from a name nobody will ever use. This closes it for the language as a whole, and
ends with the gap analysis it makes possible.

> **A warning about this document's citations.** It was written while a second,
> now-retired engine was the running one, and it cites that engine's files
> throughout: `lingo/lingo_host.gd`, `lingo/lingo_engine.gd`,
> `director/director_runtime.gd`. **All three have been deleted.** A sentence here
> saying "`lingo_host.gd` gets this right" is a statement about code that no
> longer exists, and is *not* evidence that the running engine does it.
>
> This is not a hypothetical failure mode. §9.3 listed `intersects` as
> implemented on the strength of the retired host; the live host had no binding,
> so every inventory drop in every room of every title silently evaluated to
> "nothing" — and this document is why nobody checked. The live host is
> `scenes/preview_lingo_host.gd`, and its `unbound` tally is the only honest
> answer to "does the engine have this?"
>
> **§19 is now that answer, per name, and a harness holds it.** Every claim about
> what *this port* binds belongs there; `tools/lingo_surface_audit.gd` fails if a
> row disagrees with the running engine, if the engine binds a name with no row,
> or if any of the six titles calls a name with no row. Where a paragraph below
> and §19 disagree, §19 is the one that was checked this morning. The prose in
> §9.3 is kept for what it explains — *why* a binding is shaped the way it is —
> and not as a statement of what exists.
>
> The *language* half of this document — §1 through §8, the grammar, the
> precedence table, the chunk rules — is about Director and is unaffected.

## Where this comes from, and how much to trust it

The catalogue is read off ScummVM's Director engine — the tables in
`lingo-builtins.cpp`, `lingo-the.cpp`, `lingo-the.h`, `lingo-events.cpp`,
`lingo-code.cpp`, `lingo-funcs.cpp` and `lingo-object.cpp` on `master`. Nothing
here is copied: names, arities and one-line meanings are facts about Director's
language, and the descriptions are written from scratch. No implementation is
reproduced, and none should be added later — ScummVM is GPL and this port is not.

**ScummVM is a source, not an authority**, exactly as
`data/lingo_vocabulary.json` already says of it in prose. Two consequences run
through every table below:

- Where ScummVM marks a property read-only or a builtin a stub, that is a
  statement about *ScummVM*, not always about Director. `the width of member`
  is settable in Director 6 and is not implemented as settable there. Sections
  that carry this risk say so inline.
- Where ScummVM and the game's own data disagree, the data wins. That is not a
  hypothetical: the vocabulary file records ScummVM truncating this game's score
  at 120 sprite channels when 21 of the 60 movies declare 150.

Everything about *this repo* was read directly out of the files named. The
usage counts are computed from `data/lingo_vocabulary.json`, which
`tools/generate_lingo_vocabulary.py` builds by walking the compiled AST of all
3,349 scripts under `reference/lingo/`. A "not verified" section at the end
lists the claims that are inference.

---

# 1. Builtins

Arity is given as `min..max`; `…` means variadic (ScummVM's table marks these
with a sentinel rather than a count). ScummVM tags each entry as a **function**
(usable in an expression, returns a value), a **command** (statement form, no
useful return), a **hybrid** (both), or a **constant** (a bare word that
evaluates to a fixed value). The tag letters are ScummVM's; the interpretation
of them here is inference from how each is called, not from a comment.

Two names appear twice in the table with different arities and different
meanings — `duplicate` (list copy, versus cast-member copy) and `return`
(control-flow statement, versus the carriage-return constant). A dispatcher
keyed on name alone will collide on both.

## 1.1 Math

| Name | Arity | Meaning |
|---|---|---|
| `abs` | 1 | Absolute value. |
| `atan` | 1 | Arctangent, radians. |
| `cos` | 1 | Cosine, radians. |
| `exp` | 1 | e to the power of the argument. |
| `float` | 1 | Coerce to float. |
| `integer` | 1 | Coerce to integer, rounding. |
| `log` | 1 | Natural logarithm. |
| `pi` | 0 | The constant π (also reachable as `the pi`). |
| `power` | 2 | First argument raised to the second. |
| `random` | 1 | Uniform integer in 1..n **inclusive, one-based**. |
| `sin` | 1 | Sine, radians. |
| `sqrt` | 1 | Square root. |
| `tan` | 1 | Tangent, radians. |
| `void` | 0 | The VOID value. |

`random(n)` returning `1..n` rather than `0..n-1` is the classic off-by-one in
a port: every "one of N" selection in the original silently shifts by one and
the last option never appears.

## 1.2 Strings

| Name | Arity | Meaning |
|---|---|---|
| `chars` | 3 | Substring of a string by first and last character index, one-based. |
| `charToNum` | 1 | Character code of the first character. |
| `length` | 1 | Character count. |
| `numToChar` | 1 | Character for a code. |
| `offset` | 2..3 | Position of the first string inside the second, one-based, 0 if absent; a third argument gives a start offset. |
| `string` | 1 | Coerce to string. |
| `value` | 1 | Parse a string as a Lingo value (number, list, property list). |
| `numberOfChars` | 1 | Backing form of `the number of chars in X`. |
| `numberOfItems` | 1 | Backing form of `the number of items in X`. |
| `numberOfLines` | 1 | Backing form of `the number of lines in X`. |
| `numberOfWords` | 1 | Backing form of `the number of words in X`. |

`offset` is one-based and answers 0 for "not found", which means the natural
GDScript `find()` needs `+1` *and* needs its `-1` mapped to 0. Getting only one
half right produces a function that is correct except when the needle is at the
very start.

The four `numberOf*` entries exist because the surface spelling is a *chunk
expression*, not a call: scripts write `the number of lines in field "x"`. A
parser that only recognises the call form will not see them at all.

## 1.3 Lists and property lists

| Name | Arity | Meaning |
|---|---|---|
| `list` | … | Construct a linear list. |
| `add` | 2 | Append to a list; on a **sorted** list, insert in order. |
| `addAt` | 3 | Insert at a one-based position. |
| `addProp` | 3 | Add a key/value pair to a property list. |
| `append` | 2 | Append to the end regardless of sort state. |
| `count` | 1 | Number of elements. |
| `deleteAt` | 2 | Remove by one-based position. |
| `deleteOne` | 2 | Remove the first element equal to a value. |
| `deleteProp` | 2 | Remove a property-list entry by key. |
| `duplicate` | 1 | Shallow copy of a list. |
| `findPos` | 2 | Position of a key in a property list, VOID if absent. |
| `findPosNear` | 2 | Nearest position for a key in a sorted property list. |
| `getaProp` | 2 | Value for a key, VOID if absent. |
| `getProp` | 2 | Value for a key, error if absent. |
| `getAt` | 2 | Element at a one-based position. |
| `getLast` | 1 | Final element. |
| `getOne` | 2 | Position of a value (list) or its key (property list). |
| `getPos` | 2 | Position of a value, 0 if absent. |
| `getPropAt` | 2 | Key at a one-based position. |
| `setAt` | 3 | Assign at a position, extending the list if needed. |
| `setaProp` | 3 | Assign to a key, adding it if absent. |
| `setProp` | 3 | Assign to an existing key only. |
| `sort` | 1 | Sort in place, and mark the list sorted so `add` stays ordered. |
| `listP` | 1 | Whether the value is a list. |
| `max` | … | Largest of the arguments, or of a single list argument. |
| `min` | … | Smallest, same rule. |

Two behaviours that fail quietly: `getaProp` and `getProp` differ only in
whether a missing key is VOID or an error, and `add` on a list that `sort` has
touched inserts rather than appends. A port that implements `add` as "push to
the end" will produce the right contents for unsorted lists and a subtly wrong
order for sorted ones, which surfaces much later as a menu in the wrong order.

`getPos` answering 0 for absent, where `findPos` answers VOID, is the same trap
in a different place — `if getPos(l, x) then` and `if findPos(l, x) then` read
identically and one of them is testing a number.

**Every command in the table has a second spelling**, D5's dot form:
`myList.setaProp(#k, v)` *is* `setaProp(myList, #k, v)`, with the receiver moved
in front of the arguments, and the two are the same statement on the same list —
not a copy. Titles mix them freely inside one handler. A port that resolves the
dot form as a property *read* instead answers VOID and mutates nothing, which is
silent: `on SetGlobalInfo Prop, data / gGlobalInfo.setaProp(Prop, data)` is one
line, and a movie whose configuration list stays empty because of it looks like a
data problem. `tools/lingo_scope_check.gd` asserts the receiver changed.

## 1.4 Navigation and score

| Name | Arity | Meaning |
|---|---|---|
| `go` | 1..2 | Move the playhead: to a frame number, a marker label, or a frame/marker in another movie. |
| `play` | 0..2 | Like `go`, but pushes the current position; `play done` pops it. |
| `playAccel` | … | `play` without the return-position push. |
| `marker` | 1 | With a **number**, the frame of the marker *relative to the playhead*: 0 = the marker at or before it, +n forward, -n back. With a **string**, the frame of the marker of that name (same lookup as `label`). |
| `label` | 1 | Frame number of a named marker. |
| `pause` | 0 | Halt the playhead on the current frame. |
| `continue` | 0 | Resume after `pause`. |
| `abort` | 0 | Abandon the running handler chain. |
| `halt` | 0 | Stop the movie. |
| `quit` | 0 | Exit the application. |
| `restart` | 0 | Restart the machine (a 1995 idea; inert everywhere sane). |
| `shutDown` | 0 | Shut down the machine, likewise. |
| `delay` | 1 | Hold the playhead for a number of ticks. |
| `startTimer` | 0 | Reset `the timer` to zero. |
| `updateStage` | 0 | Force a redraw without advancing the frame. |
| `nothing` | 0 | Explicit no-op. |
| `do` | 1 | Compile and run a string as Lingo. |
| `preLoad`, `preLoadCast`, `preLoadMember`, `preLoadMovie` | …/1 | Memory hints. |
| `unLoad`, `unLoadCast`, `unLoadMember`, `unLoadMovie` | 0..2 / 1 | Memory hints, inverse. |
| `cancelIdleLoad`, `finishIdleLoad`, `idleLoadDone` | 1 | Background-load control. |
| `frameReady` | 0..2 | Whether a frame's media has loaded. |
| `ramNeeded` | 2 | Bytes needed for a frame range. |

`marker` **takes two argument types and answers two different questions.** A
*number* is playhead-relative and position-indexed; a *string* is a marker name.
This is the single most dangerous item in the whole catalogue for a port, and
this one has now got it wrong in both directions.

**A number must not be looked up as a name.** `lingo/lingo_host.gd` carried a
comment recording that a name-based lookup collapsed all 49 of `strtgame`'s
markers (only 32 of them distinctly named — Director calls an unnamed one "New
Marker") onto the first, so `go(marker(0) + 1)` jumped to the same frame from
everywhere and a cinematic looped for ever. `marker(0)` must be resolved by
scanning sorted marker frame numbers against the current playhead.

**And a name must not be coerced to a number.** This paragraph used to end at
"not name-indexed", which reads as *never resolve by name* — and that is how the
binding was written, so every string argument became `to_int(...)` = 0, i.e.
"the marker at or before the playhead". The corpus contradicts it in literals
rather than by inference: `marker("mainroom")` appears **11 times** in Piposh 1
beside `marker("doc6")`, `marker("dars6")` and `marker("all6")`, and Piposh 2 has
eight more — `marker("stg1go")` through `marker("stg5go")`, `marker("hezanswer")`,
`marker("rinclicktalk")`, `marker("patclicktalk")`, `marker("hezfldclicktalk")`.
Nobody writes the same string literal eleven times expecting 0.

What it cost: Piposh 1's ship map hands the player back with `go(marker(nof))`,
`nof` being a deck code like `"dl1"`, so choosing a spot on the map returned the
player to wherever the playhead was parked — measured, `DAY1` → `ROULLETE.dir`.
A numeric string (`marker("0")`) is still a number; only a name that cannot be
read as one is a name. Rating's three `marker(x)` sites are all
`set x to the clickOn` then `x - 7`, so they are integers and stay
playhead-relative. `tools/frame_events.gd` asserts both halves against a name
taken from the loaded movie's own label table, deliberately excluding frame 0
because an unknown name answers 0 and the check has to be able to fail.

**`play` and `go` suspend the handler that called them.** This is the second
most dangerous item here, and unlike `marker` it does not announce itself: a
port that runs the rest of the handler works perfectly on every site where the
call is the last statement, which is most of them.

`Lingo::func_goto` sets `_freezeState` and `Lingo::func_play` sets `_freezePlay`,
and in both cases `Window::freezeLingoState` / `freezeLingoPlayState` stashes the
*running handler* — statement position and all — and hands execution a fresh,
empty state. The statements after the call are not dead; they run later, and the
two verbs differ only in when:

- a **`go`** is requeued as an ordinary frozen state and resumed at step 7 of the
  next tick, once the frame it chose has been entered and its `enterFrame` has
  run (§6.1);
- a **`play`** goes into a buffer of its own and is resumed only by `play done`
  (or the playhead reaching the end of the movie), which requeues it as the first
  frozen state to process. `play done` itself does *not* freeze — its internal
  `go` is guarded — so the handler that wrote it keeps running.

The idiom that depends on it, and the one that made this visible here, is a
dialogue option:

```lingo
on mouseUp
  sound playFile 1, soundspath & "egoz1.aif"
  play frame "egozspeak1"    -- Director suspends the handler HERE
  go("batz2a")               -- ...and runs this at `play done`
end
```

Run straight through, line 3 overwrites the branch line 2 just set: the talking
loop is skipped and the line of speech stops a frame after it starts. In Rating
922 of 1,239 `play` sites carry Lingo after them (621 of them a `go`, 309 a
`sound`); the 166 that are the last statement of their handler are the ones that
behave the same either way. `tools/suspend_survey.gd` counts them per title.

`go loop`, `go next` and `go previous` are the exception: `func_gotoloop`,
`func_gotonext` and `func_gotoprevious` set only `_skipFrameAdvance` and never
freeze. `go to the frame` is `func_goto` with a frame number and does.

*This port:* `lingo/lingo_interpreter.gd` captures a chain of block positions on
the way out of `_exec_block` and replays it from the inside out;
`scenes/director_preview.gd` holds the chains (because `go to movie` replaces the
interpreter) and thaws them at the end of each step. A `tell` body may not
suspend — the chain would belong to the other movie's interpreter — and that is
reported rather than silent. `tools/play_suspends.gd` is the harness.

## 1.5 Sprites

| Name | Arity | Meaning |
|---|---|---|
| `puppetSprite` | … | Take (or release) script control of a channel, freeing it from the score. |
| `puppetSound` | … | Play a sound in a channel under script control. |
| `puppetTempo` | 1 | Override the frame tempo. |
| `puppetTransition` | … | Override the frame transition. |
| `puppetPalette` | … | Override the palette. |
| `spriteBox` | 5 | Set a sprite's rectangle by channel and four edges. |
| `moveableSprite` | 0 | Command form of the sprite property. |
| `immediateSprite` | … | Mark a channel's script as running on mouse-down rather than queued. |
| `editableText` | 0 | Command form of the field property. |
| `constrainH` | 2 | Clamp a horizontal value to a sprite's rectangle. |
| `constrainV` | 2 | Clamp a vertical value likewise. |
| `rollOver` | 0..1 | Whether the mouse is over a channel; with no argument, the channel it is over. |
| `sendSprite` | … | Send a message to one sprite's behaviours. |
| `sendAllSprites` | … | Send a message to every sprite's behaviours. |
| `zoomBox` | … | Animate a rectangle between two sprites. |
| `move` | 1..2 | Move a cast member between slots. |
| `erase` | 1 | Delete a cast member. |
| `findEmpty` | 1 | First free cast slot at or after a given one. |

`rollOver` with no argument is a different function from `rollOver(n)` — one
returns a channel number, the other a boolean. A single implementation that
defaults the argument to 1 will answer "is the mouse over channel 1" where the
script asked "which channel is the mouse over", and both are plausible-looking
integers.

## 1.6 Cast and member references

| Name | Arity | Meaning |
|---|---|---|
| `member` | 1..2 | Member reference by number or name, optionally in a named/numbered cast library. |
| `cast` | 1..2 | Older spelling of the same. |
| `castLib` | 1 | Cast-library reference. |
| `script` | 1..2 | Script-member reference. |
| `sprite` | 1 | Sprite reference by channel. |
| `field` | — | (Grammar, not a builtin: `field "x"` is a chunk source.) |
| `importFileInto` | 2 | Load an external file into a member. |
| `duplicate` | 1..2 | Copy a cast member into a slot. |
| `copyToClipBoard` | 1 | Copy a member to the clipboard. |
| `pasteClipBoardInto` | 1 | Paste into a member. |
| `pictureP` | 1 | Whether a value is a picture. |

`member(n)` and `member(n, castLib)` collapse a `(library, slot)` pair into one
value. `scenes/preview/members.gd` documents how this port packs the pair into a
single integer (`LIB_STRIDE`, `pack_ref`) and why the packing does not need to
match Director's: every `castNum` site in the corpus produces and consumes the
integer inside a single expression. That reasoning is worth reading before
reusing this port's encoding anywhere the integer might be stored or compared.

**This paragraph described the packing for a long time before the packing
existed.** It pointed at `lingo/lingo_host.gd`, a file that no longer exists, and
`sprite_state.read_prop` answered `the castNum of sprite` with the bare member
number the whole time — so the library was dropped on the one property whose
whole job is to carry it, and Piposh 1's ship map lost its walking figure and
every destination on it. `tools/member_ref_round_trip.gd` is the guard, and it
chains the two modules rather than testing either, because each was defensible
alone. A design note is not an implementation, and this one outlived the file it
cited.

## 1.7 Sound

| Name | Arity | Meaning |
|---|---|---|
| `sound` | 2..3 | Verb-dispatched sound command: `playFile`, `stop`, `fadeIn`, `fadeOut`, `close`. |
| `soundBusy` | 1 | Whether a channel is still playing. |
| `beep` | 0..1 | System beep, optionally repeated. |
| `isPastCuePoint` | 2 | Whether a sound/video sprite has passed a cue point. |
| `mci` | 1 | Send a Windows MCI command string. |
| `mciwait` | 1 | Send one and block. |

`sound` is not a function with an arity — it is a **verb dispatcher**, and its
first argument selects an entirely different operation. A host that binds
`sound` as one function and ignores the verb will accept every call and perform
one of them. `lingo/lingo_host.gd` gets this right by matching on the verb and
*reporting* unknown verbs rather than returning 0, which is the difference
between a diagnostic and a silent hole.

`soundBusy` deserves its own warning, and this repo has already paid for it:
`AGENTS.md` records that a synthetic `for i in N: tick()` loop advances the
runtime clock but not the audio server's, so every `soundBusy` guard holds for
ever and any scene with speech looks stuck. It was diagnosed wrong twice.

## 1.8 Points and rectangles

| Name | Arity | Meaning |
|---|---|---|
| `point` | 2 | Construct a point. |
| `rect` | 2..4 | Construct a rectangle, from four edges or two points. |
| `inflate` | 2..3 | Grow or shrink a rectangle. |
| `inside` | 2 | Whether a point lies in a rectangle. |
| `intersect` | 2 | Intersection rectangle of two rectangles. |
| `union` | 2 | Bounding rectangle of two. |
| `map` | 3 | Map a point or rectangle from one rectangle's space to another's. |
| `offsetRect` | 2 | Translate a rectangle. (Declared in the header; not in the version of the table read here.) |

`intersects` and `within`, the sprite-collision operators, are **not builtins** —
they are infix operators handled at the opcode level (§2.7). Scripts write
`if sprite 5 intersects sprite 9 then`. A parser that only knows builtin calls
will not see them, and this port routes them from the binary-operator path into
`call_builtin` as a deliberate shim (`lingo/lingo_interpreter.gd`).

## 1.9 Type predicates

| Name | Arity | Meaning |
|---|---|---|
| `ilk` | 1..2 | The type of a value as a symbol; with two arguments, tests against one. |
| `floatP` | 1 | Is a float. |
| `integerP` | 1 | Is an integer. |
| `stringP` | 1 | Is a string. |
| `symbolP` | 1 | Is a symbol. |
| `objectP` | 1 | Is an object. |
| `voidP` | 1 | Is VOID. |
| `listP` | 1 | Is a list. |
| `pictureP` | 1 | Is a picture. |
| `factory` | 1 | Look up a factory by name. |
| `symbol` | 1 | Coerce a string to a symbol. |

## 1.10 Files, resources and externals

| Name | Arity | Meaning |
|---|---|---|
| `open` | 1..2 | Open a movie-in-a-window, or an application with a document. |
| `openXlib` / `closeXlib` / `showXlib` | 1 / 0..1 / 0..1 | Load, unload and list XLibraries. |
| `openResFile` / `closeResFile` / `showResFile` | 1 / 0..1 / 0..1 | Mac resource files. |
| `openDA` / `closeDA` | 1 / 0 | Mac desk accessories. |
| `xFactoryList` | 1 | Factories in an XLibrary. |
| `xtra` | 1 | Xtra reference by name. |
| `save` | 1 | Save a cast member. |
| `saveMovie` | 0..1 | Save the movie to a path. |
| `getNthFileNameInFolder` | 2 | Directory listing by index. |
| `getVolumes` | 0 | Mounted volume names. |
| `getPref` / `setPref` | 1 / 2 | Persistent preference storage. |
| `setCallBack` | 2 | Register a callback. |
| `externalParamCount` / `externalParamName` / `externalParamValue` | 0 / 1 / 1 | Shockwave embed parameters. |
| `netPresent` | 0 | Whether networking is available. (Header only.) |

## 1.11 Windows

| Name | Arity | Meaning |
|---|---|---|
| `window` | 1 | Window reference by name — creates one if absent. |
| `windowPresent` | 1 | Whether a named window exists. |

Windows also carry methods (`open`, `close`, `forget`, `moveToFront`,
`moveToBack`) and properties (§4.6, §5). `forget` is the one that matters most:
it removes the window from the global list, which is how a movie-in-a-window
dismisses itself. This game calls it 22 times, always as
`forget(window("…"))`, and this port maps it onto `go_back` on the route stack.

## 1.12 Text layout and fields

| Name | Arity | Meaning |
|---|---|---|
| `charPosToLoc` | 2 | Stage position of a character index in a field. |
| `locToCharPos` | 2 | Character index at a stage position. |
| `linePosToLocV` | 2 | Vertical position of a line. |
| `locVToLinePos` | 2 | Line at a vertical position. |
| `lineHeight` | 2 | Height of a line in a field. |
| `scrollByLine` | 2 | Scroll a field by lines. |
| `scrollByPage` | 2 | Scroll a field by pages. |
| `installMenu` | 1 | Install a menu bar from a field's text. |

## 1.13 Video tracks

`trackCount` (1), `trackType` (1), `trackStartTime` (1), `trackStopTime` (1) —
QuickTime/AVI track queries, all taking a sprite reference.

## 1.14 Control flow, messaging and debugging

| Name | Arity | Meaning |
|---|---|---|
| `pass` | 0 | Let the current event continue to the next tier of the hierarchy. |
| `dontPassEvent` | 0 | Stop it here. |
| `stopEvent` | 0 | Stop it here (primary-handler spelling). |
| `return` | 0..1 | Return from a handler, optionally with a value. |
| `call` | … | Invoke a handler on an object or list of objects. |
| `callAncestor` | … | Invoke it on the ancestor instead. |
| `send` / `sendAncestor` | … | Older spellings of the same. |
| `param` | 1 | Nth argument of the running handler. |
| `alert` | 1 | Modal message box. |
| `put` | … | Print to the message window (and the `put … into/before/after` statement form). |
| `showGlobals` / `showLocals` | 0 | Dump variables to the message window. |
| `clearGlobals` | 0 | Discard every global. |
| `printFrom` | … | Print a frame range. |
| `cursor` | 1 | Set the cursor from a resource id or a cast-member pair. |
| `framesToHMS` / `HMStoFrames` | 4 | Convert between frame counts and time strings. |
| `beginRecording` / `endRecording` / `updateFrame` | 0..1 / 0 / 0 | Score-recording mode. |
| `clearFrame` / `deleteFrame` / `duplicateFrame` / `insertFrame` | 0 | Score editing inside a recording session. |

`pass` and `dontPassEvent` are the whole of Lingo's propagation control and are
described properly in §6.4. Note that `pass` in the corpus of this game also
appears as `dont(pass)` — a decompiler artefact of `dontPassEvent`, not a real
call.

## 1.15 Constants

`backspace`, `empty`, `enter`, `false`, `quote`, `return`, `tab`, `true`,
`version`. These are bare words, not calls, and `return` collides with the
control-flow statement of the same name. `EMPTY` being `""` rather than VOID
matters for concatenation; `lingo/lingo_interpreter.gd` resolves all of these
before any variable lookup, which is the right place.

---

# 2. Value semantics and operators

The opcode layer is where a port loses fidelity invisibly, because every one of
these has a plausible-looking wrong answer.

## 2.1 Arithmetic and the division rule

`+ - * /` and `mod`. **If both operands are integers the result is an integer,
and `/` truncates.** If either is a float, both promote and the result is a
float. Strings coerce as far as they parse and otherwise count as 0.

This is not a rounding detail. Any script that indexes by division — a row from
a linear index, a page number from an item count — produces a different value
under float division, and nothing errors. `lingo/lingo_value.gd` implements the
rule and says so in a comment; it is worth checking any new numeric helper
against it.

`mod` coerces both sides to integer first. Division or modulo by zero answers 0
in this port; ScummVM's behaviour varies by Director version (pre-D4 raised an
error).

Director versions before 4 performed integer division *regardless* of operand
types. This game is D7, so the modern rule applies, but a port aimed at an
older title needs the version gate.

## 2.2 Comparison

**String comparison is case-insensitive.** `=`, `<>`, `<`, `>`, `<=`, `>=` all
fold case before comparing. Numbers compare numerically; a numeric string and a
number compare numerically. VOID compares equal to an unset variable.

Case-sensitivity is the failure that looks like data corruption: half the room
labels in a Director movie are typed inconsistently, and a case-sensitive `=`
turns a working comparison into a branch that never fires.

ScummVM also implements a *strict* equality used internally by `getPos` and
friends, which compares list identity rather than contents. Scripts cannot
reach it directly.

## 2.3 Logic

`and`, `or`, `not`. VOID and 0 are false, everything else true. `not` of VOID is
true.

**`and` and `or` do not short-circuit** — both operands are always evaluated and
the result is the integer 0 or 1 rather than either operand. This paragraph said
the opposite until §13 and §14 were read; the correction and what it cost are in
§17, and `tools/lingo_logic_check.gd` is the harness that holds it.

## 2.4 String tests

`contains` and `starts` are infix operators, both case-insensitive substring
tests on the string forms of their operands.

## 2.5 Concatenation

`&` joins without a separator; `&&` joins with exactly one space. VOID
concatenates as the empty string, which is why an unset global must be VOID and
not 0 — `lingo/lingo_interpreter.gd` carries the example: `effectspath &
"x.aif"` must be `"x.aif"`, and a 0 default makes it `"0x.aif"`, a filename
that will simply never be found.

## 2.6 Chunk expressions

`char`, `word`, `item`, `line`, each addressable singly or as a range
(`line 2 to 4 of x`), one-based, and nestable (`word 2 of line 3 of x`).

- **Lines are separated by carriage return** in Director. Decoded assets and
  hand-written data arrive with LF or CRLF, so an implementation has to accept
  all three; `lingo/lingo_value.gd` normalises before splitting.
- **Items are separated by `the itemDelimiter`**, default `,`. It is a global
  that scripts change and change back, so a chunk implementation that hardcodes
  the comma works until the first script that does not.
- Words split on runs of whitespace, and empty runs do not produce empty words.
- Out-of-range indices clamp or yield empty rather than erroring.
- Chunk *assignment* (`put x into line 3 of field "f"`) requires reading the
  source, splicing, and writing back — so only a source that is itself
  assignable can carry a chunk write. Deleting a middle item removes the
  preceding delimiter; deleting the first removes the following one.

## 2.7 Sprite geometry operators

`intersects` and `within` are infix, take sprite references on both sides, and
answer a boolean. In Director they are ink-aware: a matte-ink bitmap tests
against its transparency mask, not its bounding box. A bounding-box-only
implementation is *more* permissive, so hotspots become larger than they were,
which reads as sloppy hit detection rather than as a bug.

The ink-awareness is narrower than it sounds, and the reference is precise about
when it applies. `c_within` compares mattes only when **both** operands are
non-QD-shape with `kInkTypeMatte`, and otherwise takes
`getBbox().contains(getBbox())`; `c_intersects` has a third case, box-on-matte,
when only the second operand qualifies. A shape is never a matte however it is
inked, so a bitmap tested against a shape is always plain rects.

**Neither operator consults `the visible of sprite`,** and that is the difference
between them and the mouse rather than an omission. `channel.cpp:isMouseIn` opens
with `if (!_visible) return kCollisionNo` and is the only site in that file that
reads `_visible` at all; both operators go straight to `getBbox()`. Scripts rely
on it: the idiom is to park a 1x1 hidden member where a geometric question needs
asking and ask it there, which is how Piposh 1's cannon decides whether a shell
hit a ship.

A port that answers "no rect" for a hidden sprite answers *no* to every such
question -- see `docs/bugs-closed.md` 43, and `tools/sprite_collision.gd`, which
asserts both halves. The ship map in `MAINMENU.dir` is the other consumer and it
wants the same rule: `on outofthisa` reads a *hidden* sprite 20 against fourteen
deck zones to learn where the player is standing, and without this it matches
none of them.

## 2.8 Coercion summary

| From | In arithmetic | In string context | In a condition |
|---|---|---|---|
| VOID | 0 | `""` | false |
| Integer | itself | decimal digits | false iff 0 |
| Float | itself | printed per `the floatPrecision` | false iff 0 |
| Numeric string | its value | itself | false iff it parses to 0 |
| Non-numeric string | 0 | itself | false |
| Symbol | 0 | its name | true |
| List | element-wise | bracketed | true |

Floats print to `the floatPrecision`, which is 4 by default, so `put 3.0` shows
`3.0000`. The property is not a number the language stores and consults: the
reference's write arm compiles it into a `%.*f` format string
(`lingo-the.cpp:1290`) and that string is Lingo's only float-to-string path, so
every float anywhere is printed through it. A port that uses GDScript's `str()`
emits `3.0` into a field the game later parses, and one that trims whole floats
to `3` -- which this document asserted until it was measured -- is wrong the
same way in the other direction.

---

# 3. System properties — `the <prop>`

Director's global state, reachable as `the X` and in some cases assignable with
`set the X to …`. ScummVM enumerates 156 of these. Below, **W** marks the ones
ScummVM implements a setter for; everything else is read-only (or, in a handful
of cases, has a setter that is deliberately inert — noted separately).

Read-only unless marked.

**Mouse.** `mouseH`, `mouseV`, `mouseDown`, `mouseUp`, `rightMouseDown`,
`rightMouseUp`, `stillDown`, `doubleClick`, `clickOn`, `clickLoc`, `lastClick`,
`lastRoll`, `rollOver`, `mouseCast`, `mouseMember`, `mouseChar`, `mouseWord`,
`mouseItem`, `mouseLine`, `emulateMultiButtonMouse` (W).

`the clickOn` is the channel number of the sprite that received the current
mouse message and is only meaningful *during* that dispatch. This port sets it
on the host immediately before running a handler and clears it after
(`lingo/lingo_engine.gd`, retired — unverified against `scenes/preview/scripts.gd`), which is the only way it can be right — a value
computed on demand from the current mouse position answers a different question
once the handler has moved something.

**Keyboard.** `key`, `keyCode`, `keyPressed`, `lastKey`, `commandDown`,
`controlDown`, `optionDown`, `shiftDown`, `keyDownScript` (W),
`keyUpScript` (W), `mouseDownScript` (W), `mouseUpScript` (W).

The four `*Script` properties hold **Lingo source text as a string**, and
assigning one installs a primary event handler (§6.3). This is the one place in
the language where a property assignment changes the event model. This game
writes `the keyDownScript` 63 times.

**Playhead and score.** `frame`, `lastFrame`, `frameLabel`, `frameScript`,
`frameTempo`, `frameTransition`, `framePalette`, `frameSound1`, `frameSound2`,
`labelList`, `score`, `scoreSelection`, `movie`, `movieName`, `moviePath`,
`pathName`, `applicationPath`, `movieFileSize`, `movieFileFreeSize`,
`updateMovieEnabled` (W), `perFrameHook` (W), `actorList`, `pauseState`,
`exitLock` (W), `updateLock`, `preloadEventAbort` (W), `preLoadRAM` (accepted,
inert).

The seven `frame*` properties are **read-only in ScummVM and warn if written**.
In Director they are read-only too — they describe the score cell under the
playhead. Puppet equivalents (`puppetTempo`, `puppetTransition`,
`puppetPalette`) are how a script overrides them.

**Timing.** `ticks`, `timer` (W), `timeoutLength` (W), `timeoutLapsed` (W),
`timeoutKeyDown` (W), `timeoutMouse` (W), `timeoutPlay` (W), `timeoutScript` (W),
`idleHandlerPeriod` (W), `idleLoadMode` (W), `idleLoadPeriod` (W),
`idleLoadTag` (W), `idleReadChunkSize` (W), `cpuHogTicks` (accepted, inert),
`netThrottleTicks` (accepted, inert).

`the timeoutLapsed` is documented as read-only and ScummVM permits writing it
anyway, because D2/D3 titles do. That is exactly the kind of thing a
spec-following port refuses and then cannot explain why a game hangs.

**Stage and display.** `stage`, `stageColor` (W), `stageLeft`, `stageTop`,
`stageRight`, `stageBottom`, `centerStage` (W), `fixStageSize` (W),
`colorDepth` (W), `colorQD`, `switchColorDepth` (stub), `paletteMapping`,
`fullColorPermit` (inert), `imageDirect` (inert), `buttonStyle` (W),
`checkBoxType` (W), `checkBoxAccess` (W).

`the stage` is almost always the target of `tell the stage`, not a value read.
All 135 uses in this game's corpus are `tell the stage`, and the interpreter
handles `tell` at the statement level, so the property is never evaluated. A
coverage tool that counts it as an unbound read is producing a false positive;
this one does, and §7 says so.

**Sound.** `soundEnabled` (W), `soundLevel` (W), `soundDevice` (W),
`soundKeepDevice` (W), `multiSound`, `beepOn` (W).

**Text and selection.** `itemDelimiter` (W), `selection`, `selStart` (W),
`selEnd` (W), `field`, `chars`, `words`, `items`, `lines`, `chunk`.

**Files and search.** `searchPath` (W), `searchPaths` (W),
`searchCurrentFolder` (read-only despite the name suggesting a switch).

`the searchPath` is a **list**, not a string. Scripts read it as
`getAt(the searchPath, 1)`. `lingo/lingo_host.gd` keeps it as a list with one
empty element specifically so that read answers `""` rather than 0 — an empty
list would make `getAt` fall off the end.

**Cast and members.** `cast`, `castLib`, `castLibs`, `castMembers`.

**Numbers and randomness.** `pi`, `maxInteger`, `floatPrecision` (W),
`randomSeed` (W), `sqrt`.

**Machine and environment.** `machineType`, `platform` (read-only, warns),
`productName`, `productVersion`, `organizationName`, `userName`,
`serialNumber`, `memorySize`, `freeBytes`, `freeBlock`, `runMode`,
`safePlayer`, `romanLingo` (W), `quickTimePresent`,
`videoForWindowsPresent`, `digitalVideoTimeScale` (W), `deskTopRectList`.

`the freeBlock` is the one to watch. This repo's history has it: the host's old
fall-through answered 0 for any unbound property, which made every low-memory
guard in the game take the "not enough memory" branch, silently, for years.
`lingo/lingo_host.gd` now answers VOID for unbound reads and reports the name,
and the comment explaining why is the best short argument in the tree for
never defaulting a property to 0.

**Windows.** `activeWindow`, `frontWindow`, `windowList`, `window`.

**Debug and diagnostics.** `trace` (W), `traceLoad` (W), `traceLogFile` (W),
`alertHook` (W), `result`, `paramCount`, `currentSpriteNum`, `lastEvent`,
`xtras`.

**Menus.** `menu`, `menuItem`, `menuItems`, `menus`.

**Date and time.** `date`, `time`, each with `short` / `long` / `abbreviated`
sub-forms (`the long date`).

---

# 4. Sprite properties — `the X of sprite N` / `sprite(N).X`

Both spellings reach the same property. This game uses the dot form far more
often, which is why `tools/generate_lingo_vocabulary.py` counts both; a walker
that only saw `the X of sprite N` would under-report every entry below.

**Readable and writable:** `locH`, `locV`, `loc`, `width`, `height`, `rect`,
`castNum`, `castLibNum`, `member`, `memberNum`, `visible`, `visibility`,
`puppet`, `moveableSprite`, `editableText`, `immediate`, `trails`, `ink`,
`blend`, `foreColor`, `backColor`, `pattern`, `lineSize`, `type`, `cursor`,
`constraint`, `stretch`, `scoreColor`, `flipH`, `flipV`, `tweened`.

**Readable only:** `left`, `top`, `right`, `bottom`, `name`, `scriptNum`,
`scriptInstanceList`, `mostRecentCuePoint`, `currentTime`.

`left`/`top`/`right`/`bottom` being read-only is not an omission: Director
*derives* them from the location and the registration point and the member's
size, so a setter would have to move the sprite. `lingo/lingo_host.gd` reaches
the same conclusion independently and leaves them out of `SPRITE_WRITES` with
that reason written down.

**Digital-video sprite properties** (readable and writable, but only on a
channel whose member is a video): `movieRate`, `movieTime`, `startTime`,
`stopTime`, `volume`, `trackEnabled`, `setTrackEnabled`, `trackText`,
`trackNextKeyTime`, `trackNextSampleTime`, `trackPreviousKeyTime`,
`trackPreviousSampleTime`.

## The autopuppet rule

**Writing a visual sprite property implicitly puppets that aspect of the
channel.** ScummVM tracks this with per-aspect flags: assigning `locH` sets the
position flag, `width` the size flag, `foreColor`/`backColor`/`ink`/`blend`
their own. The effect is that the score stops overwriting that property on the
next frame *for that property only*.

A port that ignores this has a specific and confusing symptom: a script moves a
sprite, the move visibly happens, and one tick later the score puts it back.
The bug looks like a race in the renderer and is a missing flag in the property
setter. The opposite mistake — treating any property write as a full
`puppetSprite` — freezes the sprite's animation, because the score stops driving
its member number too.

`puppetSprite N, FALSE` releases the channel. ScummVM notes that it does not
properly restore the pre-puppet property values, which is a real fidelity gap
in ScummVM rather than in Director.

---

# 5. Cast member properties — `the X of member M` / `member(M).X`

Members are typed, and most properties exist only on one type. Reading a
bitmap's `text` is not an error in Lingo; it just answers something useless.

**Every member type.** Readable: `name` (W), `number`, `castLibNum` (W),
`type`, `castType`, `width`, `height`, `rect`, `size`, `loaded`, `filename`,
`media` (W), `mediaReady`, `modified` (W), `purgePriority` (W),
`scriptText` (W), `cuePointNames` (W), `cuePointTimes` (W), `foreColor` (W),
`backColor` (W), `antiAlias` (W).

ScummVM implements `width`, `height`, `rect`, `size`, `number`, `castType`,
`loaded`, `filename` and `mediaReady` as read-only. In Director 6+, `width`
and `height` of some member types *are* settable. Treat the read-only marks in
this section as ScummVM's implementation state.

**Text and field members.** `text` (W), `font` (W), `fontSize` (W),
`fontStyle` (W), `textFont` (W), `textSize` (W), `textStyle` (W),
`textAlign` (W), `textHeight` (W), `alignment` (W), `lineHeight` (W),
`lineCount`, `margin` (W), `border` (W), `boxType` (W), `boxDropShadow` (W),
`dropShadow` (W), `wordWrap` (W), `pageHeight` (W), `scrollTop` (W),
`autoTab` (W), `editable` (W), `hilite` (W).

**Bitmap members.** `depth` (W), `palette` (W), `paletteRef` (W),
`picture` (W), `regPoint` (W).

The registration point is the reason a naive port's sprites are all offset:
`locH`/`locV` position the *registration point*, not the top-left corner, and
Director's default for a bitmap is its centre.

`regPoint` is **writable, and the write is a layout primitive rather than a
curiosity**: the point belongs to the member, so one statement re-anchors every
sprite drawn from it. Itamar Park's `setRegPointToCorner(51, 78, 1, #right,
#Middle)` walks 28 members that way. The value is in the member's own
coordinates and not an offset from its top-left — `BitmapCastMember::getField`
pushes `_regX`/`_regY` unchanged while the drawing offset is the separate
`getRegistrationOffset()`, `_regX - _initialRect.left` — which matters because
97,464 of this corpus's 120,869 bitmap members have a non-zero rect origin.
`preview/members.gd:write_prop` is the writer and `tools/reg_point.gd` asserts
that a write moves the drawn rectangle; see `docs/bugs-closed.md` 89.

**Shape members.** `shapeType` (W), `filled` (W), `lineSize` (W),
`pattern` (W).

**Button members.** `buttonType` (W).

**Script members.** `scriptType` (W).

**Sound members.** `channelCount`, `sampleRate`, `sampleSize`, `loop` (W).

**Digital video members.** `duration` (W), `frameRate` (W), `timeScale` (W),
`video` (W), `sound` (W), `center` (W), `crop` (W), `scale` (W),
`controller` (W), `directToStage` (W), `pausedAtStart` (W), `preLoad` (W),
`digitalVideoType` (W).

**Transition members.** `transitionType`, `changeArea`, `chunkSize`.

**Xtra members.** `interface`, `mediaBusy`.

**Behavior members.** `spriteNum`.

**Movie (linked) members.** `scriptsEnabled`.

## 5.1 Other qualified entities

Not sprite and not member, but reached the same way and easy to miss because
they need their own dispatch path.

- **`the X of field F`** — `text`, `name`, `font`, `fontSize`, `fontStyle`,
  `textFont`, `textSize`, `textStyle`, `textAlign`, `textHeight`, `alignment`,
  `lineHeight`, `foreColor`, `hilite`. Distinct from member dispatch in
  ScummVM, which validates the member is a text member first.
- **`the X of <chunk>`** — `font`, `fontSize`, `fontStyle`, `textFont`,
  `textSize`, `textStyle`, `textHeight`, `lineHeight`, `foreColor`. This is how
  a script styles *part* of a field: `the foreColor of word 3 of field "x"`.
  Chunk references nest, and the offsets unwind recursively.
- **`the X of castLib C`** — `name`, `number`, `fileName`, `preLoadMode`,
  `selection`.
- **`the X of window W`** — `rect`, `drawRect`, `sourceRect`, `title`,
  `titleVisible`, `visible`, `modal`, `fileName`, `windowType`.
- **`the X of menu M` / `of menuItem I`** — `name`; and `checkMark`, `enabled`,
  `name`, `script` respectively. `the number of menuItems` and
  `the number of castMembers` / `of castLibs` are counting forms.
- **`the volume of sound N`** — sound channel volume; also `the cuePointNames of
  sound N`.
- **`the short/long/abbreviated date`** and the same for `time`.

---

# 6. The event model

This is where a Director port either works or produces a game that renders
perfectly and does nothing.

## 6.1 Per-frame order

For one tick of the score, ScummVM's playback loop does roughly this:

1. **Check whether the frame is still waiting** — tempo delay, "wait for sound",
   "wait for video", "wait for mouse click". If it is, sprites still update and
   frozen scripts still get a chance to resume, but the playhead does not move.
2. **`exitFrame`** on the frame being left, unless a `go` has asked for the
   normal advance to be skipped.
3. **Advance the playhead.** If Lingo set a next-frame target, that target is
   loaded and the target is cleared; otherwise the frame number increments.
4. **Compute the next wait** from the new frame's tempo channel.
5. **Render**: sounds, palette, transitions, sprite graphics, film-loop
   advance, then the stage is drawn.
6. **`stepMovie`**, then **`enterFrame`**, then immediate sprite scripts, then
   any frozen scripts that can now resume.

`prepareFrame` fires before the frame renders and goes to sprite behaviours
only. `beginSprite` fires when a sprite instance appears in a channel and
`endSprite` when it leaves; both, like `prepareFrame`, terminate after the
sprite tier and never reach frame or movie scripts. `stepFrame` goes to objects
in `the actorList`. `idle` is the lowest-priority per-frame message and reaches
frame and movie scripts.

**The order that matters most is that `exitFrame` fires before the advance.**
That is what makes `go to the frame` in an `exitFrame` handler an idle hold
rather than a jump: the handler sets the target to the frame it is already on,
and step 3 loads that same frame instead of incrementing. This port's
`director/director_runtime.gd` dispatches `exitFrame` and `enterFrame` in that
relationship and `scenes/preview_lingo_host.gd` names it explicitly — "why a
Director room sits still at all".

## 6.2 Movie-level events

- **`prepareMovie`** (D6+) before anything else in a movie.
- **`startMovie`** once, before the first frame plays.
- **`stepMovie`** once per frame, to movie scripts.
- **`stopMovie`** when the movie ends or is left.
- **`startUp`** at application launch.
- **`activateWindow`, `deactivateWindow`, `openWindow`, `closeWindow`,
  `moveWindow`, `resizeWindow`, `zoomWindow`** (D5+) on window state changes,
  to movie scripts.
- **`cuePassed`** when a sound or video crosses a cue point.
- **`getBehaviorDescription`, `getPropertyDescriptionList`,
  `runPropertyDialog`** are authoring-time messages a behaviour answers for the
  Director IDE. A runtime port can ignore them, but should recognise them so
  they do not report as unhandled events.

## 6.3 Mouse and keyboard resolution hierarchy

For `mouseDown`, `mouseUp`, `keyDown`, `keyUp`, `rightMouseDown`,
`rightMouseUp` and `timeout`, the message is offered to script tiers in this
order:

1. **Primary event handler** — the Lingo text held in `the mouseDownScript`,
   `the mouseUpScript`, `the keyDownScript`, `the keyUpScript` or
   `the timeoutScript`. These five, and only these five, have primary handlers.
   They run *before* everything, and unless one calls `dontPassEvent` the
   message continues.
2. **Sprite behaviours** on the sprite involved. In D6+ a sprite can carry
   several behaviours; each gets the message in order, and only after the last
   one does the decision to continue get taken.
3. **The cast member's script** of the member in that channel.
4. **The frame script** of the current frame.
5. **Movie scripts**, searched in cast-library order.

`lingo/lingo_engine.gd` implemented tiers 2–5 exactly (`dispatch_sprite_event`:
behaviour, then member script, then frame script, then movie handler) and does
not implement tier 1.

**The mouseUp asymmetry.** `mouseDown` goes to whatever sprite is under the
cursor when the button goes down. `mouseUp` in Director 3 goes to the sprite
that received the `mouseDown`; in Director 4 and later it goes to whatever
sprite is under the cursor at release. ScummVM keeps the mouse-down cast id and
sprite script id around so a `mouseUp` cast-member handler can still refer to
the original member even if sprites have been swapped underneath.

This is the difference between "click a button and drag off it before
releasing" doing nothing and doing something, and it is version-gated, so a
port that hardcodes either rule is wrong for half the corpus.

## 6.4 Stopping propagation

There is one flag. It defaults to "keep passing" for each handler, and
`dontPassEvent` (or `stopEvent`, the primary-handler spelling) clears it. The
dispatcher checks it before running each queued handler and skips the rest of
the chain for that event.

`pass` is the explicit opposite and is only meaningful where the default has
been changed — inside a behaviour that would otherwise consume the event.

The subtlety is that **the whole chain is queued up front**, tier by tier,
before any of it runs. That is why a `go` inside a `mouseUp` handler does not
cancel the handlers below it in the hierarchy: they are already queued and will
run, against a score state the `go` has already changed. A port that resolves
tiers lazily, one at a time, will get a different — arguably more sensible, and
wrong — answer.

## 6.5 Sprite-local messages

`mouseEnter`, `mouseLeave`, `mouseWithin`, `mouseUpOutSide` (D6+) go to sprite
behaviours only. `mouseWithin` fires every tick the cursor is over the sprite,
which makes it the cheapest way to accidentally run a script 60 times a second.

---

# 7. Object surface

## 7.1 Script objects

`new(script "name")` instantiates a parent script; the object holds properties
declared with `property` and handlers declared with `on`. Property lookup
checks the object's own table first, then follows the `ancestor` property if
set, recursively. Method lookup does the same. `the spriteNum` of a behaviour
answers the channel it is attached to and is synthesised rather than stored.

Assigning to an undeclared property creates it, which means a typo in a
property name is a new property rather than an error.

## 7.2 Factories (Director 3 style)

`factory "name"` looks one up; calling it instantiates. `mNew` is the
constructor and receives the argument count; `mDispose` is the destructor.
Factories accept arbitrary properties and support indexed access through `get`
and `put`. `perform` invokes a method by name at runtime.

## 7.3 XObjects and Xtras

Registered by class name, loaded with `openXlib` and released with `closeXlib`.
Names are normalised: platform extensions (`.xlib`, `.dll`, `.x16`, `.x32`) and
Mac path separators are stripped before lookup, so the same library named three
ways in three movies resolves once.

Every XObject exposes a standard set regardless of what it does: `new` (and
`birth`, D4+), `describe`, `dispose`, `name`, `respondsTo`,
`instanceRespondsTo`, `messageList`, `perform`. A port that stubs an Xtra
should answer these rather than nothing, because scripts probe with
`respondsTo` before calling.

## 7.4 Windows as objects

`window("name")` returns a handle and **creates the window if it does not
exist**, which means `windowPresent` is the only way to test without side
effects. Methods: `open`, `close`, `forget`, `moveToFront`, `moveToBack`.
Properties as listed in §5.1.

`open` sends `openWindow`; `forget` removes it from the global window list.
A single-stage port has to decide what a movie-in-a-window means; this one
turns it into an overlay on a route stack (`lingo/lingo_host.gd`), which is a
game-shaped decision and is documented as such at the call site.

---

# 8. Things that fail silently

Collected from the sections above, because each of these produces a running
game that is wrong rather than an error.

1. **`marker(n)` is playhead-relative and resolved by position; `marker("name")`
   is resolved by name.** Both halves have cost this port a bug: resolving a
   *number* by name hung a cinematic, and coercing a *name* to a number sent
   Piposh 1's ship map to the wrong room. Unnamed markers exist and share a name.
2. **A navigation call is queued, not immediate.** `go` sets a target the score
   loop consumes on its next advance; the rest of the current handler still
   runs, and so do the event tiers already queued below it. A `go` implemented
   as "jump now" reorders everything after it.
3. **`go to the frame` is a hold, and the frame re-enters.** The playhead loads
   the same frame again, `enterFrame` fires again, and the frame's sounds and
   tempo are re-applied unless guarded. This port distinguishes an idle hold
   from a real navigation precisely so it can *avoid* re-entering
   (`lingo/lingo_host.gd`), which is a deliberate divergence from ScummVM and
   is the safer choice given that this game's rooms start their speech on
   frame entry.
4. **Integer division truncates.** `7/2` is 3 unless a float is involved.
5. **String comparison is case-insensitive**, in `=`, `<`, `contains` and
   `starts` alike.
6. **VOID is not 0.** An unset global concatenates as `""` and an unbound
   property read must not answer 0 — that is what made every memory check in
   this game take the wrong branch.
7. **`the itemDelimiter` is global and mutable.** Chunk code that hardcodes the
   comma is right until the first script that changes it.
8. **Lines are CR-separated.**
9. **Writing a sprite property auto-puppets that aspect only.** Too little and
   the score overwrites the change next tick; too much and the sprite's
   animation freezes.
10. **`locH`/`locV` position the registration point**, not the top-left corner.
11. **`random(n)` is 1-based and inclusive.**
12. **`offset` is 1-based and returns 0 for absent.**
13. **`add` on a sorted list inserts.**
14. **`sound` is a verb dispatcher.** Binding the name is not binding the
    operation.
15. **`rollOver` with and without an argument are different functions.**
16. **`the mouseUp` sprite is version-dependent.**
17. **Floats print to `the floatPrecision` (default 4), never trimmed.**
18. **A property assignment can install an event handler** — the four `*Script`
    properties hold Lingo source.

---

# 9. Gap analysis

Measured against `data/lingo_vocabulary.json` (3,349 scripts, 0 unparsed) and
the tables in `lingo/lingo_host.gd`. Usage counts are AST-node occurrences
across the whole corpus, not scripts touched, so they weight a name by how
often the game reaches for it rather than by how many files mention it.

## 9.1 (a) In ScummVM, used by this game, not implemented here — the priority list

**The property surface is closed.** ~~Every sprite, member and system property
the corpus reads or writes is bound~~, with one apparent exception that is a
false positive:

> **That claim is wrong twice over, and §19 measures both.** It was made against
> the retired host's tables, and it was made against *this game* — but "the
> corpus" is six titles, and the two facts compound. Of the property names the
> six titles reach, **eleven are not live in the running engine**: `the searchPath`
> (326 sites, Piposh 1's disc scan), `the member of sprite` (1,453), `the flipH`
> and `the flipV of sprite` (456, Piposh Dream), `the loc of sprite` (361), `the
> hilite of member` (39, Rating), `the rect` and `the top of sprite`, `the
> castLibNum of sprite`, `the volume of sprite`, `the currentSpriteNum`, `the
> exitLock`, `the movie` and `the textSize of member`. Seven of those are the
> *same mechanism*: a sprite-property write is stored in the override table and
> `sprite_state.effective` merges only the keys it knows, so the write round-trips
> through a read and reaches nothing — which is what `the moveableSprite of
> sprite` and `the editableText of sprite` each did before they were found.
>
> The sentence below — "that is a genuinely strong position" — was true of one
> title's builtins and was never true of the property surface across the engine's
> six. §19 carries the list and the routing.

| Name | Uses | Verdict |
|---|---|---|
| `the stage` | 135 reads | **Not a gap.** All 135 are `tell the stage`, which `lingo/lingo_interpreter.gd` handles at the `tell` statement node — the body simply runs on the single stage. The property is never evaluated as a value. The vocabulary walker counts the `prop` node regardless, so it reports as an unbound read. |

That is a genuinely strong position and worth stating plainly: 52 sprite
properties, 156 system properties and 80 member properties enumerated, 29
of them used by this game, all 29 bound.

**The builtin surface has seven real gaps**, all small:

| Name | Uses | Form in the corpus | Why it matters |
|---|---|---|---|
| `quit` | 9 | `quit()` | Exits the application. Currently unbound, so it reports as a missing builtin and does nothing. Nine call sites — every "quit game" path in the movie. |
| `pause` | 5 | `pause()` | Halts the playhead. Unbound, so a script that pauses and expects a click to resume runs straight on. |
| `printFrom` | 4 | `printFrom(the frame, the frame, 50)` | Printing. Correctly a no-op, but should be *bound* and inert rather than unbound, so it stops reporting. |
| `dontPassEvent` | 2 | `dontPassEvent()` | Propagation control. This port dispatches tiers eagerly and stops at the first handler that answers, so the flag has nothing to change — but that equivalence is an accident of the dispatcher, not a decision, and it will stop holding the moment sprite behaviours are allowed to fall through. |
| `pass` | 2 | `pass()` | The complement of the above. |
| `saveMovie` | 2 | `saveMovie(savepath & "hezsave.dir")` | **Implemented** (`scenes/preview/movie_save.gd`, `director/director_writer.gd`). It rewrites the container on disk. The cell above used to read "this port has its own save system, so binding it inert is probably right" — there is no other save system, and inert meant every save in this game survived exactly as long as the process did. See the section below for what it writes and what it refuses. |
| `stopEvent` | 1 | `stopEvent()` | As `dontPassEvent`. |
| `unLoadMovie` | 1 | `unloadMovie(the moviePath & "day1.dxr")` | Memory hint. Bind inert. |

`castLib` shows 4 uses in callee position, which is almost certainly the
compiler mis-splitting `of castLib "master"` — the 4,600 genuine uses are the
cast qualifier that `_cast_of` already resolves. Worth confirming before
treating it as a gap.

`when keyDown then …` (4 uses) is Director 3's `when … then` construct, which is
grammar rather than a builtin and does not appear in ScummVM's builtin table at
all. It needs parser support, not a binding.

**Ranked by uses, the whole priority list is: `quit` (9), `pause` (5),
`printFrom` (4), `dontPassEvent` (2), `pass` (2), `saveMovie` (2),
`stopEvent` (1), `unLoadMovie` (1).** Twenty-six call sites in total across
3,349 scripts. Four of the eight want to be bound-and-inert rather than
implemented — and `saveMovie` is not one of the four, which this list said it
was. Two call sites made it look negligible; they are the only two the game
needs, and with them inert the title could not save at all.

The remaining large numbers in the "unbound builtin" report are **not builtins
at all**: `displayobject` (128), `searchfunk` (69), `cursorfunk` (68),
`soundspath` (68), `peoplefunk` (36), `whatodoeveryframe` (23), `talkproc`
(20), `tlkpath` (19), `walkonby2` (13) and 25 more are the game's *own*
handlers, defined in the corpus and marked `handler_defined` in the
vocabulary. If one of those reports unbound, the fault is in handler resolution
or bundle loading, not in the builtin table. `lingo/lingo_host.gd` makes this
point at the `cursorfunk` call site — binding it as a host no-op made every
unresolved call look handled, and it is deliberately left unbound so a miss is
reported.

## 9.2 (b) In ScummVM, not used by this game — note only

Present in the catalogue above and absent from the corpus, in rough order of
how likely they are to appear in *another* Director title:

- **List and property-list operations.** `list`, `add`, `addAt`, `addProp`,
  `append`, `deleteAt`, `deleteOne`, `deleteProp`, `duplicate`, `findPos`,
  `findPosNear`, `getaProp`, `getLast`, `getOne`, `getPos`, `getProp`,
  `getPropAt`, `setAt`, `setaProp`, `setProp`, `sort`, `listP`, `max`, `min`.
  Only `getAt` and `count` are used here. Any title with an inventory built on
  lists rather than a delimited field will need most of this group.
- **Math.** `atan`, `cos`, `exp`, `log`, `pi`, `power`, `sin`, `sqrt`, `tan`.
- **Strings.** `charToNum`, `numToChar`, `string`, `chars`, and the
  `numberOf*` chunk-count forms.
- **Messaging.** `sendSprite`, `sendAllSprites`, `call`, `callAncestor`,
  `send`, `sendAncestor`, `param`. A behaviour-heavy D6+ title lives on these.
- **Object model.** `new`, `birth`, `ancestor`, factories, `xtra`, `script`.
  This game uses none of it; a later Director title will use all of it.
- **Score recording.** `beginRecording`, `endRecording`, `updateFrame`,
  `clearFrame`, `deleteFrame`, `duplicateFrame`, `insertFrame`.
- **Geometry.** `point`, `rect`, `inflate`, `inside`, `intersect`, `union`,
  `map`, `offsetRect`. (`intersects` and `within`, the operators, *are* used.)
- **Text layout.** `charPosToLoc`, `locToCharPos`, `linePosToLocV`,
  `locVToLinePos`, `lineHeight`, `scrollByLine`, `scrollByPage`.
- **Video.** `trackCount`, `trackType`, `trackStartTime`, `trackStopTime`,
  `isPastCuePoint`, and the whole digital-video property group on both sprites
  and members.
- **Menus.** `installMenu`, and the `menu`/`menuItem` entities.
- **Platform and desktop.** `mci`, `mciwait`, `openResFile`, `openDA`,
  `getVolumes`, `getPref`, `setPref`, `externalParam*`, `restart`, `shutDown`.
- **Score editing on the fly**, `zoomBox`, `spriteBox`, `importFileInto`,
  `move`, `erase`, `findEmpty`.

Of the 243 builtin names enumerated, 69 appear in this corpus and 39 of those
are the game's own handlers — so **30 real builtins carry this entire game.**
That is the number that should govern effort.

## 9.3 (c) Implemented here already

**Builtins bound in `lingo/lingo_host.gd`** (`call_builtin`): `go` / `goto`,
`play` (mapped to `go`), `puppetSprite`, `updateStage`, `sound` (verbs
`playFile`, `stop`, and `fadeIn`/`fadeOut` inert), `soundBusy`, `random`,
`marker`, `label`, `rollOver`, `intersects`, `within`, `window`, `open`,
`forget` / `close`, and the bound-but-deliberately-inert group `cursor`,
`preLoadMember`, `unLoadMember`, `alert`, `beep`, `nothing`, `updateLock`.
Plus `walkonby`, which is not a Director builtin at all but the game's own
handler that this port implements natively and lets win over the original
definition (`NATIVE_HANDLERS`).

**There are two hosts, and this list describes the one that is no longer
driving.** `lingo/lingo_host.gd` belongs to the retired renderer
(`director/movie_player.gd`, reached only from `scenes/main.tscn`); the live
player is `scenes/director_preview.tscn`, and its host is
`scenes/preview_lingo_host.gd`, which binds a deliberately smaller set. A
builtin listed above is therefore **not** evidence that the running engine has
it. `intersects` and `within` were bound in the retired host and unbound in the
live one for as long as the preview has been the main scene, which made every
drop in the corpus answer "nothing" — the operators are how Director's inventory
idiom asks what an item was let go over, so the answer was hardcoded to no. When
adding a builtin, check `scenes/preview_lingo_host.gd:call_builtin`, and read
its `unbound` tally rather than this section.

**`saveMovie` — what it does, stated at the width it actually works.** Bound in
the live host, and it writes a real Director container to disk. The path is
resolved exactly as `go to movie` resolves one, so `saveMovie(savepath &
"hezsave.dir")` and the `go("doload", savepath & "hezsave.dir")` two statements
later name the same file; where that file is a game's own container, the game's
own container is what gets rewritten, which is what makes the original's
save mechanism work unmodified.

What is written: **the field members whose text this movie's scripts have
changed**, and nothing else. A `put x into field "y"` lands in the preview's
override table (`preview/text_art.gd`), and a save is exactly the set of
overrides keyed to the container being written, re-emitted as `STXT` chunks. The
rest of the file is copied byte for byte — including everything this port does
not decode — so a chunk is either replaced in place (new payload no larger) or
appended and repointed in the `mmap` (larger). No chunk is added, no chunk id
changes, and the memory map is never grown.

What it refuses: the whole write, if the result does not reopen. The container is
built in memory, written beside the target, **reopened with this engine's own
reader and read back**, and only then moved over the target. A movie that does
not round-trip never replaces anything.

What it does **not** do, and no part of this claims otherwise:

- **Only `STXT` payloads are rewritten.** A script that changed a bitmap, a
  palette, a score or a member's *properties* rather than a field's text saves
  none of it. Director's `saveMovie` saved the whole movie; this saves the half
  the language can change through `field`.
- **A member's cast entry is untouched.** Its cached text metrics are whatever
  they were, which Director would have recomputed.
- **Vacated space is not returned to the `free` list.** A save that grows a field
  leaks the old chunk's bytes, so a repeatedly-saved container grows slowly.
- **`save castLib` is not bound.** Only the movie is saveable, which is also all
  the corpus asks for.

`tools/save_movie.gd` is the harness, and its decisive case runs a **second
Godot** that saves and exits before this one reopens the file. A single-process
test cannot tell "persisted" from "still in the override table", and that
distinction is the whole of what was wrong.

**`the moviePath`** is bound with it (`director_preview.gd:movie_path`), because
`strtgame`'s `stonecold()` is the only place this game ever sets `savepath` and
it sets it to exactly that.

**Builtins with no engine side** are answered by `lingo/lingo_builtins.gd`, the
title-agnostic module `tools/lingo_builtins_check.gd` checks against §1. It is
the *only* answer for each of them. `lingo_interpreter.gd` used to carry a
second, inline table for `value`, `string`, `integer`, `float`, `abs`, `length`,
`chars`, `offset`, `count` and `getAt`, placed ahead of the dispatch that reaches
the module, so the module could never be consulted for those ten names and the
two disagreed on six of them — `getAt` past the end answered 0 rather than VOID,
`abs` widened to float and took `abs(-7)/2` off the integer-division path,
`value` coerced where §1.2 says it parses, `integer` truncated where §1.1 says it
rounds, `offset` ignored its start argument, and `count` knew only linear lists.
The inline table is gone; the comment at `lingo_interpreter.gd:_call` records the
verdict per name.

**Operators and value semantics** (`lingo/lingo_value.gd`,
`lingo/lingo_interpreter.gd`): `+ - * /` with the integer-division rule, `mod`,
`&`, `&&`, `= <> < > <= >=` with case-insensitive string comparison, `and` /
`or` **evaluating both operands** (§17), `not`, `contains`, `starts`; chunk expressions for
char/word/item/line with ranges, nesting, chunk assignment and a mutable
`the itemDelimiter`; list literals, property-list literals and one-based
indexing; the constants `EMPTY`, `TRUE`, `FALSE`, `RETURN`, `CR`, `QUOTE`,
`TAB`, `SPACE`, `VOID`.

**Statements consumed by the interpreter**: `global`, `property`, assignment,
`put … into/before/after`, call statements, `if`/`else`, `repeat while`,
`repeat with` (up and down), `repeat in`, bare `repeat`, `case`, `tell`,
`exit repeat`, `next repeat`, `exit`, `return`, and `when` — the last recorded
and not run, because it installs a tier-1 handler the port does not have (§16.3).
Expression node kinds: `num`,
`str`, `var`, `list`, `proplist`, `unary`, `binary`, `chunk`, `count`, `field`,
`field_prop`, `sprite_ref`, `member_ref`, `member_number`, `sprite_number`,
`sprite_prop`, `member_prop`, `sound_prop`, `window_prop`, `prop`, `prop_of`,
`dot`, `index`, `call`.

**Properties — RETIRED HOST, same warning as the builtin list above.** This
paragraph enumerates `lingo/lingo_host.gd`'s tables, which are deleted. The live
host routes sprite properties generically through
`scenes/preview/sprite_props.gd` into the score record, so the *set* below is not
the live set in either direction. One difference has since been closed and is
worth keeping as a record of the shape: **`set the text of member` and `set the
editable of member` did nothing in the live engine** —
`preview_lingo_host.set_member_prop` was a bare `pass`, an *unreported* no-op,
the worst kind, since an unbound write is at least counted and named — while this
paragraph listed "Member writes: `editable`, `text`" as implemented off the
deleted host's tables. Both are bound now
(`director_preview.gd:lingo_set_member_prop`, §8.4), resolved by member reference
rather than by name so `member(12, "master").text` reaches the right library,
with `editable` re-arbitrating focus on the way through. `editable` had five
sites in this corpus — all in `SAVELOAD.dir`, choosing which save slot is
typeable — and `text` had none; `put x into field "y"` is a different path and
always worked (`set_field`).

**The four lists below are the deleted host's and are kept only as a record of
its shape.** §19 is the live set, and the two differ in both directions — the
live engine binds `flipH` nowhere and `the volume of sound N` in two places, and
answers `bottom`, `castLibNum` and `constraint` from tables this paragraph never
described.

Sprite reads: `bottom`, `castLibNum`, `castNum`, `constraint`,
`cursor`, `height`, `ink`, `left`, `locH`, `locV`, `member`, `memberNum`,
`moveableSprite`, `puppet`, `right`, `top`, `visible`, `width`. Sprite writes:
the same minus the four edges, plus `volume`. System reads: `centerStage`,
`clickOn`, `commandDown`, `controlDown`, `doubleClick`, `exitLock`, `frame`,
`freeBlock`, `key`, `keyCode`, `keyDownScript`, `machineType`, `milliseconds`,
`mouseDown`, `mouseH`, `mouseV`, `movieName`, `moviePath`, `optionDown`,
`searchPath`, `shiftDown`, `soundLevel`, `ticks`, `timer`. System writes:
`centerStage`, `exitLock`, `keyDownScript`, `searchPath`, `soundLevel`.
Window fields accepted and dropped: `drawRect`, `rect`, `titleVisible`,
`windowType`. Member reads: `memberNum`, `name`, `number`, `text`. Member
writes: `editable`, `text`. `the itemDelimiter` is owned by the interpreter.

Everything else in the enumerated vocabulary was listed in one of the three
`*_UNSUPPORTED` tables in `lingo/lingo_host.gd` — **a decision, recorded, not a
hole.** Reads against those tables answered VOID and reported the name with an
`(unsupported)` mark, so a log distinguished "the port refuses this" from "the
port never heard of this". That distinction was the most valuable thing in that
host, **it did not survive the rewrite**, and rebuilding it on
`scenes/preview_lingo_host.gd` is the highest-value thing anyone could do to this
document's honesty. Today the live host has `reached` and `unbound` tallies and
no third category, so "refused" and "never heard of" look identical.

**Event model — RETIRED FILES.** The description below is of
`lingo/lingo_engine.gd` and `director/director_runtime.gd`, both deleted. The
live dispatch is `scenes/preview/scripts.gd` (which script receives a message)
and `scenes/preview/frame_loop.gd` (when frame events fire); **this paragraph has
not been re-verified against them**, and the tier behaviour it claims should be
read as a description of Director, not as a claim about the running engine.

`lingo/lingo_engine.gd` implemented tiers 2–5 of the mouse
hierarchy (`dispatch_sprite_event`), frame-and-movie dispatch for frame events
(`dispatch_frame_event`), and `enterFrame`/`exitFrame` broadcast to every
sprite behaviour in the frame (`dispatch_sprite_behaviours`) — which the
comment there noted was load-bearing, because `whereami`, gated on by 138
`mouseUp` handlers, is set by an `enterFrame` in a sprite behaviour rather than
any frame script. `director/director_runtime.gd` drove `enterFrame`,
`exitFrame`, `startMovie`, and dispatched `mouseDown` followed by `mouseUp` on
a click.

**Not implemented in the event model**: `prepareFrame`, `beginSprite`,
`endSprite`, `stepFrame`, `stepMovie`, `idle`, `timeout`, and the window events;
the queue-the-whole-chain-then-run model (tiers are resolved lazily and stop at
the first that answers, and `dontPassEvent` is accepted and ignored); and the
D3-versus-D4 `mouseUp` sprite asymmetry, which this game being D7 makes moot.

Primary event handlers (tier 1) **are** implemented, with one divergence: all
four `*Script` properties hold a *handler name* rather than Lingo source, because
this port has no runtime compile-a-string path. Every site in this corpus sets
one to a name, which is why the shortcut holds. `when <event> then` installs a
real tier-1 handler for `mouseDown`, `mouseUp`, `rightMouseDown`, `rightMouseUp`
and `keyDown`, and it passes by default as Director's does.

**The preview host** (`scenes/preview_lingo_host.gd`) is no longer "a
deliberately smaller surface for the room preview" — it is the only host there
is, and the paragraph that used to enumerate it here listed `puppetTransition`,
`cursor`, `dontPassEvent` and `puppetSprite` among the ignored long after each
had a real arm, and listed `saveMovie` nowhere at all. **The enumeration has
moved to §19**, where a harness keeps it true. What is worth keeping from it is
the discipline it describes: the host counts what it reaches and what it does
not, and the difference between "answered VOID" and "no such builtin" is the
whole of `unbound`.

That discipline stops at the builtins. **Property reads and writes have no
`unbound` tally at all** — `LingoDiagnostics` declares `SPRITE_PROP`,
`MOVIE_PROP` and `MEMBER_PROP` and nothing ever emits them, and a host method
that answers VOID for a name it does not know is indistinguishable from one that
handled the call. That is why every property gap in §19 had to be found by
reading the code. Rebuilding the retired host's third category — "the port
refuses this" against "the port never heard of this" — is still the single most
valuable thing anyone could do to this document's honesty, and it is now a
statement about property dispatch rather than about builtins.

Its system props are the whole of §6's mouse list — `mouseH`, `mouseV`,
`clickOn`, `clickLoc`, `mouseDown`, `mouseUp`, `stillDown`, `doubleClick`,
`rightMouseDown`, `rightMouseUp`, `lastClick`, `lastRoll`, `lastEvent`,
`mouseCast`, `mouseMember`, `shiftDown`, `optionDown`, `commandDown`,
`controlDown`, `mouseDownScript`, `mouseUpScript` — plus `frame`, `ticks`,
`milliseconds`/`timer`, `machineType`, `keyCode`, `key`, `keyDownScript`,
`soundLevel`, `freeBlock`, and the window set. Bound together rather than one at
a time because they were *missing* together: an unbound read answers VOID, VOID
is falsy, and `if the mouseDown then` — four sites in this corpus, polling for a
held button — took its other branch for ever. `tools/mouse_events.gd` asserts
that none of them reads back VOID.

---

# 10. Not verified

Stated as inference, and worth confirming before anything depends on it.

- **The builtin table may be incomplete.** The fetch of `lingo-builtins.cpp`
  reported truncation, and comparing it against `lingo-builtins.h` shows two
  names in the header with no row in the table read here (`offsetRect`,
  `netPresent`). Others may be missing from the tail. The header's grouping was
  used to cross-check, but the header does not carry arity, so the arities of
  those two are unstated above.
- **The meaning of ScummVM's type tags** (function / command / hybrid /
  constant) is read off how each builtin is used, not off a comment in the
  source. The grouping is almost certainly right; the letter-to-word mapping is
  an inference.
- **Read/write marks are ScummVM's implementation state, not Director's
  specification.** Several properties Director documents as settable are
  implemented read-only there. `the width of member` is the clearest example.
  Anywhere the distinction would change a port decision, check Director's own
  documentation as well.
- **Whether `enterFrame` re-fires on a `go to the frame` hold.** Two readings of
  `score.cpp` were taken and they disagreed. The second, narrower one found no
  guard on the enter-frame dispatch and no guard on the tempo or sound
  re-application, which says it does re-fire and sounds do restart; the first
  said the opposite. §6.1 and §8 follow the second reading. This port
  deliberately does not re-enter, and the divergence is intentional either way,
  but the ScummVM claim itself is not settled.
- **`the mouseUp` version cutoff.** Reported as D3-versus-D4 behaviour. Not
  cross-checked against Director documentation, and this game is D7 so it does
  not bite here.
- **The exact `sound` verb set.** `playFile`, `stop`, `fadeIn`, `fadeOut` and
  `close` are named from the port's own handling and from the arity range;
  the full verb list was not read out of the source.
- **`castLib`'s 4 callee-position uses.** Assumed to be a compiler artefact of
  the cast-qualifier form. Not confirmed by looking at the four sites.
- **Autopuppet flag granularity.** ScummVM tracks per-aspect flags for
  position, size, colour, ink, blend, thickness and moveability. Whether
  Director's own granularity matches exactly, or is coarser, was not checked.
- **Corpus counts weight occurrences, not scripts.** A name used ten times in
  one script and a name used once in ten scripts score the same. For ordering a
  priority list that is usually the right weighting; for judging blast radius
  it is not.

---

# 11. The grammar

Sections 1–10 catalogue *names*. This section catalogues *shapes*. It is the
half a hand-written parser actually collides with, and every parser bug this
port has hit so far was a missing shape rather than a missing name:
`go to marker(+1)` (unary plus), `case whatsound of :` (a colon after `of`),
`go to the frame` (a command word followed by another keyword).

Read off `lingo-lex.l`, `lingo-gr.y` and `lingo-preprocessor.cpp` on `master`.
Nothing is copied; the productions below are restated in prose and in a
notation of this document's own. **ScummVM's `.y` file is a lower bound on
Lingo, not a definition of it** — §11.12 lists four constructs this game uses
several thousand times that ScummVM's source-level parser cannot read at all,
because ScummVM meets them as compiled bytecode instead.

## 11.1 What happens before the parser sees the text

Four passes run over the source before a single token is produced. A port that
skips them will hit "syntax errors" that are not syntax at all.

1. **Line continuation is resolved first.** Director's continuation character
   is `¬` (U+00AC, byte 0xC2 in Mac Roman). The preprocessor deletes the
   newline *after* it and keeps the `¬`, so the line-number counter still sees
   one character per source line while the parser sees one logical line. Inside
   a string literal the `¬` is replaced with a space. Everything downstream —
   whitespace skipping, token scanning — has to treat a bare `¬` as whitespace.
2. **Comments are stripped, string-aware.** `--` to end of line, but only
   outside a string, and the "inside a string" flag is force-cleared at every
   CR or LF because **Lingo has no multi-line strings**. That last rule is what
   stops one unbalanced quote from eating the rest of the file.
3. **CR becomes LF**, and trailing whitespace before a newline is dropped.
4. **Per-game patches are applied, line by line** (§12), and for D3-era movie
   and cast scripts every line before the first `macro`, `factory`, `on`,
   `global` or `property` is discarded — Director let authors leave prose above
   the first definition.

There is also one format-specific rewrite: in `.MMM` movies an `mci` command is
followed by an unquoted command string, and the preprocessor wraps the rest of
the line in quotes so the normal grammar can see one argument.

## 11.2 Tokens

The lexer is **case-insensitive throughout**. Keyword matching, identifier
comparison and `end`-clause matching all fold case, so `MouseUp`, `mouseup` and
`MOUSEUP` are one name.

| Class | Shape | Notes |
|---|---|---|
| identifier | letter or `_`, then letters, digits, `_` **or `.`** | The dot is part of an identifier. `foo.bar` is *one* token naming a variable literally called `foo.bar`. |
| integer | one or more digits | |
| float | digits `.` digits, either side optional | `.5` and `5.` both lex. So does a lone `.`, which is why dot notation cannot work at this level (§11.12). |
| string | `"` … `"` | **No escape character exists.** A quote cannot appear in a literal; scripts use the `QUOTE` constant and concatenate. No newline may appear either. |
| symbol | `#` then an identifier | The `#` is stripped; the value is the name. |
| operator | one of `- + * / % ^ : , ( ) > < & [ ]` | `%` and `^` lex but **no grammar rule uses them**, so they are a syntax error rather than an operator. |
| two-char operator | `<>` `>=` `<=` `&&` | Must be tried before their first character. |
| `=` | its own token | Spelled the same for equality and assignment; resolved by position, not by spelling. |
| newline | optional spaces/tabs/`¬`, then CR or LF | **A significant token.** The grammar is newline-terminated. |

Three tokens are not what they look like, and each one breaks a naive lexer:

- **`end` swallows the word after it.** `end` plus an optional identifier is a
  single token. `end if`, `end repeat` and `end tell` become three dedicated
  block-terminator tokens; everything else — `end mouseUp`, `end`, and notably
  `end case` — becomes one "end clause" token carrying the trailing name.
  `end case` is therefore *not* a block terminator in ScummVM; it is a generic
  handler end. A lexer that emits `end` and `case` separately has a different
  language.
- **`go to` is one token.** The lexer matches `go` optionally followed by
  whitespace and `to`. There is no separate `to` to consume, and `go` and
  `go to` are indistinguishable to the parser.
- **`when <event> then <rest of line>` is one token.** It matches only the five
  events `keyDown`, `keyUp`, `mouseDown`, `mouseUp`, `timeOut`, and the text
  after `then` is captured **raw, unparsed, to end of line** and compiled
  separately as a primary event handler (§6.3). A parser that tries to parse
  the tail as a statement in the enclosing context is doing something else.

`factory` is recognised only at the start of a line.

## 11.3 Reserved words, and the two-tier split that makes them not reserved

This is the single most important structural fact about Lingo's grammar and the
one most likely to be missed.

The lexer gives about sixty words their own token. The grammar then hands
almost all of them straight back as identifiers, through two non-terminals:

- **`CMDID`** — words that may begin a command statement *and* be used as an
  ordinary identifier: `abbreviated` `abbrev` `abbr` `after` `before` `cast`
  `castLib` `char` `chars` `date` `delete` `down` `field` `frame` `hilite` `in`
  `intersects` `into` `item` `items` `last` `line` `lines` `long` `member`
  `menu` `menuItem` `menuItems` `movie` `next` `number` `of` `previous`
  `repeat` `script` `short` `sound` `sprite` `the` `time` `to` `while` `window`
  `with` `within` `word` `words`.
- **`ID`** — `CMDID` plus `else` `end` `exit` `factory` `global` `go` `if`
  `instance` `macro` `method` `on` `open` `play` `property` `put` `return`
  `set` `tell` `then`.

`ID` is what a handler name, a parameter name, a `global`/`property` name, a
`repeat with` loop variable and a plain variable reference all accept. So
**`the`, `to`, `of`, `end`, `if` and `then` are all legal variable names**, and
`on end` is a legal handler. Nothing in Lingo is truly reserved; a word is a
keyword only where the grammar is looking for one.

The practical consequence for a port: a lexer that classifies tokens as
`keyword` versus `identifier` and a parser that trusts that classification will
reject valid scripts, and — worse — will parse `set the keyDownScript to EMPTY`
as a property called `to` unless the property-name scan knows which words can
close a `the` phrase. This port already carries a `RESERVED_AFTER_PROP` table
for exactly that reason and a comment saying why.

## 11.4 Script structure

A script is a sequence of parts, each ending in a newline:

- a blank line,
- a **macro** — `macro NAME [params] ⏎ statements`, ending where the next
  definition begins (D2/D3 compatibility form),
- a **factory** — `factory NAME ⏎` followed by zero or more `method NAME
  [params] ⏎ statements`,
- a **handler** — `on NAME [params] ⏎ statements [end [NAME]]`,
- a bare **statement**, or
- a **stray `end`**, which the grammar accepts and discards at script level and
  between factory methods, with the comment that it happens "for some reason".

Two forms of handler exist and both are accepted unconditionally:

- **D3 form**, terminated by `end` (optionally naming the handler; the name is
  compared case-insensitively and a mismatch is only a warning).
- **D4 form, with no `end` at all** — the handler runs to the next definition.

Parameter lists are comma-separated `ID`s and **a trailing comma is legal**.
The `end` clause may itself be followed by a comma-separated list of names,
which is parsed and thrown away.

`global` and `property` are also script parts, and where one is written decides
its reach. **A `global` outside any handler declares the name for every handler
in that script**, so a handler that assigns it without repeating the declaration
is still writing the movie's global and not a local of its own. Getting that
wrong is invisible from the AST — the assignment runs, the handler returns, and
the value goes with the frame — and it is how `itamar-magichat` reached
`on startMovie / gFirstRun = 1` and finished the boot with an empty globals
dictionary. `tools/lingo_scope_check.gd` asserts the declaration reaches a
sibling handler, and that an *undeclared* name is still local.

## 11.5 Statements

Every statement is terminated by a newline. Sometimes that newline belongs to a
statement nested inside it — `if x then put y` ends when `put y` ends — which
is why "consume the line" is the wrong mental model.

**Command call.** `CMDID args` (§11.7). This is the general form and it is why
almost every keyword also appears in `CMDID`: any of them can be a command name.

**Navigation.** `put args`, `go args`, `play args`, `open args` each get their
own production so their keyword token can head a statement. `go` and `play`
additionally accept **frame arguments**, a small grammar of their own:

| Written | Compiles to |
|---|---|
| `go frame E` / `go to frame E` | one argument, marked as a frame |
| `go movie E` | *two* arguments — the integer `1`, then the movie |
| `go frame E of movie F` | frame, then movie |
| `go E of movie F` | expression, then movie (no `frame` keyword; ScummVM calls this "weird but valid") |
| `go frame E F` | frame, then a second expression with no separator |

The frame argument is wrapped in a marker node purely so that `play frame done`
is not mistaken for `play done`. That is the shape of the problem: the same
words mean different things depending on what precedes them.

**`open E with F`** is a separate two-argument form.

**Loop control.** `next repeat`, `exit repeat`, `exit`. Note there is no bare
`next`.

**`return`** with or without an expression.

**Chunk statements.** `delete <chunk>` and `hilite <chunk>` — both take a chunk
expression, not a general expression, and neither is a builtin call.

**`put` assignment.** `put E into P`, `put E after P`, `put E before P`, where
`P` is a variable or a chunk expression. `put E` with no target is the
message-window echo and goes through the command-call path instead.

**`set` assignment.** `set P to E` or `set P = E` — **`to` and `=` are
interchangeable here**, and `P` is a variable or a writable `the` phrase.

**Declarations.** `global`, `property`, `instance`, each followed by a
comma-separated `ID` list with an optional trailing comma.

**Conditionals.** Six shapes, all in the grammar explicitly:

```
if E then S
if E then ⏎ S… [end if]
if E then S else S
if E then S else ⏎ S… [end if]
if E then ⏎ S… else S
if E then ⏎ S… else ⏎ S… [end if]
```

**`end if` is optional.** A missing one produces a warning and parses anyway.
The block body uses a restricted statement list that cannot itself contain a
stray `end if`, which is how nesting stays unambiguous.

**Loops.**

```
repeat while E ⏎ S… end repeat
repeat with ID = E to E ⏎ S… end repeat
repeat with ID = E down to E ⏎ S… end repeat
repeat with ID in E ⏎ S… end repeat
```

Note the loop bound uses `=`, not `to`, for the initial value, and that
`end repeat` is **required** here where `end if` is not.

**`tell`.** `tell E to S` (one statement only) or `tell E ⏎ S… end tell`.

**`when <event> then <text>`** — see §11.2.

There is **no `case`/`otherwise` in ScummVM's source grammar.** The tokens are
declared and commented out. See §11.12.

## 11.6 Expressions

Precedence, lowest to highest:

| Level | Operators | Associativity |
|---|---|---|
| 1 | `and` `or` | left — **both at the same level** |
| 2 | `<` `<=` `>` `>=` `=` `<>` `contains` `starts` | left |
| 3 | `&` `&&` | left |
| 4 | `+` `-` | left |
| 5 | `*` `/` `mod` | left |
| 6 | unary `-`, unary `+`, `not` | right |

`and` and `or` sharing one level is a real difference from the C-family
ranking, and it is silent: `a or b and c` groups as `(a or b) and c`, not as
`a or (b and c)`.

Unary `+` exists and **means nothing** — the grammar returns the operand
unchanged. It is not decoration: `go to marker(+1)` is in this game's own
scripts and a parser without a unary-plus case fails on it.

Unary operators take a *simple* expression, not a full one, so `not a = b`
groups as `(not a) = b` and `-a * b` as `(-a) * b`.

`intersects` and `within` are **not** in the precedence table. They have a
dedicated production: `sprite E intersects S` / `sprite E within S`, where the
left side must be the literal word `sprite` followed by an expression and the
right side is a *simple* expression — commonly a bare channel number, as in
`sprite 5 intersects 3`. A parser that treats them as ordinary infix operators
gets the same answer here but will diverge on the right operand's extent.

**Simple expressions** are integer, float, symbol, string, `not S`, a
parenthesised expression, a function call, a variable, a chunk expression, an
object reference, a `the` phrase, or a list. The grammar carries **three
near-duplicate copies** of the expression rules — the full one, one that cannot
begin with unary `+`/`-`, and one that excludes `=`. They exist to disambiguate
two specific situations and both matter to a hand-written parser:

- **No unary math in a second argument.** `cmd 1 + 1` must be `cmd(1 + 1)` and
  never `cmd(1, +1)`. The only way to say that in an LALR grammar is to forbid
  the second of two adjacent expressions from starting with a sign.
- **No `=` in a `the`-phrase object.** `set the volume of sound 2 = 50` must
  not read `sound (2 = 50)`.

## 11.7 Command calls versus function calls

Lingo has one call, spelled two ways, and the spelling is not the difference —
**position is**. A call in statement position is a command (its result is
discarded); a call in expression position is a function. The bytecode makes
this explicit by pushing a different argument-count marker for the two cases
(§13), so "command" and "function" are properties of the *call site*, never of
the name.

Argument syntax, for a command:

| Written | Meaning |
|---|---|
| `cmd` | no arguments |
| `cmd a` | one |
| `cmd a, b, c` | three |
| `cmd a b` | **two**, with no separator |
| `cmd a b, c, d` | three, first two unseparated |
| `cmd()` | none |
| `cmd(a, b)` | two |
| `cmd(a,)` | one, trailing comma |
| `cmd(obj method arg)` | two — an object and a method name, D3 style |
| `cmd(obj method arg, …)` | the same plus more |

A trailing comma is legal in every list. The `cmd a b` form with no comma is
the one that surprises: it is why the "no unary math" expression copy exists,
and it is the ambiguity behind a whole class of shipped-game patches (§12).

For a **function** call in an expression, the parenthesised forms are the same
minus the bare `cmd a` form. So `foo 1, 2` is a statement and `foo(1, 2)` is
either.

**Reference arguments** — used by `field`, `cast`, `member`, `castLib`,
`script` and `window` — are a smaller set: one bare simple expression
(`field "x"`), or `()`, or a parenthesised list. `field "x"` and `field("x")`
are the same thing.

## 11.8 Chunk expressions

```
char E of S              char E to E of S
word E of S              word E to E of S
item E of S              item E to E of S
line E of S              line E to E of S
the last char|word|item|line in|of S
```

The source `S` is a *simple* expression, so chunk expressions nest naturally
right-to-left: `word 2 of line 3 of x`. The index `E` is a full expression, so
`line i - 102 of field "x"` works and the arithmetic binds before the `of`.

`in` and `of` are interchangeable wherever the grammar writes `in|of`.

The reference forms share this production because Director treats them as the
same kind of thing — a designator you can read, write and take a chunk of:

```
field <refargs>
cast <refargs>            cast S of castLib S
member <refargs>          member S of castLib S
castLib <refargs>
```

`of castLib` is part of the *reference*, not a trailing modifier. A parser that
handles `member "x" of castLib "y"` but forgets the same suffix after the
parenthesised form `field("x") of castLib 1` will drop the library and leave
`of castLib 1` dangling as a separate statement. That is not hypothetical; it is
one of this port's live grammar bugs (§16.3).

## 11.9 `the` phrases

```
the ID                              -- a system property
the ID of <theobj>                  -- a qualified property
the number of <theobj>              -- the entity's number
the abbreviated|abbrev|abbr|long|short date|time
the number of chars|words|items|lines in|of S
the number of menuItems in|of menu S
the number of menus
the number of xtras                 -- D5
the number of castLibs              -- D5
the last char|word|item|line in|of S
```

`<theobj>` is where the qualified-entity kinds live, and they are **distinct
grammar productions, not ordinary expressions**:

- a simple expression (covers `of sprite(5)`, `of member "x"`, `of field "f"`,
  `of window "w"` written as calls),
- `menu S`,
- `menuItem S of menu S`,
- **`sound S`**,
- **`sprite S`**.

`sound` and `sprite` earn their own node because the word is not a function —
there is no `sound(2)` object to evaluate. `the volume of sound 2` is a
two-part designator, and a port that lowers it to "property of the result of
calling `sound(2)`" has built a value where Director has an address. This game
names `the volume of sound N` on 67 lines, 66 of them writes; both the parse and
the host binding are now closed (§16.3, `docs/bugs-closed.md` 27).

The **writable** variants (the left-hand side of `set`) use the `=`-free
expression copy for the object, so `set the X of sprite N to …` cannot mis-read
the `to`.

## 11.10 Lists and property lists

```
[ ]  [ e, e, e ]        -- linear list
[ : ]                   -- empty property list
[ k: v, k: v ]          -- property list
```

A property list must *start* with a key/value pair; after that, bare
expressions are allowed and are compiled as if keyed by their index. Keys may
be a symbol, an identifier (treated as a symbol), a string, an integer or a
float.

`[:]` is the only way to write an empty property list — `[]` is an empty linear
list — and it is a lexical trap, because `:` is otherwise only a property-list
separator.

## 11.11 Error recovery is part of the grammar

Roughly forty productions have a duplicate carrying an explicit `error`
symbol. When ScummVM's "trim garbage" flag is on, it warns, discards the tokens
from the error to the end of the line, and **keeps the statement it had already
built**. When the flag is off, the parse aborts.

This is not defensive coding, it is a statement about the corpus: real Director
movies contain lines that no grammar accepts, and a parser that only has
"accept" and "reject" cannot run them. §12 is the catalogue of what it is
recovering from.

## 11.12 What ScummVM's source grammar cannot read

ScummVM compiles D4-and-later movies from **bytecode**, not from source text.
Its `.y` file therefore covers the D3/D4 authoring language and stops. Four
constructs this game uses heavily are absent from it entirely:

| Construct | In this game | Why it is missing |
|---|---|---|
| Bare assignment `x = 1` | **4,244 statements in 690 scripts** | There is no production for it. `set x = 1` is the only assignment. `x = 1` would be recovered as the command `x` with the rest trimmed. |
| Dot notation `sprite(N).locH` | **940 hits in 323 scripts**, plus 213 in 93 for `member(…).prop` | `.` is not an operator in the lexer, and a lone `.` matches the float rule. There is no member-access production. |
| `case E of` / `otherwise` | **78 statements in 43 scripts** | The `tCASE`/`tOTHERWISE` tokens are declared and commented out. |
| `sprite(N)` as a value | throughout | `sprite` appears only inside `the … of sprite …` and the intersects/within rules. |

**This is the concrete form of "ScummVM is a source, not an authority."** Its
builtin and property tables are near-complete because they are shared with the
bytecode path; its *grammar* is not, because the grammar is only used for the
minority of movies that ship source. Anywhere this port's parser accepts more
than `lingo-gr.y` does, the port is right and the `.y` file is out of scope.

## 11.13 The naive-parser checklist

Every item here is a place where a reasonable first implementation is wrong.

1. **A newline is a token.** Not whitespace.
2. **Keywords are not reserved.** `the`, `to`, `of`, `end`, `if` are all legal
   variable and parameter names.
3. **`end` eats the next word.** `end case` is not a block terminator.
4. **`go to` is one token**, and `go` takes bare words (`frame`, `movie`,
   `loop`, `next`, `previous`) that are not variables.
5. **`play done` is not `play("done")`** — it compiles to a zero-argument
   `play`, which pops the play stack.
6. **`go frame E of movie F`** is a two-argument navigation, not a chunk
   expression with a trailing modifier.
7. **`when <event> then <text>` is one lexical unit** and the text is not
   parsed in place.
8. **A command can take two arguments with no comma between them**, which
   forces the "second argument cannot start with a sign" rule.
9. **Unary `+` exists and is a no-op.**
10. **`and` and `or` have equal precedence.**
11. **`intersects`/`within` are a dedicated production**, not infix operators,
    and their left operand must be spelled `sprite E`.
12. **`set X to E` and `set X = E` are the same statement.**
13. **`=` is both assignment and equality**, resolved by position.
14. **`in` and `of` are interchangeable** in `the number of … in|of`.
15. **`of castLib` is part of a reference**, including after `field(…)`.
16. **`the … of sound N` and `the … of sprite N` are designators**, not
    property access on a call result.
17. **`end if` is optional; `end repeat` and `end tell` are not.**
18. **A handler may have no `end` at all** (D4 form).
19. **Strings have no escape character** and cannot span lines.
20. **`#name` is a symbol literal**; the `#` is not an operator.
21. **`[:]` is the empty property list.**
22. **`¬` is the line-continuation character**, and it counts as whitespace
    everywhere, including mid-token scanning.
23. **A dot inside an identifier is part of the identifier.** `a.b` is one
    name; `sprite(1).locH` only splits because `)` precedes the dot.
24. **Trailing commas are legal** in argument lists, parameter lists and
    declaration lists.
25. **Stray `end` and stray `end if` at top level are legal.**
26. **`the number of X` has two unrelated meanings** — a chunk count
    (`the number of lines in f`) and an entity number (`the number of member
    "x"`). Same three words.

---

# 12. What the patch table says about real Lingo

`lingo-patcher.cpp` is a table of per-game, per-line source substitutions
applied during preprocessing. The individual entries are worthless to this port
— they name other games' movies — but the *classes* are evidence about what
ships in commercial Director movies, and therefore about what a parser meets.

**Score-window text concatenated into the script.** By far the largest class.
Director's Score window let authors annotate frames, and that annotation ends up
appended to the script text: `Channels 17 to 18`, `Frames 150 to 160`, absolute
Mac file paths, and free prose (`Are you sure to cut off  KANJI Talk`). Nothing
parses. This is what the `error` productions and the trim-garbage flag exist for.

**Prose spliced onto the end of a valid statement.** `go to frame "Info b"If
you have not paid` — a valid statement followed immediately, with no separator,
by a sentence. Trimming to end of line keeps the navigation.

**A missing operator.** `"Error message number: " string(filer)` — the `&` was
dropped. Note that this is *almost* the legal two-adjacent-arguments form, which
is why it got past the author.

**A stray keyword.** `set Spacesuit = 0 then` — a copy/paste `then` on an
assignment.

**A doubled word.** `set the the soundLevel to 7`.

**Unbalanced delimiters.** An extra `)`, and an unterminated string literal
(`alert("Sorry. No keyword was entered for this recipe.)`). The second is
exactly why the comment stripper force-closes the in-string flag at every line
end: without that, one missing quote silently consumes the rest of the script.

**Space where a comma was meant.** `FileIO(mnew, "read" mymovie)` appears in
four different games. It is legal-looking because the D3 method-call form
`obj(method arg)` really does allow one unseparated pair — so `"read" mymovie`
is grammatically the same shape as a valid construct, and parses to something
other than what was intended. ScummVM's note calls it "ambiguous syntax that's
parsed differently between D3 and later versions", which is the honest
description: this is not a typo class, it is a *language* class.

**A trailing argument on a form that takes none.** `go to the frame 0`, patched
to `go to the frame`. And a `GO "…" OF MOVIE "…","242,197"` with an extra
argument the form does not accept.

**A missing block terminator.** One game is patched by *inserting* `end repeat`.

**A lexer edge case.** ScummVM's own FIXME records that `LoopIt .5` does not
come out as `0.5`, and the patch deletes the line rather than fix the lexer.

**Whole-handler replacements** make up the rest of the file — CD-drive
detection, dead loops, timing. Those are environment fixes, not language
evidence, and are not relevant here.

The lesson for this port is narrow and useful. **A Director script is not
guaranteed to be a Lingo program.** ScummVM's answer is two-layered: a grammar
that can discard a line tail and keep the statement, and a per-game table for
what that cannot save. This port currently parses 3,307 of 3,307 authored
scripts in this game with neither mechanism, which means it does not need them —
but the moment the same compiler is pointed at another title, the absence of any
recovery path is a hard stop rather than a warning.

---

# 13. What the bytecode layer adds

Only the parts that say something about *semantics*. The file format is not
relevant to a port that compiles from source text.

**`and` and `or` do not short-circuit.** They are single opcodes that pop two
operands. Both sides are always evaluated, both are coerced with an integer
conversion, and the result is the integer `0` or `1` — not a boolean and not the
operand. §2.3 above says they short-circuit; that is wrong, and §17 records the
correction. It matters whenever an operand has a side effect or is expensive:
`if soundBusy(1) and startTalk() then` calls `startTalk` in Director whether or
not the sound is busy.

**Command and function are the same call.** Every call pushes an argument-count
marker first, and the marker has two flavours — one meaning "a result is wanted",
one meaning "discard it". The call opcode is identical. So the command/function
distinction lives at the call site and is decided by the grammar's
statement-versus-expression position, never by the name. A port with two
dispatch tables has invented a distinction Director does not make.

**`put into`, `put after` and `put before` are one opcode** with the mode packed
into a nibble of its operand alongside the variable's storage class. They are
three spellings of one operation on a designator, which is the same grouping the
grammar uses.

**Property lists are built key-first.** The constructor pops value then key,
repeatedly, and inserts at the front — so a source-order key/value stream comes
out in source order. An odd argument count is tolerated with a warning and the
stray entry discarded.

**A method call re-types its first argument.** The object-call opcode looks at
the first argument on the stack and, if it is a symbol, converts it to a variable
reference. This is the runtime half of the `obj(mMethod, args)` form: the method
name travels as data.

**`of` is an opcode.** Chunk access is a runtime operation on a reference, not
something the compiler flattens.

**`delete` and `hilite` operate on a chunk reference** read out of a variable —
consistent with the grammar giving them chunk-only argument positions.

**There are four distinct "the" access opcodes**, differing in whether the entity
is identified by number or by name and whether a field id follows. The name-based
one exists because D4 bytecode can address a property of an object with no entity
number. A source-only port needs the entity/field pair; the name form is a hint
that the entity table is not closed.

---

# 14. What the code generator confirms

`lingo-codegen.cpp` lowers the AST, and a few of its decisions settle questions a
source-level reading leaves open.

**Evaluation order is left, then right, then operate.** Binary operators compile
both operands unconditionally before the opcode — the other half of the
no-short-circuit finding. `put` compiles the *value* first and the *target
reference* second. Conditions in `if` and in all three `repeat` forms compile to a
single "jump if zero", so a condition is evaluated once per iteration.

**Bare words after certain commands become symbols, not strings.** `go loop`,
`go next` and `go previous` compile their bare word to a symbol. Every bare
identifier argument to `playAccel` does the same. So does the verb of
`sound close|fadeIn|fadeOut|playFile|stop`. A port that passes these as strings is
relying on its own host to compare loosely.

**`play done` compiles to `play` with zero arguments.** Not `play("done")`.

**Any first argument that is a bare variable is compiled by reference**, for both
commands and functions — because it might be a method name or an out-parameter.
Only the first. This is the mechanism that makes `obj(mMethod, arg)` work without
a separate syntax.

**Constants beat variables.** A bare identifier is checked against the builtin
constant table *before* any variable lookup, so a local named `empty` cannot
shadow `EMPTY`. This port resolves constants in the same place, which is the
right one.

**`field` used as a function name is special-cased** to a dedicated field opcode
rather than a generic call, in both value and reference mode.

**`the X of <thing>` resolves at compile time where it can.** Chunk, cast and
field objects look up a numeric field id in the entity table and compile to a
direct entity access; anything else falls back to generic object property access.
An unknown property on `set the X` is a *compile-time* warning, not a runtime
miss — the opposite of this port's design, where an unbound property is reported
when it is read. Both are defensible; only one of them can tell you about a
property the game never actually reaches.

**In D3-era movies a bare identifier that looks like a cast reference becomes an
integer** (`A13` → a slot number). Version-gated, and not applicable to this game,
but it explains the patch that deletes an `installmenu A13`.

---

# 15. Files read, and files skipped

From `engines/director/lingo` on `master`, in addition to the seven files the
header of this document already names.

**Read for §11–§14:**

| File | Used for |
|---|---|
| `lingo-lex.l` | §11.1–11.2, the token classes and the three composite tokens |
| `lingo-gr.y` | §11.3–11.12, the whole grammar |
| `lingo-preprocessor.cpp` | §11.1 — continuation, comments, the D3 header rule, `mci` |
| `lingo-patcher.cpp` | §12 |
| `lingo-bytecode.cpp` | §13, semantics only |
| `lingo-codegen.cpp` | §14 |
| `lingo-code.cpp` | spot-checked to confirm `and`/`or` evaluate both sides |
| `lingo-ast.h` | node inventory, cross-checked that §11.5 lists every statement form |
| `lingo-gr.h` | token enum, used to confirm `case`/`otherwise` are absent |
| `docs/d7-keywords.txt` | the Director 7 keyword inventory, cross-check on §11.3 |

**Skipped, with reasons:**

- `xlibs/` — out of scope by instruction.
- `xtras/`, `xtras-cast/` — per-Xtra implementations. §7.3 already covers the
  standard XObject method set, which is the only part that is language.
- `lingodec/` — the Lingo *decompiler*, used to turn bytecode back into source.
  It defines no language behaviour; it consumes it. Its `codewritervisitor.cpp`
  would be a second opinion on statement shapes but a worse one than the grammar.
- `tests/*.lingo` — ScummVM's own test scripts. Useful as examples but not
  normative, and reading them would risk transcribing their content.
- `lingo-mci.cpp` — Windows MCI command strings. A separate mini-language inside
  a string argument, and this game has no `mci` call.
- `lingo-utils.cpp` — character-normalisation tables for non-Latin scripts.
  Relevant only to Japanese and Korean titles.
- `lingo.cpp`, `lingo.h`, `lingo-object.h`, `lingo-the.h`, `lingo-builtins.h`,
  `lingo-code.h`, `lingo-codegen.h`, `lingo-bytecode.h` — already covered by
  §1–§7, or headers for files listed above.

---

# 16. Cross-reference against this port's parser

The port's compiler is `lingo/compile/lingo_grammar.gd` (tables),
`lingo/compile/lingo_lexer.gd` and `lingo/compile/lingo_parser.gd`, a
transliteration of `tools/lingo_compile.py`. It is a hand-written
recursive-descent parser with a 44-word keyword set, six precedence levels, and a
small table of commands whose first argument is a bare word.

## 16.1 How the evidence was gathered

Every script in the game was extracted from its container in **authored source
form** —

```
godot --headless --path . --script tools/director_extract.gd -- --file <container> --out <dir>
```

— over all 83 containers under `games/piposh2/PIP2DATA/` plus `MASTER.CST`,
`strtgame.dir` and `HEZSAVE.DIR`. That yields **3,267 scripts, 811 KB, 3,371
handlers**. This is not the same corpus as `reference/lingo/`: that tree is the
ProjectorRays decompilation of the same movies, and a decompiler normalises
syntax. Where the two disagree about *shape*, the extracted text is the original.

The port's parser was then run over all 3,267 — via the Python original with the
three GDScript-only fixes applied (unary plus, the command-word head gate, and
`case … of :`), so the result reflects the shipping parser. **All 3,267 parse.**
There are no hard failures, which is why the analysis below is about *silent*
misparses. Those were found two ways: by looking for statements whose parse left
a keyword such as `of` or `then` heading a statement of its own, and by
pattern-matching the corpus against each grammar form in §11.

## 16.2 Grammar ScummVM supports, this parser does not, and this game never uses

Listed so that each absence is a recorded decision rather than a hole. All have
**zero** occurrences in the extracted corpus.

- ~~**`#symbol` literals.**~~ **Closed.** The lexer had no `#` in either operator
  table and raised "unexpected character" -- the only item here that failed
  *loudly*, and the one that mattered, because `call(#mouseUp, obj)` is how every
  object message in §7.1 is spelled. `lingo_lexer.gd` emits a `symbol` token and
  the interpreter makes it a `StringName`, which is the type `ilk` already answers
  `#symbol` for. Still 0 occurrences in the corpus.
- **`[:]`**, the empty property list. Parse error.
- **`the last char|word|item|line of X`.** Parse error — `last` is read as a
  property name and the chunk head that follows has nowhere to go.
- **`macro`, `factory`, `method` definitions.** Only `on` is recognised.
- ~~**`delete <chunk>`**~~ **closed**, and it was not harmless. Parsed as a
  command call, the chunk arrived as a *value* and the place it came from was
  never rewritten — so `repeat while str <> EMPTY / delete word 1 of str` never
  shortens `str`. One boot of `itamar-park` made **199,833** calls to the unbound
  name before the step budget aborted the handler that reads its ini file. It is
  a statement now (`lingo_parser.gd`, gated on a chunk keyword following, so
  FileIO's own `delete` method still parses as the call it is), and the chunk's
  **separator goes with it** — `LingoValue.delete_chunk` rather than writing ""
  into the chunk, which is the difference between a loop that terminates and one
  that does not. **`hilite <chunk>`** is still absent: it parses as a command
  call named `hilite`, which nothing binds.
- **`cast N` / `cast N of castLib M`** as a reference. `cast` is not a keyword
  here; it parses as a command call.
- **`put E after|before P`.** The parser has the modes; nothing uses them.
- **Two space-separated arguments** (`cmd a b`). The argument loop only continues
  on a comma, so the second argument becomes a statement of its own. The one
  candidate in the corpus, `savemovie savepath & "hezsave.dir"`, is a single
  expression and parses correctly.
- **`open E with F`.**
- **`the number of menus|xtras|castLibs|menuItems`.** The `menuItems` form parses
  to a chunk count with the unit `menuitem`, which is meaningless.
- **`¬` line continuation.** The lexer knows only `\`. No byte 0xAC appears
  anywhere in the corpus, in either encoding — this game's authors never used it.
- **Trailing commas** in argument lists, and `cmd(arg,)`.
- **Handlers with no `end`** (D4 form). All 3,371 handlers here are terminated.
- **`%` and `^`**, which ScummVM lexes and then has no rule for; the port rejects
  them at the lexer. Same outcome by a different route.
- **`error`-production garbage recovery.** The port has none, and has not needed
  any for this game.

Two divergences are about *shape agreement* rather than support:

- **`and`/`or` precedence.** ScummVM puts them on one left-associative level;
  this port ranks `or` below `and`. Fifteen lines in the corpus mix the two
  operators and **every one of them is fully parenthesised**, so no site depends
  on the ranking. It is still worth fixing, because the next title will not be so
  careful.
- **`intersects`/`within`** are infix operators at the comparison level here and a
  dedicated production in ScummVM. Both accept `sprite 5 intersects 3` and
  `sprite the clickOn intersects 36`, which are the forms this game uses.

## 16.3 Grammar gaps this game's scripts actually contain

### `the <prop> of sound N` — 67 lines, 52 scripts — CLOSED, see `docs/bugs-closed.md` 27

66 of the 67 are `set the volume of sound N to …` and 2 are reads, one line being
both (`set the volume of sound 3 to the volume of sound 3 - 20`); the earlier
count of 65 was of statements and missed the reads. Channels 1 to 4. What follows
is how it failed, kept because it is the clearest worked example of §11.9's
address-versus-value distinction.

ScummVM's grammar makes `sound N`
a qualified entity (§11.9). This parser has no case for it, so `_parse_the` falls
through to its generic branch and produces `prop_of(prop: "volume", target: call
sound(N))` — a property of the *result of calling* a function named `sound`.
`lingo/lingo_interpreter.gd` then reaches its assignment path for `prop_of`, which
accepts only a `sprite_ref` owner, and records `cannot assign to prop_of call`
before continuing. **The volume is never set.** Because `_fail` only appends to an
error list, nothing stops and nothing is visibly wrong except that speech and
effects play at whatever volume the last successful write left behind.

This was the largest real gap in the parser by script count, and the clearest
example of why §11.9 draws the distinction it does: Director has an *address*
here and the port built a *value*. The parse was fixed first and the host binding
second, and between those two fixes the symptom was identical while the cause was
not — which is the whole of `docs/bugs-closed.md` 27.

### `play done` — 48 statements, 48 scripts

The parser reads it correctly, as `play("done")`, and `lingo/lingo_host.gd` maps
`play` onto `go` and trims the leading word — so it becomes a no-op. §1.4 above
states that "this game does not [use `play done`]"; **that is wrong.** The claim
was drawn from `reference/lingo/`, and 96 files in that tree contain `play done`
too. The game has 160 `play frame …` calls and 48 `play done`s, which is a
matched-looking pair: the port is running the calls and dropping the returns.
Whether that is visible depends on whether any of the 48 sites relies on returning
to where `play` was issued rather than continuing from where the played sequence
ended — a behavioural question this note does not answer, and one worth answering
before the pairing is dismissed a second time.

### `go to frame E of movie F` — 6 statements, 6 scripts

`HEZSAVE.DIR` scripts 7, 11, 14 and 15, and `MASTER.CST` scripts 87 and 95:

```
go to frame "aftersave" of movie cdsavepath & "saveload.dxr"
go to frame "path5" of movie "day1.dir"
```

The command-word loop collects `to` and `frame`, parses the label, then stops
because the next token is not a comma. **The movie is dropped**, so the call
becomes a jump to a marker named `aftersave` in the *current* movie, and the
leftover `of movie …` is parsed as a separate statement — a call to a handler
named `of`. Four of the six are the save/load round trip and two are the return
into `day1` after a cutscene, so this is a navigation bug in a save path, which is
the worst place to have one.

The grammar form needed is the frame-argument set in §11.5. The host already
understands the two-argument `(frame_or_marker, movie)` shape — `_go` in
`lingo/lingo_host.gd` handles it for the `go(1, "exodus.dir")` spelling — so this
is a parser fix that needs no host work.

**Closed.** `lingo_parser.gd:_parse_optional_of_movie` appends the movie as a
plain trailing argument, gated on the command's own keyword set so only `go` and
`play` can pick it up. Deliberately *without* a `"movie"` marker word between the
two: that spelling exists in `_go` for `go to movie "x"` and discards the frame.

### `field (E) of castLib N` — 4 statements, 4 scripts

`SAVELOAD.dir` scripts 20, 24, 38 and 39:

```
put item i of SaveNames into field ("save" & i) of castLib 1
```

`_parse_primary`'s `field` branch takes the parenthesised path and never looks for
a trailing `of castLib`, so the library is dropped and `of castLib 1` becomes
another `of` statement. The bare-string path (`field "x" of castLib "master"`, 640
hits in 154 scripts) does call `_parse_optional_castlib`, and so does the
`the number of member (…) of castLib …` branch in `_parse_the` — which is the fix:
`cast = args[1] if args.size() > 1 else _parse_optional_castlib()`, a line that
already exists three functions away. `member(…)` has the same omission but no site
in this game.

**Closed**, by exactly that line, on both `field(…)` and `member(…)`. Each of the
four sites shed two junk statements, which is visible as the port's AST moving
*toward* the committed one: `SAVELOAD.dir` fell from 1,792 differences to 1,772.

### `when <event> then <stmt>` — 2 statements, 1 script

`strtgame.dir` script 306:

```
when keyDown then go to "mainmenub4"
when keyDown then gulu
```

`when` is not a keyword here, so this parses as a call to a handler named `when`
with the argument `keyDown`, followed by a second statement starting at `then`.
Both are junk. §9.1 above already notes four uses of this construct in the
decompiled tree and correctly calls it grammar rather than a binding. It is
Director 3's primary-handler installation (§6.3), and the port implements no
tier-1 handlers at all, so parsing it would only convert a silent misparse into a
recorded unimplemented feature — which is still the better of the two.

**Closed on that reasoning, and it was worse than "junk" makes it sound.** The
second statement was `go to "mainmenub4"` — a *navigation*, run unconditionally
every time `gomenu` was called instead of when a key was pressed. The parser now
claims the whole three-token shape (`when`, one of the five events, `then`) and
hangs the tail off a `when` node; `lingo_interpreter.gd` reports it under the
`event` category and executes nothing. Only the full shape is claimed, because
`when` is a legal variable name (§11.3) and `tools/lingo_designator_check.gd`
asserts one still works. The handler beside it, `gulu`, installs the same
behaviour through `the keyDownScript`, which the host does bind, so the menu is
not left without a way out.

### `the <prop> of window "x"` — 2 statements, 2 scripts

`MASTER.CST` scripts 12 and 69, both `set the windowType of window "…" to 2`.
Same mechanism as `of sound`: a generic `prop_of` over a call, and the
interpreter's assignment path rejects it. The dot spelling
`window("x").windowType = 2` *does* work, because the `dot` assignment path has a
case for an owner that evaluates to a string. So two spellings of the same thing
behave differently, which is exactly the kind of divergence that looks like a data
problem later.

**Closed** with a `window_prop` designator node, read and write, routed to the
host's *system*-property pair rather than to a `set_window_prop` of its own —
because that is already where these names arrive from the other spelling in this
corpus, `tell window("map.dxr") / set the windowType to 2`, and
`lingo_host.gd`'s `WINDOW_FIELDS` accepts and drops them there. A second entry
point to one table would be a second chance for the two spellings to disagree,
which is the fault being closed. The named window is evaluated and discarded —
nothing to place, title or resize on one stage (§7.4) — but it stays on the node,
which is the whole reason this is a designator and not `prop_of` over a call.

## 16.4 The work queue

Ordered by how many of this game's scripts hit each gap.

| # | Gap | Scripts | Statements | Where | State |
|---|---|---|---|---|---|
| 1 | `the <prop> of sound N` is not a designator | **52** | 65 | `lingo_parser.gd:_parse_the`, plus an assignment case in `lingo_interpreter.gd` | parser closed; see below |
| 2 | `play done` is a no-op; there is no play stack | **48** | 48 | `lingo_host.gd:_go` and the navigation model | open — needs a decision, not a fix |
| 3 | `go to frame E of movie F` drops the movie | **6** | 6 | `lingo_parser.gd:_parse_primary`, command-word argument loop | closed |
| 4 | `field (E) of castLib N` drops the library | **4** | 4 | `lingo_parser.gd:_parse_primary`, `field` parenthesised branch | closed |
| 5 | `the <prop> of window "x"` cannot be assigned | **2** | 2 | same fix as #1 | closed |
| 6 | `when <event> then <stmt>` misparses into two junk statements | **1** | 2 | `lingo_parser.gd`, and tier-1 dispatch in `lingo_engine.gd` | parsed and reported; tier 1 still absent |

Items 1, 3, 4 and 5 share a shape: **a suffix that is part of a designator,
parsed as though it were a trailing modifier that could be ignored.** Fixing them
together is one change to how `_parse_the` and the reference forms handle their
tails, not four patches. All four are now designator nodes —
`sound_prop`, the movie argument, the `of castLib` tail and `window_prop` — and
`tools/lingo_designator_check.gd` holds the last three against the real spellings
extracted from the containers.

**Item 1 is closed in the parser and, since `docs/bugs-closed.md` 27, in the host
too.** `sound_prop` reaches `set_sound_prop` / `get_sound_prop`, and both hosts
now implement the pair over `AudioDirector`'s per-channel volume. The second half
of that entry is why the gap survived so long: `_host_call` answered null for a
method the host lacked, which is indistinguishable from a host that handled the
call, so 66 writes went nowhere with nothing recorded. A missing host method is
now reported as `host.<method>` under `unbound_name`, and
`tools/sound_state.gd` reproduced the old failure on demand; it drove the retired
renderer and was deleted with it, so this rule now has no harness.

Item 2 is not a parser change at all, and is the only one that needs a decision
rather than a fix.

Below that line, the highest-value non-gap work is the `and`/`or` precedence
ranking (§16.2) — zero sites here, but it is wrong, it is one table, and it will
not announce itself in the next movie. Note this is the *precedence* ranking and
not the short-circuit question, which §17 records as settled and removed.

One near-miss is worth recording because it looks like a gap and is not. A bare
command word on a line of its own — `updateStage`, `cursorfunk`, `nothing`,
`dontPassEvent`, and 44 sites of `updateStage` alone — parses to a *variable
read*, not a call, because the port has no empty-argument command form. It works
anyway: `lingo/lingo_interpreter.gd:_read_var` falls through to "an unknown bare
identifier is a parameterless handler call in Lingo" and dispatches. The
equivalence holds only while no local or global shares the name with a handler,
which is an accident of this game rather than a property of the design.

---

# 17. Corrections to the sections above

Two claims in §1–§10 are contradicted by what §11–§16 read.

- **§2.3 said `and` and `or` short-circuit. They do not.** They are single
  opcodes that pop both operands, coerce each to an integer and push `0` or `1`
  (§13). The code generator emits no jump for them (§14). Both sides of a logical
  operator are always evaluated, so a side-effecting or expensive operand runs
  regardless of the other.

  **Removed** from the interpreter rather than recorded as a deliberate
  divergence, and §2.3 above is now corrected in place. The argument for removing
  it is stronger in Lingo than the general "an operand might have a side effect":
  a bare identifier that is not a variable is a **parameterless handler call**
  (`lingo_interpreter.gd:_read_var`), so `if x and cursorfunk then` is a call the
  AST does not spell like one. A short-circuiting interpreter stops making those
  calls with nothing in the tree to say which ones, and the symptom — a cursor
  that does not change, speech that never starts — reads as a missing binding
  rather than as a conditional. `tools/lingo_logic_check.gd` asserts the right
  operand runs by giving it an observable effect; checking the *value* of
  `0 and x` proves nothing, since both implementations answer 0.
- **§1.4 says this game does not use `play done`. It does** — 48 statements in 48
  authored scripts, and 96 files in the decompiled tree. The reasoning that
  followed it ("a port that inherits that shortcut into a title which *does* use
  the play stack will return to the wrong place with no error") therefore applies
  to *this* title. See §16.3.

One claim is refined rather than corrected: §9.1 lists `when keyDown then …` as
"grammar rather than a builtin", which is right. §11.2 adds the mechanism — it is
a single lexical token whose tail is captured raw — and §16.3 names the one script
that contains it.

Three further corrections, from the audit that produced §19:

- **§9.1 said the property surface is closed. It is not.** Eleven property names
  the six titles reach are not live, seven of them by one mechanism — a sprite
  write stored in the override table that nothing merges. The claim was measured
  against one title and against a host that has been deleted, and both halves of
  that were load-bearing. Corrected in place at §9.1 and enumerated in §19.
- **§9.3's enumeration of the preview host was stale in five places** and is
  replaced by §19, which a harness holds true. It listed `puppetTransition`,
  `cursor`, `dontPassEvent` and `puppetSprite` as ignored when each has a real
  arm, and did not mention `saveMovie` at all.
- **§9.2's usage counts are Piposh 2's, and the engine runs six titles.** Its
  list group says "only `getAt` and `count` are used here"; across the six,
  **`setAt` has 2,758 sites**, `deleteAt` 134, `addAt` 18, `addProp` and `sort`
  6 each, `duplicate` 12 and `findPos` 3 — none of them in Piposh 2. Its geometry
  group calls `point` and `map` unused; they have 59 and 5. The section's
  *conclusion* is untouched, and is in fact vindicated: every one of those was
  built because Director has it, which is exactly what `AGENTS.md` asks for, and
  `setAt` alone would have been the second-biggest hole in the language surface
  if the measurement had been allowed to govern scope. Read "0 uses" anywhere in
  §9 as "0 uses in one title of six".

---

# 18. Not verified (part two)

- **ScummVM's trim-garbage flag is not always on.** §11.11 describes the error
  productions as if recovery always happens. The flag that selects between "trim
  and continue" and "abort" is set elsewhere in the engine and was not traced, so
  when a shipped movie gets recovery rather than a hard failure is unstated.
- **The `.5` lexing claim.** ScummVM's own FIXME says the parser "treats `.5` as
  `5`", but the float rule as written should match `.5` as `0.5`. The mechanism
  behind their note was not found. §11.2's remark that a lone `.` lexes as a float
  follows from rule ordering and longest-match, and was not tested.
- **Bare assignment is genuinely absent from `lingo-gr.y`.** Read off the `asgn`
  production, which has only the three `put` forms and `set`. Not cross-checked
  against a running ScummVM, and the error productions make it hard to prove by
  observation — `x = 1` would be *recovered*, not rejected.
- **Whether any of the 48 `play done` sites depends on the return.** Not tested.
  §16.3's entry states the risk, not a measured symptom.
- **The corpus in §16 is the authored source, not what the port runs.** The port
  executes ASTs compiled from `reference/lingo/`, the decompiled tree. The two
  agree on `play done` (48 statements versus 96 files) and on the existence of
  `case`, but a decompiler normalises syntax, so a shape present in one and absent
  from the other proves nothing about the other. Every statement count in §16 is
  from the extracted authored text.
- ~~**§16.3's claim that `set the volume of sound N` is dropped** was read out of
  `lingo_interpreter.gd`'s assignment path, not observed at runtime.~~ Now
  observed: `tools/sound_state.gd` (deleted with the retired renderer) ran the corpus's own two shapes through the
  real compiler, interpreter and game host and asserts the volume that lands on
  the channel, and its last case reproduces the dropped write against a host with
  the binding deliberately absent.
- **The parse survey used the Python compiler with the GDScript fixes patched
  in**, not `lingo_parser.gd` itself, because there is no tool that compiles a
  directory of `.ls` files through the GDScript path. The two are meant to agree
  script for script; if they have drifted, the survey reflects the Python.
- **The D7 keyword list in ScummVM's `docs/` includes `{`, `}` and `..`**, none of
  which appear in the grammar or the lexer. Whether they are real Lingo syntax
  somewhere, or artefacts of how that list was compiled, was not chased.

---

# 19. The claim table — what this engine actually binds

Every section above this one is prose, and prose is what let four documented
capabilities turn out not to exist. `intersects` was listed as implemented on
the strength of a host that had been deleted; `set the text of member` and `set
the editable of member` were listed while `set_member_prop` was a bare `pass`;
`saveMovie` was described as correctly inert while the game could not save at
all. Each was found by accident, after real debugging, and each was found
*despite* this document rather than through it.

So the claim itself is a table and nothing else, because a table can be read by
a machine. **`tools/lingo_surface_audit.gd` parses it** and fails if any row
disagrees with the running engine, if a name the engine binds has no row, or if
a name any of the six titles calls has no row. It is the normative statement of
this port's Lingo surface; everything above is the language it is a surface of.

    godot --headless --path . --script tools/lingo_surface_audit.gd
    godot --headless --path . --script tools/lingo_surface_audit.gd -- --survey
    godot --headless --path . --script tools/lingo_surface_audit.gd -- --name flipH

The prose between here and the table is the gap list it produces, which is the
one thing a table is bad at: an ordering with a reason attached to each place.

## How to read a row

| column | meaning |
|---|---|
| name | the Lingo spelling, lower-cased — Lingo is case-insensitive (§11.2) |
| kind | `builtin`, or the entity a property hangs off: `system` (`the X`), `sprite`, `member`, `window`, `sound` |
| state | `live`, `inert` or `absent` — see below |
| note | corpus sites across **every** root under `games/`, then where the binding lives |

**Three states, never two.** That distinction is the whole point:

- **`live`** — bound, and the effect reaches something a movie can observe.
- **`inert`** — bound, answers cleanly, counted as reached, and *does nothing*.
  This is the dangerous state and the one that hides. A name in the host's
  `IGNORED` list, an arm whose body is `return 0`, a sprite property stored in
  the override table that `sprite_state.effective` never merges, and a member
  write with no arm all look identical to a caller. `intersects` was this shape
  in the retired host's documentation; `the flipH of sprite` is this shape
  today, at 450 sites.
- **`absent`** — not bound. The honest state: the name is reported when a script
  reaches it, so a log says so. That is now true of properties as well as of
  builtins, and it was not for most of this port's life —
  `LingoDiagnostics.SPRITE_PROP`, `MOVIE_PROP` and `MEMBER_PROP` were declared
  from the day the sink was written and none of the three was ever emitted,
  which is why the property half of this table had to be built by reading the
  code rather than by running it. All three emit now, from the fall-through of
  the thing that consumes each kind rather than from a list beside it:
  `director_preview.gd:_note_sprite_prop` against `sprite_props.gd:consumed`,
  `_note_member_prop` beside it on `members.gd:read_prop`'s VOID and on
  `lingo_set_member_prop`'s `_:`, and `preview_lingo_host.gd:_note_movie_prop`
  on both ends of `get_system_prop` / `set_system_prop`.
  `tools/property_surface.gd` is the harness that keeps them honest.

A fourth value, **`noop`**, may be *recorded* and cannot be *observed*: it reads
as `inert` to the harness and means that Director's own semantics for the name
are "nothing a movie can see happens here". `nothing`, `printFrom`, the
`preLoad`/`unLoad` memory hints, `restart`, `shutDown`, `showGlobals`,
`showLocals` and the window's `picture` are the whole of it, and each carries its
reason in its note. It is a suppression channel and it is meant to be an
uncomfortable one — per name, written here rather than in the harness, and
excluded from the reachable-gap count below. Anything whose absence a player
could notice is `inert` and is a gap: `beep`, `alert`, `quit`, `continue` and
`updateStage` were all bound to nothing and all of them were in the list. All
five are live now, and `updateStage` is the one worth keeping the sentence for:
it sat inert at 3,717 sites — the largest reachable gap this document ever
recorded — behind a note that said the platform could not do it.

A row absent from this table is a Director name no title reaches and this engine
does not bind; §9.2 is where that remainder is described. Adding a binding means
adding its row, and the harness enforces it.

## Counting

Counts are call and property sites in the **authored** Lingo held in the `CASt`
records of every container under every root in `games/`, not in
`reference/lingo/`. Two reasons, and the second is the one that bites: that tree
is Piposh 2 alone, where the engine runs six titles, and it is ProjectorRays'
decompilation, which renders bare `pass` as `pass()` and `dontPassEvent` as
`dont(pass)` — so a token grep for either answers 0 where the real count is 6.
Where a count here disagrees with one quoted elsewhere in this document, this
one is the authored source and the other is the decompiled tree.

The three language builds of Piposh 1 (`piposh`, `piposh-en`, `piposh-ru`) ship
near-identical scripts, so a name only they use is counted about three times.
That inflates a rank and never invents one.

## What is still open, in the order a movie meets it

> **Reachable gaps recorded here: 0.** `tools/lingo_surface_audit.gd` counts the
> rows that are not `live` and that at least one of the six titles calls, and
> fails if the number moves. It can only move two ways and both deserve a red
> gate: a gap closed and this number not brought down with it, or a name some
> title calls newly bound to something that does nothing.

`noop` rows are excluded from that count and only those: `nothing`, `printFrom`,
the `unLoad` memory hints, `restart`, `shutDown`, `showGlobals`, `showLocals` and
the window's `picture`. Everything else that answers without doing anything is a
gap, including the ones that look harmless.

The `preLoad` family used to sit in that list and does not any more. A memory
hint looks like the safest thing in Lingo to leave unbound, and this one is not:
each of the four reports what it managed to load through `the result`, so a movie
can ask afterwards and get an answer. `noop` is a claim that nothing observable
happens, and that claim was false.

| sites | name | state | what a movie sees, and where the fix goes |
|---|---|---|---|
| 3,717 | `updateStage` | **live** | Director redraws *now*, mid-handler, and every `repeat` loop that animates by moving a sprite and calling this depended on it; inert, the loop drew once when it ended and the sprite teleported. `director_preview.gd:repaint_now()` clears the node's canvas item, runs the same `_paint` the frame loop runs, and presents with `RenderingServer.force_draw()`. What made that possible was moving the player's painting off `CanvasItem.draw_*` — which asserts `drawing`, raised only inside `NOTIFICATION_DRAW` — and onto `director/director_paint.gd`, which issues the same commands through `RenderingServer` and may be called from anywhere. **The note this replaces was half right and stopped there**: `queue_redraw()` followed by `force_draw()` really does leave `_draw` unrun, because the redraw callback sits on the message queue and GDScript cannot flush it — but `force_draw` presents the commands a canvas item *already holds*, so the answer was to write the commands rather than to wait for a notification. Both halves are re-measured every run by `tools/lingo_system_builtins.gd`; the behaviour is `tools/update_stage.gd`, which asserts that a handler leaves the *paint* remembering the member it set before the call while the channel reads the one it set after. It also spends a pending `puppetTransition` and re-resolves the cursor, which are the other two things `lingo-builtins.cpp:b_updateStage` does. |
| 1,453 | `the member of sprite N` | **live** | Piposh Dream reads it (`member(the member of sprite xxx).name`). Aliased to `membernum` in `sprite_props.gd`: Director's member *reference* and its integer are two properties, and one here, because this port packs `(library, slot)` into a single integer `member()` accepts either way (§1.6). Wrong only for a title that compares a member reference against something that is not an integer. |
| 450 | `the flipH of sprite N` | **live** | Piposh Dream's `fritz1.dir` both reads and writes it (`sprite(getAt(ppl, 1)).flipH = 1`). Aliased to the record's `flip_h`, answered from the score's own bit by `read_prop` and merged by `effective`; `sprite_art.gd` has drawn from that name since before the bit was decoded and mirrors the hit test with it, so a flipped sprite is clickable where it is drawn. `the flipV` (6 sites) is the same entry. |
| 361 | `the loc of sprite N` | **live** | Same file swaps two sprites' positions with it. Split in `director_preview.gd`'s two entry points rather than aliased: the read composes `locH`/`locV` into the two-element list this port represents a point with, and the write splits one back onto `_write_position`, so the constraint stays applied in exactly one place (§7.6). **`tools/lingo_surface_audit.gd` still counts this row as a gap** -- it reads bindings out of the host and the property tables and cannot see a name the node routes before either -- so the count above is one higher than the truth until the audit learns to look there. |
| 39 | `the hilite of member M` | absent | Rating, `set the hilite of member "rectang" to 1`, once per room. `lingo_set_member_prop` knows `editable` and `text` and drops everything else **without reporting it**, which is the `set_member_prop` shape again in a narrower place. |
| 20 | `the rect of sprite N` | inert | Readable in Director and derived from loc, registration point and member size. |
| 12 | `the currentSpriteNum` | **live** | Piposh Dream's hex board reads it to know which channel is running the behaviour, once per tile across `hex1`/`hex2`/`hex3`. §7.1 says it is synthesised rather than stored, and it is: the host carries `current_sprite_num`, `preview/event_chain.gd` sets it around the one element of the five that is a sprite behaviour and puts back what it found, and `sendSprite`/`sendAllSprites` bracket their sends the same way so a broadcasting behaviour reads its own channel again on the way back. A cast script, a frame script and a movie script all read 0 during the same click, which is Director's answer and the reason the value is per element rather than per chain. |
| 6 | `the flipV of sprite N` | inert | As `flipH`. |
| 4 | `xtra` | **live** | Xtra reference by name or by 1-based index, resolved against the same registry `the xtras` reads — so the two cannot disagree about what this player has loaded — with §7.3's name normalisation applied to both sides. **The registry holds two Xtras, FileIO and BudAPI** (`lingo/lingo_fileio.gd`, `lingo/lingo_buddyapi.gd`), and a name that is not in it is still *reported by name* instead of vanishing, the way an unbound builtin is. Both are there because they are the Xtras titles are *blocked on* rather than merely missing: two movies pointed at this engine stop at startup without FileIO, both while reading a configuration file, and a third parks on frame 0 without BuddyAPI's `baReadIni` (`bugs.md` 78). The two have different shapes and §19's rows say so -- FileIO is reached through an instance, while every `ba*` name is a global builtin and the registry entry exists only so that `the xtras` and `xtra("BudAPI")` agree with the player about what is loaded. `new(xtra("FileIO"))` answers an instance, `openFile(f, path, 1)` and `f.openFile(path, 1)` are one statement, and `status(f)` reports Director's own Mac OS codes — a script branches on `status(f) = 0`, so a plausible wrong code would be worse than no binding. Writes are refused in a headless run without `--allow-writes` and outside the game root always. The corpus's only two sites are `xtra(#net, 2, type & "thud.aif")` in Piposh Dream's `ratA.dir`, inside a handler called `__` that nothing calls: three arguments, which is an arity error in Director too, and is now reported as one. |
| 4 | `the top of sprite N` | inert | With `left`, `right` and `bottom`: read-only in Director and *derived*, which is why §4 leaves them out of the writable set. Answering 0 is a wrong answer, not a missing one. |
| 3 | `the textSize of member M` | absent | A member write with no arm, as `hilite`. |
| 3 | `the castLibNum of sprite N` | inert | The library half of `the member of sprite`. |
| 2 | `the volume of sprite N` | **live** | Piposh 2's `arcade1.dir` writes it twice, `sprite(2).volume = 255` on the way out of the arcade. The sprite spelling of a **digital-video** property, and it closed with the rest of that surface: `scenes/preview/media.gd` owns a playhead per channel — rate, in and out points, volume, cue index — and the fourteen sprite names route to it from `preview_lingo_host.gd:get_sprite_prop` rather than into the channel record, because Director applies none of the score's auto-puppet release rules (§5.3) to a playhead. The value round-trips and is clamped to Director's 0-255. **Nothing plays**: there is no QuickTime or AVI decoder here, so `the mediaReady of member` is FALSE for a `#digitalVideo` and the playhead has no media to move — which is what Director answers for a video whose file is missing, and `media.gd`'s header is the full account. `the volume of sound N` is a different property and was already live. |

Two shapes account for most of that list, and neither is a missing name:

- **A sprite property write is stored and never consumed.** `sprite_state.write_prop`
  puts *any* key in the override table, so every write round-trips through
  `read_prop` and looks implemented, while only the keys `sprite_state.effective`
  merges reach the screen. `the moveableSprite of sprite`, `the editableText of
  sprite` and `the constraint of sprite` were each exactly this and were each
  found the hard way; `flipH`, `flipV`, `loc`, `rect`, `member` and `castLibNum`
  were the same thing when this paragraph was written, and `ink` is it with 0
  sites. `the volume of sprite` is off the list: it was never a *drawn sprite*
  property at all, and the fix was not another merge row but a second owner --
  `preview/media.gd` holds the digital-video playhead, which the score's release
  rules must not touch.
- **A property with no binding was not reported.** This is the shape that made
  the one above so expensive, and it is closed. `LingoDiagnostics` declared
  `SPRITE_PROP`, `MOVIE_PROP` and `MEMBER_PROP` and emitted none of the three:
  `_host_call` reports a missing host *method* -- which is what closed `set the
  volume of sound N` (§16.4) -- while a bound method answering VOID for a name it
  does not know is indistinguishable from one that had nothing to say. So the
  property surface had no `unbound` tally at all, and this table had to be built
  by reading the code rather than by running the game and counting complaints.

  All three emit now, and each reports from the **fall-through of the code that
  consumes that kind** rather than from a list kept beside it, because a list and
  the code drift and that drift is how `ink` and `blend` came to be excused by
  name. The member read half was the last and the best hidden: `members.gd`
  answered **0** for every property it had no arm for, so `the frameRate of
  member N` and `the width of member N` came back as two integers a script cannot
  tell apart -- the same "a wrong answer, not a missing one" this list already
  says about `the top of sprite`, over fifty names and with nothing recording it.
  It answers VOID internally now and `director_preview.gd` reports it and hands
  the caller the same 0 as before, so no movie's behaviour moves.

  `tools/property_surface.gd` is what stops this rotting: it drives a name this
  engine does not bind through all three categories and fails if any stays quiet,
  drives eleven names it *does* bind and fails if any of those reports, and
  derives from the sources that every write arm reaches a store something outside
  the setter reads. The last of those is the one with teeth -- the audit beside it
  scores any arm containing an `=` as live, so a property bound to a field nobody
  reads is exactly what it cannot see.

## The table

| name | kind | state | corpus sites; where the binding lives |
|---|---|---|---|
| `sound` | builtin | live | 58490 sites; host arm |
| `go` | builtin | live | 32158 sites; host arm |
| `visible` | sprite | live | 12548 sites; merged by effective() |
| `locv` | sprite | live | 11239 sites; merged by effective() |
| `put` | builtin | live | 9363 sites; grammar: a parser keyword (§11.3), never dispatched |
| `sprite` | builtin | live | 9015 sites; grammar: a parser keyword (§11.3), never dispatched |
| `loch` | sprite | live | 6952 sites; merged by effective() |
| `membernum` | sprite | live | 6260 sites; merged by effective() |
| `puppetsprite` | builtin | live | 5328 sites; host arm |
| `play` | builtin | live | 5286 sites; host arm |
| `getat` | builtin | live | 5071 sites; lingo_builtins.gd |
| `number` | member | live | 4702 sites; members.gd read_prop |
| `member` | builtin | live | 4015 sites; grammar: a parser keyword (§11.3), never dispatched |
| `value` | builtin | live | 3948 sites; lingo_builtins.gd |
| `updatestage` | builtin | live | 3717 sites; host arm -> `director_preview.gd:lingo_update_stage` |
| `membernum` | member | live | 2992 sites; members.gd read_prop |
| `cursor` | sprite | live | 2910 sites; merged by effective() |
| `marker` | builtin | live | 2845 sites; host arm |
| `setat` | builtin | live | 2758 sites; lingo_builtins.gd |
| `rollover` | builtin | live | 2444 sites; host arm |
| `soundbusy` | builtin | live | 2080 sites; host arm |
| `member` | sprite | live | 1453 sites; aliased to `membernum` in sprite_props.gd |
| `random` | builtin | live | 1378 sites; lingo_builtins.gd |
| `text` | member | live | 1322 sites; members.gd read_prop |
| `keycode` | system | live | 1172 sites; read only |
| `clickon` | system | live | 1006 sites; read only |
| `name` | member | live | 756 sites; members.gd read_prop |
| `keydownscript` | system | live | 747 sites; read+write |
| `moviepath` | system | live | 746 sites; read only |
| `field` | builtin | live | 682 sites; grammar: a parser keyword (§11.3), never dispatched |
| `label` | builtin | live | 516 sites; host arm |
| `mouseh` | system | live | 486 sites; read only |
| `mousedownscript` | system | live | 477 sites; read+write |
| `fliph` | sprite | live | 450 sites; aliased to the record's `flip_h`, merged by effective, drawn and hit-tested by sprite_art.gd |
| `flip_h` | sprite | live | 0 sites; not a Director name -- the score record's own spelling, which `read_prop` and `effective` key on and `fliph` aliases to. Recorded because the engine binds it and this table is what the engine is audited against. |
| `flip_v` | sprite | live | 0 sites; the vertical half of the row above. |
| `forget` | builtin | live | 389 sites; host arm |
| `nothing` | builtin | noop | 376 sites; host IGNORED; Director's own explicit no-op; there is nothing to do |
| `loc` | sprite | live | 361 sites; stored in _overrides, consumed by nothing |
| `searchpath` | system | live | 326 sites; read+write |
| `constraint` | sprite | live | 316 sites; merged by effective() |
| `volume` | sound | live | 314 sites; read and write |
| `frame` | system | live | 302 sites; read only; **1-based**, like every frame number Lingo names -- `go N`, `play frame N`, `label()` and `marker()` are the same space, and the runtime's own 0-based index is behind `director_preview.lingo_frame_index`/`lingo_frame_number` |
| `mousev` | system | live | 300 sites; read only |
| `count` | builtin | live | 275 sites; lingo_builtins.gd |
| `dontpassevent` | builtin | live | 262 sites; host arm |
| `stage` | system | live | 253 sites; read only |
| `window` | builtin | live | 205 sites; host arm |
| `keyupscript` | system | live | 205 sites; read+write |
| `return` | builtin | live | 195 sites; lingo_builtins.gd |
| `pass` | builtin | live | 174 sites; host arm |
| `beep` | builtin | live | 154 sites; host arm |
| `continue` | builtin | live | 150 sites; host arm |
| `pause` | builtin | live | 146 sites; host arm |
| `abs` | builtin | live | 138 sites; lingo_builtins.gd |
| `deleteat` | builtin | live | 134 sites; lingo_builtins.gd |
| `open` | builtin | live | 133 sites; host arm |
| `castnum` | sprite | live | 123 sites; merged by effective() |
| `machinetype` | system | live | 123 sites; read only |
| `quit` | builtin | live | 102 sites; host arm |
| `moviename` | system | live | 94 sites; read only |
| `timer` | system | live | 91 sites; read+write |
| `soundlevel` | system | live | 70 sites; read+write |
| `point` | builtin | live | 59 sites; lingo_builtins.gd |
| `editable` | member | live | 58 sites; director_preview.gd, read and write |
| `printfrom` | builtin | noop | 56 sites; host IGNORED; printing; no printer, and §9.1 already calls this correctly inert |
| `centerstage` | system | live | 55 sites; read+write |
| `windowtype` | window | live | 54 sites; windows.gd read+write |
| `movie` | system | live | 41 sites; read only |
| `hilite` | member | live | 39 sites |
| `mousedown` | system | live | 39 sites; read only |
| `moveablesprite` | sprite | live | 33 sites; merged by effective() as `moveable` |
| `intersects` | builtin | live | 23 sites; host arm |
| `trackcount` | builtin | live | 0 sites; host arm -> media.gd; 0, a video's track table is in a file nothing here can open |
| `tracktype` | builtin | live | 0 sites; host arm -> media.gd; VOID for a track that does not exist |
| `trackstarttime` | builtin | live | 0 sites; host arm -> media.gd |
| `trackstoptime` | builtin | live | 0 sites; host arm -> media.gd |
| `ispastcuepoint` | builtin | live | 0 sites; host arm -> media.gd; computed from the playhead against the decoded cue table |
| `rect` | sprite | live | 20 sites; stored in _overrides, consumed by nothing |
| `key` | system | live | 20 sites; read only |
| `addat` | builtin | live | 18 sites; lingo_builtins.gd |
| `unload` | builtin | noop | 16 sites; host IGNORED; memory hint (§1.4), inverse |
| `duplicate` | builtin | live | 12 sites; lingo_builtins.gd |
| `within` | builtin | live | 12 sites; host arm |
| `puppet` | sprite | live | 12 sites; routed on the node to `lingo_puppet_sprite`, the same flag `puppetSprite` sets. It was **not** merged by effective() and this row said it was: the flag is `channel.gd:PUPPET_KEY`, the string `_puppet`, so the property spelling stored `puppet` in the override entry and reached nothing in either direction — `puppetSprite N, TRUE` then `the puppet of sprite N` answered 0, and `set the puppet of sprite N to 1` answered 1 with the channel unfrozen. Found by `tools/property_surface.gd` driving Director's own name list through the engine; the audit had it in a hand-written consumed list, which is what kept it quiet. |
| `currentspritenum` | system | live | 12 sites; read only |
| `savemovie` | builtin | live | 11 sites; host arm |
| `editabletext` | sprite | live | 11 sites; merged by effective() as `editable` |
| `addprop` | builtin | live | 6 sites; lingo_builtins.gd |
| `sort` | builtin | live | 6 sites; lingo_builtins.gd |
| `flipv` | sprite | live | 6 sites; aliased to the record's `flip_v`, merged by effective, drawn and hit-tested by sprite_art.gd |
| `integer` | builtin | live | 5 sites; lingo_builtins.gd |
| `map` | builtin | live | 5 sites; lingo_builtins.gd |
| `exitlock` | system | live | 5 sites; read+write |
| `xtra` | builtin | live | 4 sites; host arm |
| `top` | sprite | live | 4 sites; stored in _overrides, consumed by nothing |
| `findpos` | builtin | live | 3 sites; lingo_builtins.gd |
| `textsize` | member | live | 3 sites |
| `castlibnum` | sprite | live | 3 sites; read arm |
| `alert` | builtin | live | 2 sites; host arm |
| `stopevent` | builtin | live | 2 sites; host arm |
| `unloadmovie` | builtin | noop | 2 sites; host IGNORED; memory hint (§1.4), inverse |
| `volume` | sprite | live | 2 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `freeblock` | system | live | 2 sites; read only |
| `abort` | builtin | live | 0 sites; host IGNORED |
| `add` | builtin | live | 0 sites; lingo_builtins.gd |
| `append` | builtin | live | 0 sites; lingo_builtins.gd |
| `atan` | builtin | live | 0 sites; lingo_builtins.gd |
| `backspace` | builtin | live | 0 sites; lingo_builtins.gd |
| `castlib` | builtin | live | 0 sites; grammar: a parser keyword (§11.3), never dispatched |
| `chars` | builtin | live | 0 sites; lingo_builtins.gd |
| `chartonum` | builtin | live | 0 sites; lingo_builtins.gd |
| `clearglobals` | builtin | live | 0 sites; host IGNORED |
| `close` | builtin | live | 0 sites; host arm |
| `cos` | builtin | live | 0 sites; lingo_builtins.gd |
| `cursor` | builtin | live | 0 sites; host arm |
| `delay` | builtin | live | 0 sites; host arm |
| `deleteone` | builtin | live | 0 sites; lingo_builtins.gd |
| `deleteprop` | builtin | live | 0 sites; lingo_builtins.gd |
| `empty` | builtin | live | 0 sites; lingo_builtins.gd |
| `enter` | builtin | live | 0 sites; lingo_builtins.gd |
| `exp` | builtin | live | 0 sites; lingo_builtins.gd |
| `false` | builtin | live | 0 sites; lingo_builtins.gd |
| `findposnear` | builtin | live | 0 sites; lingo_builtins.gd |
| `float` | builtin | live | 0 sites; lingo_builtins.gd |
| `floatp` | builtin | live | 0 sites; lingo_builtins.gd |
| `framestohms` | builtin | live | 0 sites; lingo_builtins.gd |
| `getaprop` | builtin | live | 0 sites; lingo_builtins.gd |
| `getlast` | builtin | live | 0 sites; lingo_builtins.gd |
| `getone` | builtin | live | 0 sites; lingo_builtins.gd |
| `getpos` | builtin | live | 0 sites; lingo_builtins.gd |
| `getprop` | builtin | live | 0 sites; lingo_builtins.gd |
| `getpropat` | builtin | live | 0 sites; lingo_builtins.gd |
| `halt` | builtin | live | 0 sites; host arm |
| `hmstoframes` | builtin | live | 0 sites; lingo_builtins.gd |
| `ilk` | builtin | live | 0 sites; lingo_builtins.gd |
| `inflate` | builtin | live | 0 sites; lingo_builtins.gd |
| `inside` | builtin | live | 0 sites; lingo_builtins.gd |
| `installmenu` | builtin | inert | 0 sites; host IGNORED |
| `integerp` | builtin | live | 0 sites; lingo_builtins.gd |
| `intersect` | builtin | live | 0 sites; lingo_builtins.gd |
| `length` | builtin | live | 0 sites; lingo_builtins.gd |
| `list` | builtin | live | 0 sites; lingo_builtins.gd |
| `listp` | builtin | live | 0 sites; lingo_builtins.gd |
| `log` | builtin | live | 0 sites; lingo_builtins.gd |
| `max` | builtin | live | 0 sites; lingo_builtins.gd |
| `min` | builtin | live | 0 sites; lingo_builtins.gd |
| `numberofchars` | builtin | live | 0 sites; lingo_builtins.gd |
| `numberofitems` | builtin | live | 0 sites; lingo_builtins.gd |
| `numberoflines` | builtin | live | 0 sites; lingo_builtins.gd |
| `numberofwords` | builtin | live | 0 sites; lingo_builtins.gd |
| `numtochar` | builtin | live | 0 sites; lingo_builtins.gd |
| `objectp` | builtin | live | 0 sites; lingo_builtins.gd |
| `offset` | builtin | live | 0 sites; lingo_builtins.gd |
| `pi` | builtin | live | 0 sites; lingo_builtins.gd |
| `picturep` | builtin | live | 0 sites; lingo_builtins.gd |
| `power` | builtin | live | 0 sites; lingo_builtins.gd |
| `preload` | builtin | live | 0 sites; host IGNORED; memory hint (§1.4); nothing a movie can observe |
| `preloadcast` | builtin | live | 0 sites; host IGNORED; memory hint (§1.4) |
| `preloadmember` | builtin | live | 0 sites; host IGNORED; memory hint (§1.4) |
| `preloadmovie` | builtin | live | 0 sites; host IGNORED; memory hint (§1.4) |
| `puppetpalette` | builtin | live | 0 sites; host arm |
| `puppetsound` | builtin | live | 0 sites; host arm |
| `puppettempo` | builtin | live | 0 sites; host arm -> `director_frame_clock.gd:set_puppet_tempo`; §9.1's precedence and release condition |
| `puppettransition` | builtin | live | 0 sites; host arm |
| `quote` | builtin | live | 0 sites; lingo_builtins.gd |
| `rect` | builtin | live | 0 sites; lingo_builtins.gd |
| `restart` | builtin | noop | 0 sites; host IGNORED; restarts the machine; §1.4 calls it inert everywhere sane |
| `setaprop` | builtin | live | 0 sites; lingo_builtins.gd |
| `setcallback` | builtin | inert | 0 sites; host IGNORED |
| `setprop` | builtin | live | 0 sites; lingo_builtins.gd |
| `showglobals` | builtin | noop | 0 sites; host IGNORED; dumps to the message window, which does not exist here |
| `showlocals` | builtin | noop | 0 sites; host IGNORED; dumps to the message window, which does not exist here |
| `shutdown` | builtin | noop | 0 sites; host IGNORED; shuts the machine down; likewise |
| `sin` | builtin | live | 0 sites; lingo_builtins.gd |
| `sqrt` | builtin | live | 0 sites; lingo_builtins.gd |
| `starttimer` | builtin | live | 0 sites; host arm |
| `string` | builtin | live | 0 sites; lingo_builtins.gd |
| `stringp` | builtin | live | 0 sites; lingo_builtins.gd |
| `symbolp` | builtin | live | 0 sites; lingo_builtins.gd |
| `tab` | builtin | live | 0 sites; lingo_builtins.gd |
| `tan` | builtin | live | 0 sites; lingo_builtins.gd |
| `true` | builtin | live | 0 sites; lingo_builtins.gd |
| `union` | builtin | live | 0 sites; lingo_builtins.gd |
| `unloadcast` | builtin | inert | 0 sites; host IGNORED; memory hint (§1.4), inverse |
| `unloadmember` | builtin | inert | 0 sites; host IGNORED; memory hint (§1.4), inverse |
| `void` | builtin | live | 0 sites; lingo_builtins.gd |
| `voidp` | builtin | live | 0 sites; lingo_builtins.gd |
| `castnum` | member | live | 0 sites; members.gd read_prop |
| `height` | member | live | 0 sites; members.gd read_prop |
| `width` | member | live | 0 sites; members.gd read_prop |
| `cuepointnames` | sound | live | 0 sites; sound.gd read |
| `loop` | sound | inert | 0 sites; sound.gd read  (no effect) |
| `looping` | sound | inert | 0 sites; sound.gd read  (no effect) |
| `backcolor` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `blend` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `bottom` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `currenttime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `editable` | sprite | live | 0 sites; merged by effective() |
| `forecolor` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `height` | sprite | live | 0 sites; merged by effective() |
| `immediate` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `ink` | sprite | live | 0 sites; read from the score record; a write reaches nothing |
| `left` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `linesize` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `mostrecentcuepoint` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `moveable` | sprite | live | 0 sites; merged by effective() |
| `movierate` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `movietime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `name` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `pattern` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `right` | sprite | live | 0 sites; stored in _overrides, consumed by nothing |
| `scorecolor` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `scriptinstancelist` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `scriptnum` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `settrackenabled` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `starttime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `stoptime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `stretch` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `trackenabled` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `tracknextkeytime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `tracknextsampletime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `trackpreviouskeytime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `trackprevioussampletime` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `tracktext` | sprite | live | 0 sites; preview_lingo_host.gd -> media.gd, the playhead |
| `trails` | sprite | live | 0 sites; merged by effective() |
| `tweened` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `type` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `visibility` | sprite | inert | 0 sites; stored in _overrides, consumed by nothing |
| `width` | sprite | live | 0 sites; merged by effective() |
| `activewindow` | system | live | 0 sites; read only |
| `clickloc` | system | live | 0 sites; read only |
| `commanddown` | system | live | 0 sites; read only |
| `controldown` | system | live | 0 sites; read only |
| `doubleclick` | system | live | 0 sites; read only |
| `drawrect` | system | live | 0 sites; read+write |
| `filename` | system | live | 0 sites; write only |
| `frontwindow` | system | live | 0 sites; read only |
| `lastclick` | system | live | 0 sites; read only |
| `lastevent` | system | live | 0 sites; read only |
| `lastroll` | system | live | 0 sites; read only |
| `milliseconds` | system | live | 0 sites; read only |
| `modal` | system | live | 0 sites; read+write |
| `mousecast` | system | live | 0 sites; read only |
| `mouseloc` | system | live | 0 sites; read only; the pair form of `the mouseH`/`the mouseV`, bound by `4b2e9371`. 0 sites is a fact about these six corpora and not about the name: `test-games/itamar-park` drives its software cursor with `set the loc of sprite CursorCh to the mouseLoc` from `on idle`, and that corpus is not one this audit scans |
| `mousemember` | system | live | 0 sites; read only |
| `mouseup` | system | live | 0 sites; read only |
| `mouseupscript` | system | live | 0 sites; read+write |
| `optiondown` | system | live | 0 sites; read only |
| `rect` | system | live | 0 sites; read+write |
| `rightmousedown` | system | live | 0 sites; read only |
| `rightmouseup` | system | live | 0 sites; read only |
| `selend` | system | live | 0 sites; read+write |
| `selstart` | system | live | 0 sites; read+write |
| `shiftdown` | system | live | 0 sites; read only |
| `sourcerect` | system | live | 0 sites; read only |
| `stilldown` | system | live | 0 sites; read only |
| `ticks` | system | live | 0 sites; read only |
| `timeoutkeydown` | system | live | 0 sites; read+write; §8.3's "a key event refreshes the timeout clock", and **it now does**: `director_preview.gd:_dispatch_key` stamps the clock when this is true, where `events.cpp:371` stamps `_lastTimeOut`. The paragraph this replaces said nothing consumed it, which was true while there was no clock. Default **true**, which is Director's (`movie.cpp:92`) and not the false it carried while it was a store. |
| `title` | system | live | 0 sites; read+write |
| `titlevisible` | system | live | 0 sites; read+write |
| `windowlist` | system | live | 0 sites; read only |
| `windowtype` | system | live | 0 sites; read+write |
| `cast` | builtin | live | host arm |
| `constrainh` | builtin | live | host arm |
| `constrainv` | builtin | live | host arm |
| `getnthfilenameinfolder` | builtin | live | host arm |
| `setpref` | builtin | live | host arm |
| `windowpresent` | builtin | live | host arm |
| `abbr date` | system | live | host arm |
| `abbr time` | system | live | host arm |
| `abbrev date` | system | live | host arm |
| `abbrev time` | system | live | host arm |
| `abbreviated date` | system | live | host arm |
| `abbreviated time` | system | live | host arm |
| `applicationpath` | system | live | host arm |
| `beepon` | system | live | host arm |
| `colordepth` | system | live | host arm |
| `colorqd` | system | live | host arm |
| `date` | system | live | host arm |
| `floatprecision` | system | live | host arm |
| `freebytes` | system | live | host arm |
| `lastkey` | system | live | host arm |
| `long date` | system | live | host arm |
| `long time` | system | live | host arm |
| `maxinteger` | system | live | host arm |
| `memorysize` | system | live | host arm |
| `multisound` | system | live | host arm |
| `pathname` | system | live | host arm |
| `pausestate` | system | live | host arm |
| `pi` | system | live | host arm |
| `platform` | system | live | host arm |
| `randomseed` | system | live | host arm |
| `runmode` | system | live | host arm |
| `searchpaths` | system | live | host arm |
| `short date` | system | live | host arm |
| `short time` | system | live | host arm |
| `soundenabled` | system | live | host arm |
| `stagebottom` | system | live | host arm |
| `stageleft` | system | live | host arm |
| `stageright` | system | live | host arm |
| `stagetop` | system | live | host arm |
| `time` | system | live | host arm |
| `new` | builtin | live | 6 sites; lingo_interpreter.gd, before the module and the host; §7.1. Builds a script object and runs its `new` handler with `me` as the first argument; the expression is what that handler *returned*, which is `me` by convention and may deliberately be something else. Resolved ahead of user handlers, alone among the builtins: every parent script declares `on new`, and `ancestor = new(script "base")` inside it would otherwise be unbounded recursion. |
| `script` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. A packed member reference, like `member()`'s, so `the scriptText of script "x"` works on it; `new` turns one into an object through `preview_lingo_host.gd:script_at`. The designator spelling `script "Parent"` is a parser arm rather than a command call, because the command form's argument loop crosses commas and `new(script "base", who)` would hand the constructor's arguments to the designator. |
| `call` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. `call(#msg, objectOrList, args...)`, with `me` in front of the arguments. A **list** is Director's broadcast form and every object in it that answers runs; the value is the last one's, and an object that does not answer is skipped in silence, which is the reference's own `if (sym.type == VOIDSYM)`. |
| `send` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; D4's undocumented spelling of `call`. The reference maps both names onto one body (`lingo-builtins.cpp:126,149`) and so does this. |
| `callancestor` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. Enters the chain at the object's **ancestor**, skipping the object's own handler, and `me` inside it is the ancestor. **The reference stubs this** (`b_callAncestor` prints and drops the stack), so what is built is Director's documented meaning of the name rather than a copy of an implementation. |
| `sendancestor` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; D4's spelling of `callAncestor`, one body as above. |
| `timeoutlength` | system | live | 0 sites; read+write; §3. Ticks of no player activity before `timeOut` is raised; 10800 (three minutes) by default, which is `movie.cpp:90`. **0 or less disables the clock** -- not in the reference's arithmetic, and necessary here because otherwise the default would fire on every tick of every movie. |
| `timeoutlapsed` | system | live | 0 sites; read+write; §3. Ticks since the clock was last reset. **Writable**, against the D3.1 manual and with the reference: `lingo-the.cpp:1496` records that D2 and D3 Mac allow it and that a shipped title relies on it. Writing moves the origin, so `set the timeoutLapsed to 0` restarts the clock. |
| `timeoutmouse` | system | live | 0 sites; read+write; §3. Whether a mouse press resets the clock; true by default. Stamped at the press for both buttons, where `events.cpp:270` stamps it -- a release and a move do not count. |
| `timeoutplay` | system | live | 0 sites; read+write; §3. Whether `play` resets the clock; false by default. **The reference stores this and never reads it**, so the consumer is built from Director's documented meaning and is unverified against Director running. |
| `timeoutscript` | system | live | 0 sites; read+write; §6.3 tier 1. The fifth member of the `*Script` family and the same mechanism exactly -- a string of Lingo compiled in the setter, run as the primary handler for `timeOut` before the frame and movie scripts see it. The reference's write arm is `movie->setPrimaryEventHandler(kEventTimeout, ...)`, which is the call the other four make. |
| `actorlist` | system | live | 0 sites; read+write; §6.1. The objects sent `stepFrame` once per frame, in list order, after `the perFrameHook` (`scenes/preview/actors.gd`). The **live** Array is handed back rather than a copy, because `append(the actorList, x)` is how a title adds to it and a copy makes that idiom silently do nothing. Not saved in a session record: an object has no JSON form. |
| `perframehook` | system | live | 0 sites; read+write; §6.1. One object, sent `stepFrame` at the point `score.cpp:731-770` calls `executePerFrameHook` -- after the playhead moves, before `prepareFrame`, and skipped on a frame carrying a transition, which the reference hangs on the transition's subframes instead. VOID until a movie installs one, which is why `tools/lingo_surface_audit.gd` now asks whether the host *reported* rather than whether it answered VOID. |
| `updatelock` | system | live | 0 sites; read+write; §3. TRUE suppresses the stage repaint -- both `updateStage`'s (`director_preview.gd:repaint_now`) and the frame loop's (`stage_redraw`). The reference declares `kTheUpdateLock` and implements neither half, so this is the property's documented meaning: the paint is **skipped, not queued**, so clearing the lock does not replay what was missed. The engine's own repaints -- a resize, a debug overlay, a palette change -- still happen, because Director's lock is over the movie's updates. |
| `picture` | system | live | 0 sites; read only; §14. The **movie's own window** asked about itself, on the same `get_system_prop` arm as `the centerStage`, `the windowType` and six others -- inside `tell window("x")` that is the window, which is where the corpus's 21 `set the centerStage` sites mean it. Like its window twin two rows down it answers **VOID**: this renderer holds no surface to read back, and a wrong image would be worse than nothing. It reported `absent` until `tools/lingo_surface_audit.gd` stopped reading a VOID answer as a fall-through and started asking whether the host *reported* -- the same mistake `getPref` earned, in the other direction. |
| `filename` | cast | live | 4 sites; cast_libs.gd read; §5.1. The path the movie *names* for an external cast, not the one this port resolved it to: a title comparing it against a string it built itself is comparing against the authored spelling. "" for the internal cast, which is Director's answer. Read-only, as all three of these are. |
| `name` | cast | live | 1 sites; cast_libs.gd read; §5.1. The library's name from the movie's `MCsL`. |
| `number` | cast | live | 0 sites; cast_libs.gd read; §5.1. The reverse lookup, a name to a library number, asked through `members.gd:library_named` rather than re-derived -- or the two would disagree about a library genuinely called "2". **-1** for a name that matches nothing, which is the reference's answer and is not 0, because 0 would be indistinguishable from a library-1 answer. |
| `centerstage` | window | live | 0 sites; windows.gd read+write |
| `drawrect` | window | live | 0 sites; windows.gd read+write |
| `filename` | window | live | 0 sites; windows.gd read+write |
| `modal` | window | live | 0 sites; windows.gd read+write |
| `moviename` | window | live | 0 sites; windows.gd read |
| `name` | window | live | 0 sites; windows.gd read+write |
| `picture` | window | inert | 0 sites; windows.gd read  (no effect); deliberately unimplemented: this renderer holds no surface to read back, and VOID is the honest answer rather than a wrong image |
| `rect` | window | live | 0 sites; windows.gd read+write |
| `sourcerect` | window | live | 0 sites; windows.gd read |
| `title` | window | live | 0 sites; windows.gd read+write |
| `titlevisible` | window | live | 0 sites; windows.gd read+write |
| `visible` | window | live | 0 sites; windows.gd read+write |
| `do` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host |
| `editabletext` | builtin | live | 0 sites; host arm |
| `externalparamcount` | builtin | live | 0 sites; host arm |
| `externalparamname` | builtin | live | 0 sites; host arm |
| `externalparamvalue` | builtin | live | 0 sites; host arm |
| `frameready` | builtin | live | 0 sites; host arm |
| `getpref` | builtin | live | 0 sites; host arm |
| `getvolumes` | builtin | live | 0 sites; host arm |
| `immediatesprite` | builtin | live | 0 sites; host arm |
| `moveablesprite` | builtin | live | 0 sites; host arm |
| `param` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host |
| `ramneeded` | builtin | live | 0 sites; host arm |
| `sendallsprites` | builtin | live | 0 sites; host arm |
| `sendsprite` | builtin | live | 0 sites; host arm |
| `spritebox` | builtin | live | 0 sites; host arm |
| `symbol` | builtin | live | 0 sites; lingo_builtins.gd |
| `version` | builtin | live | 0 sites; host arm |
| `alignment` | member | live | 0 sites; members.gd read_prop |
| `autotab` | member | live | 0 sites; members.gd read_prop |
| `backcolor` | member | live | 0 sites; members.gd read_prop |
| `border` | member | live | 0 sites; members.gd read_prop |
| `boxdropshadow` | member | live | 0 sites; members.gd read_prop |
| `boxtype` | member | live | 0 sites; members.gd read_prop |
| `castlibnum` | member | live | 0 sites; members.gd read_prop |
| `casttype` | member | live | 0 sites; members.gd read_prop |
| `changearea` | member | live | 0 sites; members.gd read_prop |
| `chunksize` | member | live | 0 sites; members.gd read_prop |
| `depth` | member | live | 0 sites; members.gd read_prop |
| `dropshadow` | member | live | 0 sites; members.gd read_prop |
| `duration` | member | live | 0 sites; members.gd read_prop |
| `controller` | member | live | 0 sites; members.gd read_prop -> media.gd; the QuickTime controller bar; Director's dialog default until a script writes it, because the digital-video specific block is not decoded |
| `directtostage` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `video` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `sound` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller`; the member spelling, not the builtin |
| `crop` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `center` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `scale` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller`; a two-element point |
| `framerate` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `pausedatstart` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller` |
| `loop` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller`; the member spelling, not `the loop of sound N` |
| `preload` | member | live | 0 sites; members.gd read_prop -> media.gd; as `controller`; the member spelling, not the builtin |
| `digitalvideotype` | member | live | 0 sites; members.gd read_prop -> media.gd; `#other` -- neither QuickTime nor Video for Windows can be identified without opening the file |
| `timescale` | member | live | 0 sites; members.gd read_prop -> media.gd; the media's own clock units; Director's tick for a sound member |
| `cuepointnames` | member | live | 0 sites; members.gd read_prop -> media.gd; decoded from a sound member's own markers; empty for a video, whose media cannot be opened |
| `cuepointtimes` | member | live | 0 sites; members.gd read_prop -> media.gd; as `cuepointnames`, in the member's duration units |
| `channelcount` | member | live | 0 sites; members.gd read_prop -> media.gd; decoded from a sound member's stream; 0 for a video |
| `samplerate` | member | live | 0 sites; members.gd read_prop -> media.gd; as `channelcount` |
| `samplesize` | member | live | 0 sites; members.gd read_prop -> media.gd; as `channelcount` |
| `filename` | member | live | 0 sites; members.gd read_prop |
| `filled` | member | live | 0 sites; members.gd read_prop |
| `fontsize` | member | live | 0 sites; members.gd read_prop |
| `fontstyle` | member | live | 0 sites; members.gd read_prop |
| `forecolor` | member | live | 0 sites; members.gd read_prop |
| `linecount` | member | live | 0 sites; members.gd read_prop |
| `lineheight` | member | live | 0 sites; members.gd read_prop |
| `linesize` | member | live | 0 sites; members.gd read_prop |
| `loaded` | member | live | 0 sites; members.gd read_prop |
| `margin` | member | live | 0 sites; members.gd read_prop |
| `mediabusy` | member | live | 0 sites; members.gd read_prop |
| `mediaready` | member | live | 0 sites; members.gd read_prop |
| `modified` | member | live | 0 sites; members.gd read_prop |
| `pageheight` | member | live | 0 sites; members.gd read_prop |
| `palette` | member | live | 0 sites; members.gd read_prop |
| `paletteref` | member | live | 0 sites; members.gd read_prop |
| `pattern` | member | live | 0 sites; members.gd read_prop |
| `purgepriority` | member | live | 0 sites; members.gd read_prop |
| `rect` | member | live | 0 sites; members.gd read_prop |
| `regpoint` | member | live | 0 sites; members.gd read_prop and write_prop |
| `scripttext` | member | live | 0 sites; members.gd read_prop |
| `scripttype` | member | live | 0 sites; members.gd read_prop |
| `scrolltop` | member | live | 0 sites; members.gd read_prop |
| `shapetype` | member | live | 0 sites; members.gd read_prop |
| `size` | member | live | 0 sites; members.gd read_prop |
| `textalign` | member | live | 0 sites; members.gd read_prop |
| `textheight` | member | live | 0 sites; members.gd read_prop |
| `textstyle` | member | live | 0 sites; members.gd read_prop |
| `transitiontype` | member | live | 0 sites; members.gd read_prop |
| `type` | member | live | 0 sites; members.gd read_prop |
| `wordwrap` | member | live | 0 sites; members.gd read_prop |
| `desktoprectlist` | system | live | read only |
| `framelabel` | system | live | read only |
| `framepalette` | system | live | read only |
| `framescript` | system | live | read only |
| `framesound1` | system | live | read only |
| `framesound2` | system | live | read only |
| `frametempo` | system | live | read only |
| `frametransition` | system | live | read only |
| `itemdelimiter` | system | live | interpreter, read+write |
| `keypressed` | system | live | read only |
| `labellist` | system | live | read only |
| `lastframe` | system | live | read only |
| `moviefilefreesize` | system | live | read only |
| `moviefilesize` | system | live | read only |
| `organizationname` | system | live | read only |
| `paramcount` | system | live | interpreter, read only |
| `productname` | system | live | read only |
| `productversion` | system | live | read only |
| `quicktimepresent` | system | live | read only |
| `digitalvideotimescale` | system | live | 0 sites; read+write; 0 is Director's "each member's own scale" |
| `result` | system | live | interpreter, read only |
| `rollover` | system | live | read only; **answers the builtin's query, not the property's** (§4.5). Director's `the rollOver` is the ink-aware hit test with no eligibility filter; this is the pure-rect descent `rollOver(n)` uses. Bound and wrong-by-one-query rather than absent -- `ENGINE_TODO.md` has what a third channel would cost. |
| `romanlingo` | system | live | read only |
| `safeplayer` | system | live | read only |
| `selection` | system | live | read only |
| `serialnumber` | system | live | read only |
| `time` | system | live | read only |
| `trace` | system | live | read+write |
| `tracelogfile` | system | live | read+write |
| `username` | system | live | read only |
| `videoforwindowspresent` | system | live | read only |
| `windowtype` | system | live | read+write |
| `xtras` | system | live | read only |
| `new` | builtin | live | 6 sites; lingo_interpreter.gd, before the module and the host; §7.1. Builds a script object and runs its `new` handler with `me` as the first argument; the expression is what that handler *returned*, which is `me` by convention and may deliberately be something else. Resolved ahead of user handlers, alone among the builtins: every parent script declares `on new`, and `ancestor = new(script "base")` inside it would otherwise be unbounded recursion. |
| `script` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. A packed member reference, like `member()`'s, so `the scriptText of script "x"` works on it; `new` turns one into an object through `preview_lingo_host.gd:script_at`. The designator spelling `script "Parent"` is a parser arm rather than a command call, because the command form's argument loop crosses commas and `new(script "base", who)` would hand the constructor's arguments to the designator. |
| `call` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. `call(#msg, objectOrList, args...)`, with `me` in front of the arguments. A **list** is Director's broadcast form and every object in it that answers runs; the value is the last one's, and an object that does not answer is skipped in silence, which is the reference's own `if (sym.type == VOIDSYM)`. |
| `send` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; D4's undocumented spelling of `call`. The reference maps both names onto one body (`lingo-builtins.cpp:126,149`) and so does this. |
| `callancestor` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; §7.1. Enters the chain at the object's **ancestor**, skipping the object's own handler, and `me` inside it is the ancestor. **The reference stubs this** (`b_callAncestor` prints and drops the stack), so what is built is Director's documented meaning of the name rather than a copy of an implementation. |
| `sendancestor` | builtin | live | 0 sites; lingo_interpreter.gd, before the module and the host; D4's spelling of `callAncestor`, one body as above. |
| `timeoutlength` | system | live | 0 sites; read+write; §3. Ticks of no player activity before `timeOut` is raised; 10800 (three minutes) by default, which is `movie.cpp:90`. **0 or less disables the clock** -- not in the reference's arithmetic, and necessary here because otherwise the default would fire on every tick of every movie. |
| `timeoutlapsed` | system | live | 0 sites; read+write; §3. Ticks since the clock was last reset. **Writable**, against the D3.1 manual and with the reference: `lingo-the.cpp:1496` records that D2 and D3 Mac allow it and that a shipped title relies on it. Writing moves the origin, so `set the timeoutLapsed to 0` restarts the clock. |
| `timeoutmouse` | system | live | 0 sites; read+write; §3. Whether a mouse press resets the clock; true by default. Stamped at the press for both buttons, where `events.cpp:270` stamps it -- a release and a move do not count. |
| `timeoutplay` | system | live | 0 sites; read+write; §3. Whether `play` resets the clock; false by default. **The reference stores this and never reads it**, so the consumer is built from Director's documented meaning and is unverified against Director running. |
| `timeoutscript` | system | live | 0 sites; read+write; §6.3 tier 1. The fifth member of the `*Script` family and the same mechanism exactly -- a string of Lingo compiled in the setter, run as the primary handler for `timeOut` before the frame and movie scripts see it. The reference's write arm is `movie->setPrimaryEventHandler(kEventTimeout, ...)`, which is the call the other four make. |
| `actorlist` | system | live | 0 sites; read+write; §6.1. The objects sent `stepFrame` once per frame, in list order, after `the perFrameHook` (`scenes/preview/actors.gd`). The **live** Array is handed back rather than a copy, because `append(the actorList, x)` is how a title adds to it and a copy makes that idiom silently do nothing. Not saved in a session record: an object has no JSON form. |
| `perframehook` | system | live | 0 sites; read+write; §6.1. One object, sent `stepFrame` at the point `score.cpp:731-770` calls `executePerFrameHook` -- after the playhead moves, before `prepareFrame`, and skipped on a frame carrying a transition, which the reference hangs on the transition's subframes instead. VOID until a movie installs one, which is why `tools/lingo_surface_audit.gd` now asks whether the host *reported* rather than whether it answered VOID. |
| `updatelock` | system | live | 0 sites; read+write; §3. TRUE suppresses the stage repaint -- both `updateStage`'s (`director_preview.gd:repaint_now`) and the frame loop's (`stage_redraw`). The reference declares `kTheUpdateLock` and implements neither half, so this is the property's documented meaning: the paint is **skipped, not queued**, so clearing the lock does not replay what was missed. The engine's own repaints -- a resize, a debug overlay, a palette change -- still happen, because Director's lock is over the movie's updates. |
| `filename` | cast | live | 4 sites; cast_libs.gd read; §5.1. The path the movie *names* for an external cast, not the one this port resolved it to: a title comparing it against a string it built itself is comparing against the authored spelling. "" for the internal cast, which is Director's answer. Read-only, as all three of these are. |
| `name` | cast | live | 1 sites; cast_libs.gd read; §5.1. The library's name from the movie's `MCsL`. |
| `number` | cast | live | 0 sites; cast_libs.gd read; §5.1. The reverse lookup, a name to a library number, asked through `members.gd:library_named` rather than re-derived -- or the two would disagree about a library genuinely called "2". **-1** for a name that matches nothing, which is the reference's answer and is not 0, because 0 would be indistinguishable from a library-1 answer. |
| `centerstage` | window | live | 0 sites; windows.gd read+write |
| `bareadini` | builtin | live | 0 sites in `games/`, 34 in `test-games/itamar-magichat`; host arm -> `lingo/lingo_buddyapi.gd`. **BuddyAPI** (Gary Smith), the third-party Xtra a Windows title reaches for when Director has nothing: `baReadIni(Section, Keyname, Default, IniFile)` answers the value or the caller's `Default`. Windows' own `GetPrivateProfileString` rules -- case-insensitive section and key, `;` comments, whitespace stripped, one matching pair of quotes removed. **A string, always**, which is the whole of `bugs.md` 78: unbound it answered the integer 0, magichat's `if tmp = EMPTY` was false, its own `"intro"` fallback was skipped, `#startFrame` became 0 and the playhead never left frame 0. `tools/buddyapi_xtra.gd` asserts the `ilk` and the `= EMPTY` test rather than the value alone. Paths resolve through FileIO's index (case-insensitive tail match against the game root). |
| `bawriteini` | builtin | live | 0 sites in `games/`, 2 in `test-games/itamar-magichat`; host arm. `baWriteIni(Section, Keyname, Value, IniFile)`, 1 on success and 0 on refusal. A read-modify-write that keeps every other line of the file exactly as it stands -- comments, blanks, key spelling and the file's own line ending -- because a hand-written `.ini` is one a movie's own line scanner also reads. Refused outside the game root always and in a headless run without `--allow-writes`, and the refusal is reported: BuddyAPI has no `status` channel for a reason to arrive through. |
| `baflushini` | builtin | live | 0 sites in `games/`, 2 in `test-games/itamar-magichat`; host arm. The commit. Writes above are committed eagerly, so that a title that never flushes cannot lose its save; what is left for this is what a flush is actually for -- re-commit anything a failed write left pending, and drop the parsed document so the next `baReadIni` reads the disk instead of this process's memory. **Not `noop`**, and the harness proves it: the file is changed behind the cache, the same read must still answer the old value, and must answer the new one after the flush. |
| `bafileexists` | builtin | live | 0 sites in `games/`, 1 in `test-games/itamar-magichat`; host arm. 1 or 0, through the same resolver, so a 1997 path with a dead directory in front of a live tail answers correctly. |
| `bafilesize` | builtin | live | 0 sites; host arm. Bytes, or **-1** for a file that is not there -- the one return value BuddyAPI's own published listing writes out rather than leaving to its 1/0 convention. |
| `badeletefile` | builtin | live | 0 sites in `games/`, 2 in `test-games/itamar-magichat`; host arm. 1 on success, under both write guards. |
| `bacopyfile` | builtin | live | 0 sites in `games/`, 2 in `test-games/itamar-magichat`; host arm. `baCopyFile(Src, Dest, Overwrite)`; `"Never"` refuses an existing target, `"IfNewer"`/`"IfOlder"` compare modification times, and anything else -- including the corpus's own `"Always"` -- copies. **Unverified**: the published listing names the argument and not its accepted values. |
| `barenamefile` | builtin | live | 0 sites; host arm. Windows' rename, so it refuses rather than replaces when the new name is taken. |
| `bafilelist` | builtin | live | 0 sites; host arm. A Lingo list of the **bare names** in a folder matching a DOS wildcard, which is what makes the usual `repeat with f in baFileList(dir, "*.txt")` loop concatenate correctly. |
| `bafolderlist` | builtin | live | 0 sites; host arm. The sub-folder names, as a list. |
| `bafolderexists` | builtin | live | 0 sites; host arm. 1 or 0, through `FileIO.resolve_folder` -- the folder half of the same index, added with this. |
| `bacreatefolder` | builtin | live | 0 sites; host arm. One level, under the game root, named by the request's last element: a 1997 path names a tree that is not here and building it to satisfy the request is not this port's job. Fails on a folder that is already there, which is `CreateDirectory`'s own answer. The listing gives no return value for this call; 1-on-success is BuddyAPI's convention everywhere it is written down, and is unverified. |
| `badeletefolder` | builtin | live | 0 sites; host arm. **Empty folders only**, which is the published behaviour and also the only version of this call a player should have: a recursive delete driven by a path a movie built is how a corpus disappears. |
| `baopenurl` | builtin | live | 0 sites in `games/`, 3 in `test-games/itamar-magichat`; host arm. **Declines, and says so.** The call asks the host operating system to open a URL a *movie* chose, and two of magichat's three sites pass `ReadConfigLine("globals", "before")` -- a string out of a configuration file this player will read from anywhere under the game root. It answers 0, which is BuddyAPI's own "this did not happen", and reports the URL through the diagnostics so the decision is visible rather than silent. Live rather than `noop` because the report is the effect; if opening is ever wanted it belongs behind an opt-in beside `--allow-writes`. |
