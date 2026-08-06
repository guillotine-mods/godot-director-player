# Lingo's surface

What the language actually exposes, catalogued so that an interpreter written
here can be checked against it rather than grown one missing name at a time.

The port already runs the original's scripts (`lingo/lingo_interpreter.gd`) and
binds them to the engine (`lingo/lingo_host.gd`). What it has never had is the
*other* half of the picture: the list of everything Director offers, so that a
name the game reaches for and the port answers with VOID can be told apart from
a name nobody will ever use. `data/lingo_vocabulary.json` closed that for
properties. This closes it for the language as a whole, and ends with the gap
analysis the two together make possible.

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

## 1.4 Navigation and score

| Name | Arity | Meaning |
|---|---|---|
| `go` | 1..2 | Move the playhead: to a frame number, a marker label, or a frame/marker in another movie. |
| `play` | 0..2 | Like `go`, but pushes the current position; `play done` pops it. |
| `playAccel` | … | `play` without the return-position push. |
| `marker` | 1 | Frame number of the marker *relative to the playhead*: 0 = the marker at or before it, +n = n markers forward, -n = n back. |
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

`marker` is **playhead-relative and position-indexed, not name-indexed.** This
is the single most dangerous item in the whole catalogue for a port, and this
one already got it wrong once: `lingo/lingo_host.gd` carries a comment
recording that a name-based lookup collapsed all 49 of `strtgame`'s markers
(only 32 of them distinctly named — Director calls an unnamed one "New Marker")
onto the first, so `go(marker(0) + 1)` jumped to the same frame from everywhere
and a cinematic looped for ever. `marker(0)` must be resolved by scanning
sorted marker frame numbers against the current playhead.

`play` versus `go` matters only if the movie uses `play done`. This game does
not — `lingo/lingo_host.gd` maps `play` onto `go` deliberately and says so —
but a port that inherits that shortcut into a title which *does* use the play
stack will return to the wrong place with no error.

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
value. `lingo/lingo_host.gd` documents how this port packs the pair into a
single integer and why the packing does not need to match Director's: all 18
`castNum` sites in the corpus are one line that produces and consumes the
integer inside a single expression. That reasoning is worth reading before
reusing this port's encoding anywhere the integer might be stored or compared.

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

`and`, `or`, `not`. VOID and 0 are false, everything else true. `and` and `or`
short-circuit. `not` of VOID is true.

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

Whole floats print without a decimal part. That is why `put 3.0` shows `3`, and
why a port that uses GDScript's `str()` will emit `3.0` into a field the game
later parses.

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
(`lingo/lingo_engine.gd`), which is the only way it can be right — a value
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
- **`the volume of sound N`** — sound channel volume.
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

`lingo/lingo_engine.gd` implements tiers 2–5 exactly (`dispatch_sprite_event`:
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

1. **`marker(n)` is playhead-relative and resolved by position.** Not by name.
   Unnamed markers exist and share a name. Already cost this port a hanging
   cinematic.
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
17. **Whole floats print without a decimal part.**
18. **A property assignment can install an event handler** — the four `*Script`
    properties hold Lingo source.

---

# 9. Gap analysis

Measured against `data/lingo_vocabulary.json` (3,349 scripts, 0 unparsed) and
the tables in `lingo/lingo_host.gd`. Usage counts are AST-node occurrences
across the whole corpus, not scripts touched, so they weight a name by how
often the game reaches for it rather than by how many files mention it.

## 9.1 (a) In ScummVM, used by this game, not implemented here — the priority list

**The property surface is closed.** Every sprite, member and system property
the corpus reads or writes is bound, with one apparent exception that is a
false positive:

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
| `saveMovie` | 2 | `saveMovie(savepath & "hezsave.dir")` | The original's save mechanism — it wrote game state by saving a modified movie. This port has its own save system, so binding it inert is probably right, but it should be a decision. |
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
implemented.

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

**Builtins the interpreter answers itself**, because they have no engine side
(`lingo/lingo_interpreter.gd`): `value`, `string`, `integer`, `float`, `abs`,
`length`, `chars`, `offset`, `count`, `getAt`.

**Operators and value semantics** (`lingo/lingo_value.gd`,
`lingo/lingo_interpreter.gd`): `+ - * /` with the integer-division rule, `mod`,
`&`, `&&`, `= <> < > <= >=` with case-insensitive string comparison, `and` /
`or` with short-circuit, `not`, `contains`, `starts`; chunk expressions for
char/word/item/line with ranges, nesting, chunk assignment and a mutable
`the itemDelimiter`; list literals, property-list literals and one-based
indexing; the constants `EMPTY`, `TRUE`, `FALSE`, `RETURN`, `CR`, `QUOTE`,
`TAB`, `SPACE`, `VOID`.

**Statements consumed by the interpreter**: `global`, `property`, assignment,
`put … into/before/after`, call statements, `if`/`else`, `repeat while`,
`repeat with` (up and down), `repeat in`, bare `repeat`, `case`, `tell`,
`exit repeat`, `next repeat`, `exit`, `return`. Expression node kinds: `num`,
`str`, `var`, `list`, `proplist`, `unary`, `binary`, `chunk`, `count`, `field`,
`field_prop`, `sprite_ref`, `member_ref`, `member_number`, `sprite_number`,
`sprite_prop`, `member_prop`, `prop`, `prop_of`, `dot`, `index`, `call`.

**Properties.** Sprite reads: `bottom`, `castLibNum`, `castNum`, `constraint`,
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

Everything else in the enumerated vocabulary is listed in one of the three
`*_UNSUPPORTED` tables in `lingo/lingo_host.gd` — **a decision, recorded, not a
hole.** Reads against those tables answer VOID and report the name with an
`(unsupported)` mark, so a log distinguishes "the port refuses this" from "the
port never heard of this". That distinction is the most valuable thing in the
host and should survive any rewrite.

**Event model.** `lingo/lingo_engine.gd` implements tiers 2–5 of the mouse
hierarchy (`dispatch_sprite_event`), frame-and-movie dispatch for frame events
(`dispatch_frame_event`), and `enterFrame`/`exitFrame` broadcast to every
sprite behaviour in the frame (`dispatch_sprite_behaviours`) — which the
comment there notes is load-bearing, because `whereami`, gated on by 138
`mouseUp` handlers, is set by an `enterFrame` in a sprite behaviour rather than
any frame script. `director/director_runtime.gd` drives `enterFrame`,
`exitFrame`, `startMovie`, and dispatches `mouseDown` followed by `mouseUp` on
a click.

**Not implemented in the event model**: primary event handlers (tier 1) —
`the keyDownScript` is stored and run as a *handler name* rather than as Lingo
source, and the other three `*Script` properties are unbound; `prepareFrame`,
`beginSprite`, `endSprite`, `stepFrame`, `stepMovie`, `idle`, `timeout`,
`mouseEnter`/`mouseLeave`/`mouseWithin`/`mouseUpOutSide`, `cuePassed`, and the
window events; the queue-the-whole-chain-then-run model (tiers are resolved
lazily and stop at the first that answers); and the D3-versus-D4 `mouseUp`
sprite asymmetry.

**The preview host** (`scenes/preview_lingo_host.gd`) is a deliberately smaller
surface for the room preview: `go`, `sound`, `puppetSound`, `soundBusy`,
`label`, `marker`, and an ignore-list of `puppetTransition`, `updateStage`,
`beep`, `delay`, `preLoadMember`, `preLoad`, `unLoadMember`, `unLoad`, `alert`,
`cursor`, `nothing`, `dontPassEvent`, `puppetSprite`, `halt`, `quit`,
`startTimer`. System props: `frame`, `mouseH`, `mouseV`, `clickOn`, `ticks`,
`milliseconds`/`timer`, `machineType`. It counts what it reaches and what it
does not, which is the same discipline as the real host at a tenth the size.

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
