extends SceneTree
## Which members a movie's scripts puppet onto channels, what those members are,
## and which of them are film loops with film-loop children.
##
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir
##   godot --headless --path . --script tools/puppet_members.gd -- --root rating --file blatack1.dir
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --all
##   godot --headless --path . --script tools/puppet_members.gd -- --source
##
##   --root R     the corpus (default the config's)
##   --file F     the container (default the config's boot movie)
##   --all        every container of the root in counts, and nothing else: how the two
##                init rules divide each movie's runs. One process per root.
##   --play S     after the static report, enter scene S the way the movie does and
##                say what drew. `--play all` walks every scene it derived.
##   --ticks N    process frames to give one played scene (default 4000)
##   --no-input   press nothing: the control run every input claim needs
##   --avoid L    channels `--play` must not click, comma-separated, on top of the ones
##                derived. For a back-to-the-menu button kept as a *cast* script, which
##                the derivation cannot see — `hex2.dir`'s ch90 is the measured case.
##   --source     print each script's handler text under its findings
##   --verbose    print every element of every game, not the first 12
##
## A survey and not a gate: it prints a table and numbers rather than pass/fail,
## so it is not in `gate.sh`'s `ALL`.
##
## ## What this answers, and why the question needed a tool
##
## A film loop whose child was itself a film loop drew nothing: `film_loop_view.gd`
## asked `host._texture_for` per child and that path is bitmap-and-shape only, so a
## type-2 child returned null and the inner loop was skipped whole. Fixed, in
## `paint_loop`'s recursion. **What that fix was worth needed a different question
## answered: which of a movie's scripted scenes had a nested loop in it at all.**
## `tools/film_loop_nesting.gd` says which loops nest and `tools/film_loop_cast.gd`
## says where their children resolve; neither says which *scene* the player would
## have noticed it in, because neither reads the scripts that put a loop on a
## channel.
##
## So this walks the other way round: from the movie's own markers and score to the
## scripts, from those scripts to the members they assign, and from a type-2 member
## into its children. The measured answer for `piposh-dream/COMEIN.dir` — six
## minigames, one per character — is that **exactly one of the six was hit**, and it
## is recorded in `docs/bugs-closed.md` beside `bugs.md` 98.
##
## ## How a "scene" is derived, with no table anywhere
##
## Nothing here names a movie, a marker, a channel or a member. Five rules, each
## read off the container:
##
## **An init is a frame script that claims a channel.** `puppetSprite(N, 1)` takes
## channel N away from the score so a script can dress it; `puppetSprite(N, 0)`
## gives it back. Only the claim counts, and that one bit is the whole
## discriminator: of COMEIN's **15** frame scripts calling `puppetSprite`, **6
## claim and 9 release**. The releases are the two ways a scene can end — the
## `fritzend`/`docend`/`krupend`/`rafend`/`hatend`/`pozend` frames handing the
## channels back when the character has been hit, and the six `*win` frames doing
## it inside a `repeat with i`, where the channel is a variable this cannot bound
## and does not need to. Count mentions instead of claims and this file would report
## fifteen games in a movie that has six, and the nine extras would all be endings.
##
## **Where a movie never puppets at all, an init is a frame script that *dresses* a
## channel.** `puppetSprite` is the author's own statement of which script owns which
## channel, so where it is present it is the better evidence and this second rule is
## a fallback rather than a widening: it fires only when **no** covered frame script
## in the container so much as mentions `puppetSprite`. `piposh-dream/puzzle.dir` is
## why it exists. That container is a playable 4x4 sliding-tile puzzle whose sixteen
## tiles are ordinary score sprites — Director's own auto-puppets, and the subject of
## `docs/bugs-closed.md` 120 — made visible with `sprite(i).visible = 1` and dressed
## by name with
##
##     set the member of sprite gsnum to "paz" & item x of line y of field "pazel"
##
## Nothing in it calls `puppetSprite`, so the claim rule reported `0 run(s) hold a
## claiming init` for a container `tools/puzzle_board.gd` gates as a working game:
## a survey and a gate contradicting each other, and a minigame sweep that drops
## the movie from its set. Its init is `1:2` on f5, under the movie's own `restart`
## marker, and it deals the board, reveals the tiles, dresses all sixteen and sets
## the `ifmove` global that the tiles' own `mouseDown` reads.
##
## **The gate is `mention` and not `claim`**, which is the whole of what keeps this a
## fallback. `PUPPET` requires the call to end the line, so a movie that this file
## reports as releasing without ever claiming is a movie whose claims the regex
## missed rather than one that has none — and opening the fallback there would turn
## COMEIN's nine ending screens into nine more games, in whichever container that
## shape next appears. `piposh-dream/rating.dir` is that shape in this corpus today:
## 2 mentions, 0 claims, and a `claim == 0` gate would have opened the fallback in a
## movie that puppets.
##
## **Measured with `--all` over all six roots**: 482 movies hold a score, 1,207 scenes
## come from a claiming init, the fallback adds **2** — and the gate refuses **350**
## runs that dress inside movies that do puppet. That last number is the whole
## argument for the gate rather than an assumption that nothing was over-widened:
## `piposh-dream/hatul3.dir` alone would have gone from 14 scenes to 43. It is the
## `gated` column, and it is printed rather than reasoned about.
##
## **Those 29 were then read**, because "they are all endings" is the kind of sentence
## that reads as measured whether or not anybody measured it. Fifteen are one frame
## long and run `1:155`, which is COMEIN's ending shape exactly: `puppetSprite(20, 0)`,
## `puppetSprite(21, 0)`, then `hatmen = hatmen - 1` and a respawn at `savespot`. The
## other fourteen are three frames each under the movie's own `stage<N>psila`,
## `stage<N>water` and `stage<N>fall` markers, running `1:150` or `1:154` — which open
##
##     set the keyDownScript to EMPTY
##     set the keyUpScript to EMPTY
##     set the member of sprite 15 to member(89, 2)
##
## and drop or lift the cat by 40 pixels. They dress a channel while *disarming* the
## controls, which is this file's own definition of a scene ending (`KEY_INSTALL`
## deliberately does not match the EMPTY form). So all 29 are outcome frames and none
## is an init, which is what the gate refusing them is worth.
##
## The false negative that remains, stated rather than hidden: a movie that puppets
## in one scene and auto-puppets in another still loses the second. That is what a
## fallback costs, and it is not what `puzzle.dir` was — nothing in it puppets at all,
## in a covered frame script or anywhere else in the container, and the same is true
## of the second site the rule finds.
##
## **The other site is a main menu, and it is worth knowing before reading a report.**
## `piposh2/strtgame.dir` f839..f906 — the default root's own boot movie, so a bare
## run lands on it — is the four-button menu, and its `1:357` swaps each button
## between a still bitmap and a 14-frame film loop on `rollOver`. Derived correctly
## and it is not a minigame: the label to read is `dressed`, and the honest reading of
## a dressing scene is "a script puts members on channels over these frames", which is
## this file's subject and not a claim about what the player is playing. (Its derived
## *name* is `credits`, from the one marker it exits to, which is `_name_of`'s
## longest-common-prefix rule having a single exit to work with.)
##
## Which of the two rules fired is on every line of the report, as `claimed` or
## `dressed`. The two words are `--play`'s own labels for a sampled channel because
## it is the same distinction: a claimed channel is off the score, so a member on it
## can only be the script's, and a dressed one is still shared with the score.
##
## What the derived `puzzle.dir` scene then *says* is thin, and that is a second
## defect rather than this one: its channel operand is `gsnum`, a `repeat` counter,
## and its right-hand side is a string concatenation rather than a `member()` call,
## so both come out `UNBOUND` and the scene reports no elements. Bounding a bare
## loop variable would feed the **claim** scan as well and could move COMEIN's six,
## so it is a separate change owing its own control run. `tools/scene_probe.gd
## --marker restart` is what reads that board today, and `bugs.md` 120 used it.
##
## **A scene is the covered run its init sits in.** Frame scripts arrive as score
## interval entries — a span of frames with a script attached — so "which frames
## does a script run on" is a fact the score states. Take the maximal *contiguous*
## stretch of frames that some frame-script interval covers, and the run containing
## an init is that init's scene. In COMEIN the six runs come out
## f177..f207, f294..f318, f436..f474, f573..f610, f722..f753 and f894..f921: the
## init, the throw, the collision poll and the settle, and nothing else. The
## outcome frames (`fritzend` f209, `fritzwin` f226) are runs of their own, one
## frame each, because the frames between are uncovered — which is the score
## saying they are a different scene, not this file deciding it.
##
## **The narrowest covering interval wins.** That is `scenes/preview/scripts.gd`'s
## rule, carried here rather than called: `for_frame` takes the preview node and
## reaches `host._script_in_lib`, so a headless static pass cannot use it. A movie
## carries both scene-specific frame scripts and ones that span everything, and
## taking the first match hands every frame to the widest.
##
## **A script member number is resolved in the library the interval names.** With
## `0` and `0xFFFF` normalised to 1, which `scripts.gd:in_lib` does and
## `DirectorScore._read_interval` deliberately does not — it stores the raw `_i16`.
## Skip the normalisation and the resolution lands in the wrong cast, which is the
## bug class `scripts.gd` exists around: it returns a stranger rather than nothing.
##
## ## Members from expressions, not only from literals
##
## Half of what a scene assigns is not a literal. COMEIN's throw handlers say
##
##     set the member of sprite (26 + x) to member(155 + x, 1)
##
## and a literal scan finds neither the channels nor the members. So an operand is
## either an integer or `<int> + <var>`, and **a variable's range is bounded by the
## comparisons the same handler makes against it**: `if (x = 1) or (x = 2) or
## (x = 3)` admits exactly 1, 2 and 3, so the channels are 27, 28, 29 and the
## members 156, 157, 158. That is a general mechanism rather than a special case —
## an author who writes an offset writes the guard beside it — and it is
## corroborated on every run rather than trusted: each scene's line **compares** the
## channels the arithmetic derived against the ones its init claimed and says whether
## they agree, which for COMEIN's six is where 27, 28, 29 meets `puppetSprite(27, 1)`
## three times over. Where a handler dresses a channel the init never claimed, the line
## names it — `hat` and `poz` do exactly that, dressing 3 and 4 with a literal after
## claiming them, and `doc` dresses 3 and 4 **without** claiming them, which is the lead
## at the bottom of this file. A `derived` member is labelled as such in the output, and an
## operand this cannot bound is reported verbatim as `unbounded` rather than
## dropped, because a member silently missing from a survey of members is the
## failure mode worth avoiding.
##
## Only assignment reaches a channel, so only assignment is scanned:
## `set the member[Num] of sprite`, and the dot form `sprite(N).member[Num] =`.
##
## ## The nesting question
##
## For every member a scene assigns: its type, and for a type-2 member its frame
## count, its `looping` flag, and whether any child resolves to another type-2
## member. Opened through `FilmLoopView.open_loop` and resolved through
## `FilmLoopView.child_lib` — the preview's own entry points, so what is reported
## is what the painter walks rather than a second reading written here, which is
## the discipline `tools/film_loop_cast.gd` and `tools/film_loop_scale.gd` both
## keep.
##
## ## Where the player gets in
##
## The played half of this question needs an entry, and the entry is derivable too.
## An idle span is a closed loop: a frame in the run, *before* the init, whose
## script jumps back to the marker covering it (`go(marker(0))`, or `go to the
## frame`). Nothing in the score can leave such a loop, so whatever does is a
## sprite behaviour — and the one to click is the sprite over those frames whose
## script has an `on mouseUp`/`on mouseDown` that calls `go`. Its rect comes from
## the score's own record through `Geometry.stage_rect`, so the click point is the
## movie's and not a coordinate written down here.
##
## `--play` then uses it: a scene with a click entry is entered by putting the
## playhead inside the idle span and pressing the derived point, and a scene without
## one by landing `LEAD_IN` before its init — or before the movie's own `action*` marker
## where it has one, which `_landing` explains and which two different scenes measured the
## hard way.
## **Neither ever jumps to the init marker**, and that is not superstition — landing on
## the init means the score's own arrival at that frame is what would have run the
## `puppetSprite`, the globals and the `keyUpScript`, and skipping it leaves a scene
## whose channels were never claimed. Frames are awaited, never ticked in a loop, for
## `AGENTS.md`'s reason: a synthetic tick advances the runtime clock and not the audio
## server's, so every `soundBusy` gate holds for ever and the speech before a scene
## never ends. Keys are pressed on the movie's *score ticks* rather than per
## process frame, because these scenes read them through a `keyUpScript` and a press per
## frame pins the playhead (`tools/film_loop_restart.gd`'s `PRESS_EVERY`).
##
## **Which** keys is the scene's own business and is derived, not chosen: the handlers its
## init installs (`set the keyUpScript to "westup"`), and the `the keyCode = N` tests and
## `case the keyCode of` arms inside those handlers. A scene that installs none is a mouse
## scene and is driven with the mouse instead, on whichever visible channels
## `interaction.gd:script_for_click` — the click descent itself — says a `mouseUp` would
## reach. `--no-input` presses nothing, which is the control every claim about input needs:
## the difference between the two runs is the only thing that says a change came from the
## player rather than from the score.
##
## Measured on COMEIN: **one** of the six scenes is behind such a loop —
## `fritz`, whose f178 runs `go(marker(0))` and whose channel 36 carries
## `on mouseUp ... go(marker(1))`, the doorbell. The other five have no gating
## behaviour anywhere in or before their run; the movie plays into them through the
## speech gate (`if not soundBusy(1) then go(marker(1))`). So the general shape does
## *not* repeat, and a survey that assumed it did would have gone looking for five
## hotspots that are not there.
##
## ## Position, and the channels nobody was watching
##
## The played sampler read `membernum` and `visible` and nothing else, so **a scene whose
## visible behaviour is a sprite moving measured as dead on it.** Two things changed for
## that, and it is worth being exact about which of them did the work, because the
## obvious diagnosis was the wrong one.
##
## `piposh-dream/fritz2.dir`'s scene at f273 is the case. With input and without, every
## channel it watched reported the same members, and the row read as a game that takes
## none. The diagnosis on record was that the scene *moves* a sprite rather than swapping
## its member. Its own scripts say otherwise — `1:10` and `1:11` each do both, in
## adjacent lines:
##
##     set the memberNum of sprite getAt(ppl, 1) to member(the memberNum of sprite getAt(ppl, 1) + 1, 2)
##     set the locH of sprite getAt(ppl, 1) to the locH of sprite getAt(ppl, 1) + 17
##
## and the reason neither showed is that `getAt(ppl, 1)` is channel **10**, and channel
## 10 was not being watched. `ppl = [10, 11, 12, 13]`, the init claims all four with
## `repeat with i = 10 to 13` / `puppetSprite(i, 1)`, and a bare loop variable is the one
## operand `_operand` refuses to bound. So `claimed` came out `[1, 32]`,
## `assigned_channels` `[6]`, and the four channels the entire scene is about were
## invisible to the instrument. The blind spot was the **watch list**, not the property.
##
## Both are fixed. The sampler asks the engine which channels the run puppeted rather
## than only which ones a regex could spell (`_puppeted_now`), and it reads
## `the locH`/`the locV` of every watched channel as a signal of its own
## (`_note_position`). Measured on that scene over 4,000 process frames, against
## `--no-input` at the same landing — the watch list goes from `[1, 6, 32]` to
## `[1, 6, 10, 11, 12, 13, 32]`, and:
##
##     ch      position, with input          position, no input        members in / out
##     1       STILL (1499, 240)             STILL (1499, 240)          1 / 1
##     6       STILL (504, 431)              STILL (504, 431)           1 / 1
##     10      MOVED 1x, 2 points            MOVED 1x, 2 points         1 / 1
##     11      MOVED 24x, 25 points          MOVED 24x, 25 points      21 / 21
##     12      MOVED 1x, 2 points            MOVED 1x, 2 points        35 / 14
##     13      STILL (27, 400)               STILL (27, 400)            8 / 8
##     32      STILL (190, 264)              STILL (190, 264)           2 / 2
##
## **So position is a new signal and it is not what separates the two runs.** Three
## channels move where the old table showed no channel doing anything at all, which is
## the description of the scene the survey could not previously give; but every position
## number matches its control to the step, and what the player changes is ch12's
## membership — 35 distinct members against 14, with 82, 83 and 84 reached only with
## input. The scene's own gate says why: the player's motion is behind
## `if getAt(mnv, 1) > 1`, the init sets `mnv = [0, 0, 0, 0, 0, 0]`, and only a hit
## raises it. Ch11's 25 points are `foemov` walking an enemy in on its own, which is the
## score's business and not the player's — and it is identical in both runs, which is the
## control doing its job.
##
## The other thing to read off that table: ch10, 11 and 12's positions stop at
## `h 138..563` and `v 350..386` because the init sets `the constraint of sprite i to 39`
## and the engine clamps into channel 39's box. `set the locH of sprite 13 to -20` is
## reported as a resting position of 27 for the same reason, so the numbers are the
## engine's answer and not the script's literal.
##
## The negative control is a scene that swaps members, `piposh-dream/hatul2.dir`'s
## `stage1psila` at f180, and it says the position signal does not manufacture motion:
##
##     ch      position, with input          position, no input        members in / out
##     1       MOVED 1x, 2 points            MOVED 1x, 2 points         2 / 2
##     15      MOVED 9x, 10 points           STILL (13, 392)            9 / 4
##     40      MOVED 2x, 3 points            STILL (-83, 152)           4 / 2
##
## Ch15 really does move, and Director's canonical walk cycle is why: `1:8`'s
## `hatulidown2` arm swaps the cat's member *and* adds 17 to its `locH` on the same
## keypress, so `h 13..148` over ten points beside members 2/3/4/18..21 is one behaviour
## and not two claims. Under `--no-input` the same channel is `STILL`, which is the
## reading that matters — the signal is silent where nothing pressed anything.
##
## **Ch1 is the caution, and it is in the table on purpose.** It reports motion in both
## runs, and nothing in the scene moves it: it swaps between members 3 and 236, and the
## score's own record for those two carries different `locH`/`locV`. A member swap can
## therefore move a sprite without any script saying `set the locH`, so a position
## difference is evidence about the *player* only against the control run — the same rule
## every other number in this file is under, and the reason `--no-input` exists.
##
## **What is legible now and still not fixed**: the *membership* column reads an absent
## channel too, and answers `member 0` for it. `EMPTY_CHANNEL`'s `visible` is 1, so the
## sampler's visibility guard lets an unoffered channel through, which is where fritz2's
## `ch 32 : visible with 0 on 17 frame(s)` comes from — 17 samples before the init, the
## same 17 the position line accounts for as `416 of 433 sample(s) drawn`. Left alone on
## purpose: fixing it moves every membership number this file has ever printed, and it is
## its own change with its own control run. The position line at least says out loud how
## many of a row's samples were real.
##
## ## A lead this survey turned up, filed as `bugs.md` 100, and got wrong
##
## This section said `doc` was the one of the six that never dresses its lanes: "over a
## 20,000-frame window channels 27, 28 and 29 are never dressed with 187/188/189 at all",
## and it built a two-anomaly case about `1:193` on top of that. **The measurement was
## this file's own doing.** It pressed `KEY_RIGHT` and `KEY_LEFT` unconditionally, and of
## COMEIN's six dodge handlers `dockeys` is the only one that reads `the keyCode = 125` and
## `= 126` — Down and Up. The other five read 123 and 124. So the one scene with vertical
## controls was played with the two keys its handler ignores, and a scene that is never
## given its throw key never throws.
##
## With the keys derived from `dockeys` itself, the same entry (f293, walked in) dresses all
## three: `ch 27 <- 187`, `ch 28 <- 188`, `ch 29 <- 189`, each "dressed onto ch [...] after
## the init". `--no-input`, same landing, reproduces the old reading exactly — nothing
## dressed, all three loops "never dressed onto a claimed channel" — so the attribution is
## the keys and nothing else.
##
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir --play doc
##   godot --headless --path . --script tools/puppet_members.gd -- --root piposh-dream --file COMEIN.dir --play doc --no-input
##
## Which lanes a given run dresses is a coin toss either way — the throw handler picks with
## `random(5)` and only three of five values throw — so read the set over runs, not one row.
## What is *not* settled: whether `doc` still leaves for `docend` earlier than it should on
## the `sprite(3).visible` branch of `1:195`. That was the second half of the same report and
## it needs the reference, not another run of this file.
##
## ## The day-2 containers, re-derived and played scene by scene
##
## The 2026-08-14 minigame sweep played **one scene per container** in `piposh-dream`'s
## day-2 games and said so, leaving `hatul2`'s other thirteen and `fritz2`'s other five
## unmeasured. Re-derived after the dressing fallback widened the init rule and after
## `--play` grew a position signal and a runtime watch list:
##
##     container    the sweep said    now                          moved
##     hatul2.dir              14     14 claiming, 0 dressing      no
##     fritz2.dir               6      6 claiming, 0 dressing      no
##     show.dir                 0      0 claiming, 0 dressing      no
##
## **`show.dir` is the one the fallback could have moved and does not.** It is the exact
## condition that opens the rule — 0 of its covered frame scripts mention `puppetSprite`,
## so the report says `the dressing fallback is ON` — and it still derives nothing,
## because nothing in the container dresses a channel either. `strings` over the file
## finds **0** `puppetSprite` and **0** `set the member[Num] of sprite` at any site,
## covered or not, so the zero is the container's rather than the rule's and no further
## widening reaches it. `show.dir` has no scenes because it assigns no members, which is
## a different fact from "it is not a game" — see the last part of this section.
##
## ### hatul2: thirteen of fourteen entered, and one row carries every one of them
##
## `--play all --ticks 4000 --avoid 12` against `--play all --no-input` at the same
## landings. **`--avoid 12` is load-bearing and the numbers say so**: without it all six
## water scenes click channel 12 on the gameover screen the run wanders into, leave for
## `mainmenu.dir` after ~1,000 of the 4,000 frames, and report their `drown`/`splsh`
## loops as *never painted* — which reads exactly like the nested-loop bug this file was
## built beside, and is nothing but a truncated run. With the channel avoided the same
## six paint both loops and agree with the control. That is the `hex2` ch90 case again in
## a container nobody had pointed it at.
##
## Thirteen of the fourteen report `init ran : yes`. Every one of the eight stage scenes
## rests on **channel 15, the cat, on both signals at once**: with input ch15 shows 7..9
## distinct members and 4..45 position steps, and against the control 2..4 members and
## **0 or 1** steps. `stage3`, `stage5`, `stage6` and `stage@f643` are the widest
## (42, 44, 45 and 43 steps against 0 or 1). Ch1 and ch40 read the same in both runs in
## six of the eight, which is the control doing its job; ch40 separates only in
## `stage1psila` and `stage5`, where the death loop is dressed onto it and only a
## keypress kills the cat. So the eight stages are one behaviour measured eight times —
## Director's walk cycle, `set the memberNum ... + 1` and `set the locH ... + 17` on the
## same arm — and not eight independent findings.
##
## The six water scenes rest on **ch20 and ch21**, at 193..300 position steps against 0
## or 1, and their membership barely moves (3..5 against 1..3). **Those six rows are not
## a like-for-like pair and the numbers must not be quoted as one.** Avoiding channel 12
## only moved the click: the play run then presses **ch13**, which is the gameover
## screen's *play again* button — `on mouseUp ... go("again")`, and the `again` frame's
## `exitFrame` is `go("newgame")` — so the input run replays the game from f179 and
## visits f179..f1128 while the control sits in f1050..f1093. The region differs as well
## as the input, and the honest row is "these are the frames the splash animation runs
## over, and only the input run reaches them" rather than "the player animates the
## splash". A pair worth quoting needs `--avoid 12,13` on the play side, which is one run
## nobody has made.
##
## The fourteenth, `stage8water@f982`, reports `init ran : NO` in **both** runs, and the
## cause is the landing rather than the engine. The playhead is put at f980 and the first
## frame either run samples is f1050: a script in between takes its
## `go("gameover")` branch, because the landing skipped the movie's own `newgame` at f179
## and `hatmen` is therefore never assigned. `AGENTS.md`'s VOID-global rule one level up —
## the *movie's* init, not the scene's — and the reason `stage1psila` (landing f178, two
## frames before `newgame`) is the only hatul2 scene that gets its globals honestly.
##
## ### fritz2: one scene of six is measured, and the other five are the same fight
##
## Every fritz2 scene lands at **f252** and every one of them plays f252..f300 (f255..f300
## before the settle frames were recorded; the span is the same walk). That is
## `_landing` above working as written and collapsing: the rule takes the latest `action*`
## marker at or before the init, `fritz2.dir` has exactly one (`actionbegins`, f254), and
## the inits are at f254, f273, f425, f517, f591 and f703. So `endstage1`..`endstage4` are
## landed 173 to 451 frames short of themselves and none is entered.
##
## They are not entered by a longer run either, and the movie says why: the fight holds on
## `go(marker(0))` and leaves for `endstage1` only when
## `sprite(30).visible = 1 and sprite getAt(ppl, 1) intersects 30`. Winning is the entry.
## `endstage1` then leaves for `endstage2` on its own copy of the same test, and so on to
## `endstage5`, so the container is a five-link chain each of whose links is a won fight.
## **A key driver that rotates through ten keys cannot win it**, and the reason is the one
## the position section above records: the player's own motion is behind
## `if getAt(mnv, 1) > 1`, which only a hit raises.
##
## So the only fritz2 row that is a measurement of its own scene is `actionbegins@f273`,
## and it reproduces `606a2a15` to the channel: ch12's membership is the whole difference,
## **34 distinct members against the control's 14** (35 when that commit measured it — the
## throw picks with `random`), every other watched channel identical on both signals. The
## five other rows carry that same ch12 difference because they are five recordings of the
## same fight, which is worth knowing before quoting them as five findings.
##
## ### `init ran` said NO about inits the playhead had run, and now does not
##
## **The settle frames were not in the record.** `init ran` was a flag the sampler set on
## `here == scene["init"]`, and the sampler's first pass is eight process frames after the
## landing -- while the landing is `LEAD_IN` frames *before* the init on purpose, so the
## playhead crosses the init inside those eight and the flag was asking about a window
## that starts after the frame it is about. Measured with
## `--root piposh-dream --file fritz2.dir --play "actionbegins@f254" --ticks 600
## --verbose`: landing f252, first sampled frame f256, 45 distinct frames f256..f300, and
## `init ran : NO (f254 is NOT in the frames played)` on a run whose own tally line
## reports the interpreter reaching `puppetsprite` nine times. Every scene whose init
## falls inside the settle window read NO, in every container this file has surveyed.
##
## Fixed by recording those frames (`_note_frame`), so the set the line prints is the set
## it tests. The same run now reports 48 distinct frames **f252..f300** and `init ran :
## yes`, and no channel row moves.
##
## **The control is a scene that comes close to its init and never stands on it**, because
## manufactured coverage would be a worse answer than the one fixed. `hatul2.dir`'s
## `stage8water@f982` is it: landing f980, the record now holds **f980** and then nothing
## until f1050 -- a script at f980 takes its `go("gameover")` branch -- and the row still
## reads `init ran : NO (f982 is NOT in the frames played)`. A near miss stays a miss. So
## do the four `endstage` rows below, whose inits are 173 to 451 frames past anything the
## run visits: `--play all` on fritz2 reports `yes` for exactly the two scenes whose init
## the playhead crossed and `NO` for the other four.
##
## A gap in the printed frame list is now the *movie* jumping rather than this file
## looking away, and the fixed run is its own example: f253 is absent because f252's
## frame script `3:2` is `if not soundBusy(1) then go(marker(1))` and `marker(1)` there is
## `actionbegins` at f254, so f253 ran no `exitFrame`. `_note_frame` records why that is
## a property of `frame_loop.gd` rather than a hope.
##
## ### The defect left in this file, found by pointing it at a container it had not seen
##
## Not fixed here. The reproducing command is `--root piposh-dream --file fritz2.dir
## --play <scene>`:
##
## **`_landing`'s `action*` rule has no distance bound.** It is right where the marker is
## in or beside the scene's own run (`actionbegins@f273`, measured) and wrong where the
## movie has one such marker and several scenes after it, which is fritz2 exactly. A
## landing 451 frames early is not a landing. Note before changing it that landing
## `LEAD_IN` before an `endstage` init instead runs that init with `ppl`, `foes`, `mnv`
## and `advance` unassigned, which is what `stage8water@f982` above shows costs a
## 70-frame jump to `gameover` — so the rule exists for a reason and both arms are wrong
## for this container.
##
## ### hatul2's stage chain: the mechanism is in the scripts, and nothing drove it
##
## The sweep left open whether one pass runs `hatul2`'s stages in sequence. The container
## answers it: `wlkrightintersects` — a walk handler, not a frame script — does
## `stage = stage + 1`, scrolls `movwho` by 30 pixels per step, places the cat for the new
## stage and calls `go(marker(1))`, all behind `sprite 15 intersects 5`; `wlkleftintersects`
## is the mirror with `stage - 1` and `go(marker(-1))`. So the stages *are* one contiguous
## chain walked by reaching the edge of the screen, not eight independently addressed
## screens, and `stage = 9` is the win.
##
## **Not driven, and the budget is why.** Three obstacles, each measured rather than
## assumed: the key driver rotates Space/Left/Right/Down/Up so the cat's net displacement
## is ~0 and it never reaches sprite 5; `--play stage2 --ticks 8000 --verbose` walks
## f219..f236, drowns into `stage2water` at f772 and parks in `gameover` f1050..f1093
## without ever visiting f298; and `stage1psila`, the one scene landed before `newgame`,
## stops after 668 frames on this file's own painted-everything break. Driving the chain
## needs a held direction key rather than a rotation, which is a change to `_press` and
## `press_keys` and not a longer run.
##
## ### show.dir is not 2,402 frames of animation, and it does run
##
## It was ruled not-a-minigame from its static shape, and the derivation agrees — no
## scenes, correctly. What it is is a **click-driven quiz**: `clknum` numbers the
## questions, four `on mouseUp` handlers spell `go("clk" & clknum & "a".."d")`, a
## `badpoint` field scores the wrong ones, and each question's frame script holds on
## `if not soundBusy(1)`. So the question "do its 2,402 frames run cleanly" is not a
## question about a linear show.
##
## Entering it the way `mainmenu.dir` does (`go(1, "show.dir")`) and letting it run plays
## **6 frames of 2,402**: `liveness_sweep --only show.dir` and `film_loop_nesting --file
## show.dir --ticks 12000` independently report f0..f5, `go`/`marker` and nothing else
## reached, and `film loops {}`. That is the movie's own opening hold, and
## `tools/hotspots.gd --file show.dir --frame 1` says what is on it: three sprites, a
## 640x480 background and two 102x30 buttons at (1,1) and (1,37), both clickable. Channel
## 2 is the exit (`go(1, "mainmenu.dxr")`) and channel 3 is the start — and a sweep that
## clicks in channel order takes the exit, which is why nothing had ever seen the show.
##
## Clicked, it plays. `--do "*=ch3;+2500=wait"` reaches the `clk1` marker at f59 and
## settles on f64, with **393 loop draws and 1,143 child draws** (ch7 carries `1:25`, the
## nested child of the `1:29` parent `docs/bugs-closed.md` records for this container),
## 284 `soundBusy` polls, 299 `exitFrame`s run, **0 unbound builtins, no Lingo error, no
## sprite skipped**, and four answer buttons `ch51..ch54` eligible — the first question,
## waiting. 2,514 ticks for 63 frames is the speech gate setting the pace, so the
## remaining ~2,338 frames are behind fourteen answer clicks and roughly fourteen times
## that wall clock. **Answered for the frames a click reaches, and not measured beyond
## them**; the next step is a `--do` chain of `clk<N>` to an answer channel, not a longer
## wait.
##
## Which of the two film-loop harnesses already covers this container, settled by running
## them rather than by reading their headers, because reading them gave the wrong answer.
## `film_loop_cast.gd` **does**. A bare run sweeps the config's default and answers about
## piposh2's 61 movies, which is `AGENTS.md`'s measured-zero trap exactly and is what made
## this look like a gap — but the tool takes `--root` through `Args`/`DirectorPaths` like
## every other survey here, and `gate.sh`'s `ALL` carries it **twice**, the second entry
## being `film_loop_cast:--root@piposh-dream`: 52 movies including this one, 918 indexed
## children in 1,373 loops, 5 checks green. `film_loop_nesting.gd` **does not**. It
## defaults to COMEIN, and `--file show.dir --index 0 --ticks 12000` fails all four of its
## checks for want of a subject rather than for a defect — the movie holds at f0..f5, so
## the painter never reaches the `1:29` parent and there is nothing for the assertions to
## be about. The played entry above would give it one.

const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerFile := preload("res://director/director_file.gd")
const CastTable := preload("res://director/director_cast_table.gd")
const Score := preload("res://director/director_score.gd")
const Labels := preload("res://director/director_labels.gd")
const FilmLoopView := preload("res://scenes/preview/film_loop_view.gd")
const Geometry := preload("res://scenes/preview/sprite_geometry.gd")
const Interaction := preload("res://scenes/preview/interaction.gd")

## How many score ticks apart the synthetic arrow presses are. Three, for
## `film_loop_restart.gd`'s measured reason: a press per tick holds the playhead on the
## frame that arms the throw and nothing is ever thrown.
const PRESS_EVERY := 3
## How far before its span a walk-in scene is dropped. Two frames, so the movie plays
## the span's own first frame -- which is where the `starter` reset and the speech gate
## live -- rather than starting inside it.
const LEAD_IN := 2

const LOOP_TYPE := 2

## Mac virtual key code -> Godot keycode, the inverse of `director_keys.gd`'s own table.
const MAC_TO_GODOT := {
	49: KEY_SPACE, 123: KEY_LEFT, 124: KEY_RIGHT, 125: KEY_DOWN, 126: KEY_UP,
	36: KEY_ENTER, 48: KEY_TAB, 51: KEY_BACKSPACE, 53: KEY_ESCAPE,
	0: KEY_A, 11: KEY_B, 8: KEY_C, 2: KEY_D, 14: KEY_E, 3: KEY_F, 5: KEY_G,
	4: KEY_H, 34: KEY_I, 38: KEY_J, 40: KEY_K, 37: KEY_L, 46: KEY_M, 45: KEY_N,
	31: KEY_O, 35: KEY_P, 12: KEY_Q, 15: KEY_R, 1: KEY_S, 17: KEY_T, 32: KEY_U,
	9: KEY_V, 13: KEY_W, 7: KEY_X, 16: KEY_Y, 6: KEY_Z,
	18: KEY_1, 19: KEY_2, 20: KEY_3, 21: KEY_4, 23: KEY_5, 22: KEY_6, 26: KEY_7,
	28: KEY_8, 25: KEY_9, 29: KEY_0,
}

## `puppetSprite N, 1` and `puppetSprite(N, 1)` are the same call; Director's
## parentheses are optional on a command. The flag is captured rather than assumed
## because the release form is what separates a scene's init from its exit.
const PUPPET := "(?i)puppetsprite\\s*\\(?\\s*([^,()]+?)\\s*,\\s*([^,()]+?)\\s*\\)?\\s*(?:\\n|$)"
## `set the member of sprite <chan> to <rhs>` and its `memberNum` spelling.
const SET_MEMBER := "(?i)set\\s+the\\s+member(num)?\\s+of\\s+sprite\\s+(\\(?[^\\n]+?\\)?)\\s+to\\s+([^\\n]+)"
## `sprite(<chan>).member = <rhs>`, the same assignment in the dot spelling.
const DOT_MEMBER := "(?i)sprite\\s*\\(\\s*([^\\n]+?)\\s*\\)\\s*\\.\\s*member(num)?\\s*=\\s*([^\\n]+)"
## `member(<id>[, <lib>])` on the right-hand side of either.
const MEMBER_OF := "(?i)member\\s*\\(\\s*([^,()]+?)\\s*(?:,\\s*([^,()]+?)\\s*)?\\)"
## `the number of member "name" [of castLib N]` — the other way a script names a
## member, and the one `rating/blatack1.dir` uses at six sites. A name is a *better*
## reference than a number, because a number is per cast and a name is what the
## author typed; `Cast.number_of` resolves it in the library named, or in the
## script's own where none is.
const NUMBER_OF := "(?i)the\\s+number\\s+of\\s+member\\s+\"([^\"]+)\"(?:\\s+of\\s+castlib\\s+([^\\s]+))?"
## A closed idle loop: the frame sends the playhead back to its own marker.
const HOLDS := "(?i)go\\s*(?:to\\s*)?\\(?\\s*(?:marker\\s*\\(\\s*0\\s*\\)|the\\s+frame)\\s*\\)?"
## A hold that a sound releases is not an idle loop, and this is the whole of the
## difference. COMEIN's speech gate is
##
##     if not soundBusy(1) then go(marker(1)) else go(marker(0))
##
## which matches `HOLDS` exactly and yet leaves on its own the moment the line of
## speech ends. Counting it made this file report a click entry for `krupnik` (f448)
## and `sue` (f586) and then admit it could find no hotspot over either -- which is
## the honest failure of a wrong rule rather than a missing behaviour. A loop only a
## sprite can leave is one with no sound gate in it.
const SOUND_GATED := "(?i)soundbusy"
## A behaviour that answers the mouse and moves the playhead is the way out of one.
const MOUSE_GO := "(?i)^\\s*on\\s+mouse(up|down)\\b"
## `set the keyDownScript to "westdown"`, naming the handler a scene reads its controls
## through. The EMPTY form is deliberately not matched: it is how a scene *ends*.
const KEY_INSTALL := "(?i)set\\s+the\\s+key(?:down|up)script\\s+to\\s+\"([^\"]+)\""
const KEYCODE_TEST := "(?i)the\\s+keycode\\s*=\\s*([0-9]+)"
const KEYCODE_CASE := "(?i)case\\s+the\\s+keycode\\s+of"

var _verbose := false
var _show_source := false
## Channels `--play` must not click, on top of the ones `_hotspots` derives. See
## `_live_hotspots` for why a derived set is not enough.
var _avoid := {}


func _init() -> void:
	var args := Args.parse()
	_verbose = Args.flag(args, "verbose")
	_show_source = Args.flag(args, "source")
	for text in Args.text(args, "avoid", "").split(",", false):
		_avoid[int(text)] = true

	var paths = Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root" % Paths.CONFIG_PATH)
		quit(1)
		return
	if Args.flag(args, "all"):
		_sweep(paths)
		quit(0)
		return
	var rel := Args.text(args, "file", str(paths.boot_movie))

	var f := ContainerFile.new()
	if not f.open(paths.resolve(rel)):
		print("cannot open %s under %s" % [rel, paths.root])
		quit(1)
		return
	var table = CastTable.new()
	if not table.open(f, paths):
		print("no cast in %s" % rel)
		f.close()
		quit(1)
		return
	var ids: Array = f.ids_of("VWSC")
	if ids.is_empty():
		print("%s has no score" % rel)
		f.close()
		table.close()
		quit(1)
		return
	var score = Score.new()
	if not score.parse(f.read_chunk(ids[0])):
		print("%s: score will not parse" % rel)
		f.close()
		table.close()
		quit(1)
		return
	var labels = Labels.new()
	var label_ids: Array = f.ids_of("VWLB")
	if not label_ids.is_empty():
		labels.parse(f.read_chunk(label_ids[0]))

	print("root       : %s" % paths.root)
	print("movie      : %s  %d frames, %d markers, %d score intervals" % [
		rel, score.frame_count, labels.markers.size(), score.intervals().size()])

	var cover := _coverage(score)
	var runs := _runs(cover)
	# The census before the derivation, because it decides which rules the derivation
	# is allowed to use: the dressing fallback is gated on this movie mentioning
	# `puppetSprite` nowhere. Printed in the order it always was, which is why the
	# call moved and the `print` did not.
	var puppets := _puppet_sites(table, cover)
	var may_dress := int(puppets["mention"]) == 0
	var scenes := _scenes(table, score, labels, cover, runs, may_dress)
	print("covered    : %d of %d frames, in %d contiguous run(s)" % [
		cover.size(), score.frame_count, runs.size()])
	print("puppetting : %d frame script(s) mention puppetSprite — %d claim a channel," % [
		int(puppets["mention"]), int(puppets["claim"])]
		+ " %d release one" % int(puppets["release"]))
	# Not one per scene in general: `rating/blatack1.dir` has 5 claiming frames in 3
	# runs, because one fight re-arms its channels partway through. The scene count is
	# the run count, so a run with two claims is one scene and the first claim is its
	# init -- which the per-scene report says outright rather than averaging away.
	print("claims     : %d frame(s) claim a channel" % scenes["claim_sites"])
	print("scenes     : %d run(s) hold an init — %d claiming, %d dressing" % [
		scenes["list"].size(), int((scenes["by_rule"] as Dictionary)["claim"]),
		int((scenes["by_rule"] as Dictionary)["dress"])])
	print("rules      : %s" % ("the dressing fallback is ON — no covered frame script"
		+ " here mentions puppetSprite" if may_dress
		else "the dressing fallback is OFF — this movie puppets, so a claim is the"
			+ " discriminator"))
	print("")

	var hit := 0
	for scene in scenes["list"]:
		if _report(scene, table, score, labels, cover):
			hit += 1

	print("=".repeat(78))
	print("summary")
	print("  %-10s %-7s %-8s %-20s %-18s %s" % [
		"scene", "init", "rule", "channels claimed", "film loops", "loops that nest"])
	for scene in scenes["list"]:
		var loops: Array = []
		var nests: Array = []
		for key in scene["elements"]:
			var el: Dictionary = scene["elements"][key]
			if int(el["type"]) != LOOP_TYPE:
				continue
			loops.append(int(el["id"]))
			if not (el["loop_children"] as Array).is_empty():
				nests.append(int(el["id"]))
		loops.sort()
		nests.sort()
		print("  %-10s %-7s %-8s %-20s %-18s %s" % [
			str(scene["name"]), "f%d" % int(scene["init"]), _rule_word(scene),
			str(scene["claimed"]), str(loops),
			"none" if nests.is_empty() else str(nests)])
	print("")
	print("  %d of %d scene(s) assign a film loop that has a film-loop child."
		% [hit, scenes["list"].size()])
	print("  Those, and only those, drew nothing inside the inner loop before the")
	print("  nested-loop recursion in film_loop_view.gd:paint_loop landed.")

	var play := Args.text(args, "play", "")
	if play == "":
		f.close()
		table.close()
		print("")
		print("  (--play <scene>, or --play all, enters them and says what drew)")
		quit(0)
		return

	print("")
	print("=".repeat(78))
	print("played")
	for scene in scenes["list"]:
		if play != "all" and str(scene["name"]) != play:
			continue
		await _play(rel, scene, table, Args.number(args, "ticks", 4000),
			Args.flag(args, "no-input"))
	f.close()
	table.close()
	quit(0)


## Every container of the root in counts, and nothing else.
##
## **It is a before-and-after in one run**, which is the reason it exists. The
## dressing rule fires only where `mention` is 0, so a container with any
## `puppetSprite` in a covered frame script cannot move: its `claimed` column is
## exactly what this file reported before the rule existed, and `dressed` is
## everything the rule added. A reader who wants to know whether the fallback
## over-widened does not have to take the argument on trust or stash the code —
## the two columns are side by side, per container, over a whole root.
##
## `gated` is the recall the gate gives up on purpose: for a movie that *does*
## puppet, the number of its runs that would have derived a dressing init had the
## gate not been closed. For `piposh-dream/COMEIN.dir` that number is the movie's
## ending screens, and the argument for the gate is that they are not games.
##
## One root per process, because `--root` beats `Paths.load_config`'s `force_root`
## and a sweep that fought it would report six copies of one corpus.
## `paths.containers()` lists the `.cst` files too, and a container with no score
## has no frame scripts and nothing to derive; those are counted and skipped rather
## than fatal, because quitting on the first one reports the first movie of a root.
func _sweep(paths) -> void:
	var rels: Array[String] = paths.containers()
	print("root       : %s" % paths.root)
	print("containers : %d listed under the root" % rels.size())
	print("")
	print("  %-30s %7s %5s %8s %6s %8s %8s %6s" % [
		"container", "frames", "runs", "mention", "claim", "claimed", "dressed",
		"gated"])
	var totals := {"movies": 0, "skipped": 0, "claimed": 0, "dressed": 0, "gated": 0,
		"moved": 0}
	for rel in rels:
		var f := ContainerFile.new()
		if not f.open(paths.resolve(rel)):
			totals["skipped"] = int(totals["skipped"]) + 1
			continue
		var ids: Array = f.ids_of("VWSC")
		if ids.is_empty():
			totals["skipped"] = int(totals["skipped"]) + 1
			f.close()
			continue
		var table = CastTable.new()
		var score = Score.new()
		if not table.open(f, paths) or not score.parse(f.read_chunk(ids[0])):
			totals["skipped"] = int(totals["skipped"]) + 1
			table.close()
			f.close()
			continue
		totals["movies"] = int(totals["movies"]) + 1
		var cover := _coverage(score)
		var runs := _runs(cover)
		var puppets := _puppet_sites(table, cover)
		var may_dress := int(puppets["mention"]) == 0
		var claimed := 0
		var dressed := 0
		var gated := 0
		for run in runs:
			var found := _init_of(table, cover, run, may_dress)
			if str(found["rule"]) == "claim":
				claimed += 1
			elif str(found["rule"]) == "dress":
				dressed += 1
			elif not may_dress and str(_init_of(table, cover, run, true)["rule"]) == "dress":
				gated += 1
		totals["claimed"] = int(totals["claimed"]) + claimed
		totals["dressed"] = int(totals["dressed"]) + dressed
		totals["gated"] = int(totals["gated"]) + gated
		if dressed > 0:
			totals["moved"] = int(totals["moved"]) + 1
		if _verbose or claimed > 0 or dressed > 0 or gated > 0:
			print("  %-30s %7d %5d %8d %6d %8d %8d %6d" % [
				str(rel).left(30), int(score.frame_count), runs.size(),
				int(puppets["mention"]), int(puppets["claim"]),
				claimed, dressed, gated])
		table.close()
		f.close()
	print("")
	print("  %d movie(s) with a score, %d container(s) skipped (no score, or will not"
		% [int(totals["movies"]), int(totals["skipped"])] + " parse)")
	print("  %d scene(s) by a claiming init — the count before the dressing rule"
		% int(totals["claimed"]))
	print("  %d scene(s) by a dressing init, in %d movie(s), each of which reported"
		% [int(totals["dressed"]), int(totals["moved"])] + " 0 before")
	print("  %d run(s) refused by the gate: they dress, in movies that puppet"
		% int(totals["gated"]))
	print("  (rows with nothing in any of the three columns are omitted; --verbose"
		+ " prints them)")


## Enter one scene the way the movie does, and report what reached the painter.
##
## The two entries are the two the derivation found, and nothing else is tried. What
## is read back afterwards is the painter's own record and never a field written from
## here: `_textures` is the decode cache keyed by `Geometry.texture_key`, so an
## element's key appearing in it means the painter asked the cast to decode that
## member at that size; `_loop_stats` is the paint tally, including the recursion's
## own `nested loop drawn` and `nested children offered`; and the live membership *and
## position* of a channel come through `lingo_sprite_prop`, which is what a script would
## read.
##
## **Three signals per channel, printed apart on purpose**: which members it held, where
## it stood, and — on the `signals` line — which of the two changed. Membership alone
## was the whole of this sampler, and a scene whose visible behaviour is a sprite walking
## measures as dead on that instrument. See the header's `fritz2.dir` section for the row
## that cost, and `_note_position` for the absent-channel trap the position read has to
## get past.
##
## `_last_member` is deliberately not touched. It is the painter's record of what it
## painted and `tools/update_stage.gd` uses it as a probe that `updateStage` paints
## inside a handler, so writing it from a harness makes that entry assert nothing.
func _play(rel: String, scene: Dictionary, table, ticks: int, no_input: bool) -> void:
	var run: Array = scene["run"]
	print("-".repeat(78))
	print("scene      : %s" % str(scene["name"]))

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview.call("lingo_go_movie", rel, null)
	for i in 8:
		await process_frame
	if preview.get("_score") == null:
		print("  ENTERED  : no — no score loaded for %s" % rel)
		preview.queue_free()
		return

	# The frame record and the paint baseline are opened *before* the entry, because the
	# settle frames below are frames of the run and the record has to be able to hold
	# them. That is the whole of the `init ran` fix; see `_note_frame`.
	var frames: Dictionary = {}
	# What the painter had already parsed when the init first ran. **The cache is
	# cumulative and the score places film loops of its own**, so "in `_loops`" is not
	# by itself evidence that a *scene* drew its element: `doc` and `poz` both have
	# 187..189 painted at their span's first frame, before their init has run, because
	# the score puts them on channels there. Without this baseline the run stopped after
	# one frame with all three loops "painted" and the init never reached -- a pass that
	# proved nothing, and exactly the shape `film_loop_nesting.gd`'s population guard
	# exists to refuse.
	var baseline: Dictionary = {}

	var entry := str(scene["entry"])
	var clicking := entry.begins_with("click")
	var how := ""
	var at := 0
	var centre := Vector2.ZERO
	if clicking:
		# Inside the idle span, a few frames short of the frame that jumps back, so the
		# score is genuinely looping when the press lands.
		var hold := int(entry.split("f")[1].split(" ")[0])
		at = maxi(0, hold - 5)
		centre = _centre_of(entry)
		how = "clicked (%d, %d) from f%d, inside the idle span" % [
			int(centre.x), int(centre.y), at]
	else:
		at = int(scene["land"])
		how = "playhead put at f%d, %s" % [at, str(scene["land_by"])]
	preview.set("_index", at)
	# **These eight frames are recorded, and that is the `init ran` fix.** The landing is
	# `LEAD_IN` before the init on purpose, so the playhead crosses the init *here*,
	# before the sampler's first pass -- and a record that opened at the first pass could
	# not hold the one frame the whole question is about. The two entries share one settle
	# loop rather than a copy each for the same reason: a frame recorded on one path and
	# not the other would make the answer depend on how the scene was entered.
	for i in 8:
		await process_frame
		_note_frame(preview, frames, baseline, int(scene["init"]))
	if clicking:
		preview.call("route_press", centre)
		preview.call("route_release", centre)
	print("  entered  : %s" % how)

	# The elements this scene is expected to put on a channel, and the channels the
	# init claimed. Both come from the static half rather than from the run.
	var want: Dictionary = {}
	for key in scene["elements"]:
		want[str(key)] = int(scene["elements"][key]["type"])
	var alive: Dictionary = {}   # channel -> {member: times seen visible}
	# channel -> where it stood, over the frames that offered it. Membership and
	# position are kept apart all the way to the print, because a scene that swaps a
	# member and a scene that moves a sprite are two different claims about what the
	# movie did and one used to stand in for both.
	var positions: Dictionary = {}
	# Every channel the sampler ever watched, so a channel that was watched and never
	# became visible is a row that says so rather than a row that is missing.
	var watched: Dictionary = {}
	# Channels the engine reports as puppeted at some point in the run, accumulated
	# rather than read once: they are claimed *by* the init, so a set taken at the
	# landing is empty, and a channel handed back later still belongs in the report.
	var runtime: Dictionary = {}
	# Sampler passes, i.e. score frames the sampler ran on.
	var samples := 0
	var reached: Dictionary = {} # "lib:id" -> the first texture key it decoded under
	var last := -1
	var since := 0
	var on_channel: Dictionary = {}
	var spent := 0
	var left_for := ""
	var here_movie := str(preview.call("movie_name"))
	var pressed := 0
	var clicks := {}
	# The keys this scene's own primary handlers test, or none for a control run. Left and
	# Right were hardcoded here, which is right for COMEIN and wrong for five of the six
	# other minigames in this title: `westup` fires on space, `mazekey` reads all four
	# arrows, and `planeup` reads nothing else at all.
	var press_keys: Array = [] if no_input else (scene["keys"] as Array)
	for tick in ticks:
		await process_frame
		spent = tick + 1
		# **Stop if a click took the movie somewhere else.** The scene's own back-to-the-menu
		# button is excluded by name where it is a sprite behaviour, but `hex1.dir` keeps one
		# as a *cast* script and the click descent answers for it exactly as it does for a
		# board piece. Carrying on would sample another movie's channels under this scene's
		# name, and the frame numbers would silently be someone else's.
		if str(preview.call("movie_name")) != here_movie:
			left_for = str(preview.call("movie_name"))
			break
		var here := int(preview.call("current_frame"))
		_note_frame(preview, frames, baseline, int(scene["init"]))
		if here != last:
			last = here
			since += 1
			if since >= PRESS_EVERY and not press_keys.is_empty():
				since = 0
				pressed += 1
				_press(preview, press_keys[pressed % press_keys.size()])
			# A mouse scene is driven with the mouse, every score frame and on every live
			# hotspot at once. `eat.dir`'s plate only passes while the hungry guest's own
			# counter reads 4 or less -- a five-frame window on one of nine channels -- so a
			# rotation loses the game by construction and a key-only driver reports a scene
			# whose every control is a click as one where nothing changed. It is faster than
			# a player, and a scene that answers only under it is worth saying so about.
			if press_keys.is_empty() and not no_input:
				for channel in _live_hotspots(preview, scene):
					var at3 := _centre_of_channel(preview, int(channel))
					if at3 == Vector2.ZERO:
						continue
					preview.call("route_press", at3)
					preview.call("route_release", at3)
					pressed += 1
					clicks[int(channel)] = int(clicks.get(int(channel), 0)) + 1
			# Sampled once per *score* frame and on every one of them, not only on the
			# rising edge of `visible`. The rising edge misses a channel that was
			# already dressed when the sampler first looked, which showed up as `doc`
			# reporting nothing but member 0 on all three lanes while the painter's own
			# loop cache held all three of its spears.
			# **Claimed *and* dressed, not claimed alone.** A scene's init claims one set of
			# channels and its handlers dress another, and the two need not agree -- the
			# per-scene report says so out loud ("handlers also dress %s, unclaimed") and
			# this sampler then ignored exactly the channels that line names. Measured on
			# `piposh-dream/fritz2.dir`: the scene at f273 claims `[1, 32]` and dresses
			# `[6]`, so 92 runs of its own `psyregb` key handler produced a channel table
			# identical to the `--no-input` control on both claimed channels and the scene
			# read as taking no input at all. It does -- `mnv` moves through 259 distinct
			# values against the control's 103. Sampling the union costs nothing and the two
			# kinds of evidence are still told apart below.
			# **Sampling the union was not enough, and this comment used to say it was**:
			# ch6 was the channel it added and ch6 reads member 337 in both runs. The
			# channel that shows the difference is **10**, which neither rule could name --
			# see the header's position section.
			# **And the channels the *run* puppeted, asked of the engine rather than
			# spelled.** The static scan can only watch a channel whose operand it could
			# bound, and `fritz2.dir`'s f273 init claims its four fighters with
			#
			#     ppl = [10, 11, 12, 13]
			#     repeat with i = 10 to 13
			#       puppetSprite(i, 1)
			#
			# so `_operand` reports `i` unbounded, `claimed` comes out `[1, 32]`, and the one
			# channel every handler in the scene reads and writes -- `sprite getAt(ppl, 1)`,
			# channel 10 -- was watched by nothing at all. The puppet flag is not derived
			# from anything: it is state the engine holds, so the run can be *asked* which
			# channels it took off the score rather than a regex being asked which channels
			# it can spell. That costs the static derivation nothing and cannot move it --
			# `_operand`, `_init_of` and the `--all` sweep are untouched, which is why this is
			# not the bare-loop-variable change the header defers.
			for channel in _puppeted_now(preview):
				runtime[int(channel)] = true
			var watching: Dictionary = {}
			for channel in scene["claimed"]:
				watching[int(channel)] = true
			for channel in (scene["assigned_channels"] as Dictionary):
				watching[int(channel)] = true
			for channel in runtime:
				watching[int(channel)] = true
			var watch_list: Array = watching.keys()
			watch_list.sort()
			# Which channels this frame is *offering*, which is the guard the position read
			# cannot do without. See `_note_position` for what an unguarded read answers.
			var offered: Dictionary = {}
			for value in preview.call("frame_sprites"):
				offered[int((value as Dictionary)["channel"])] = true
			samples += 1
			for channel in watch_list:
				watched[int(channel)] = true
				_note_position(preview, positions, int(channel),
					offered.has(int(channel)))
				if not bool(preview.call("lingo_sprite_prop", int(channel), "visible")):
					continue
				var member := int(preview.call(
					"lingo_sprite_prop", int(channel), "membernum"))
				var seen: Dictionary = alive.get(int(channel), {})
				seen[member] = int(seen.get(member, 0)) + 1
				alive[int(channel)] = seen
				# Which claimed channels an element was actually dressed onto, after
				# entry. This is the evidence that survives a loop the score has
				# already parsed: the cache cannot say who put it there, and a channel
				# holding the member can only be the scene's own assignment, because
				# `puppetSprite` has taken the channel off the score.
				#
				# The library comes from `the castLibNum of sprite` rather than being
				# assumed to be 1. A number alone is not a member reference -- that is
				# the one rule `scenes/preview/scripts.gd` exists to hold -- and a
				# hardcoded 1 here would make this evidence silently never match on a
				# title whose elements live in a linked cast, reporting zero rather than
				# failing, which is `scenes/preview/README.md`'s named failure mode.
				var ekey := "%d:%d" % [_lib(int(preview.call(
					"lingo_sprite_prop", int(channel), "castlibnum"))), member]
				if want.has(ekey):
					var where: Dictionary = on_channel.get(ekey, {})
					where[int(channel)] = true
					on_channel[ekey] = where
		for key in preview.get("_textures") as Dictionary:
			for ekey in want:
				if reached.has(ekey):
					continue
				if str(key).begins_with("%s:" % ekey):
					reached[ekey] = str(key)
		# Stopped on the answer rather than after a fixed window, and the reason is the
		# movie's own `random(5)`: the throw handler picks a lane per pass and only three
		# of five values throw at all, so which of a scene's three loops a bounded window
		# happens to see is a coin toss. Measured over two 3000-frame runs of all six
		# scenes, every element loop was painted in at least one and none in both --
		# `krup` showed 84 and 85 in the first and only 86 in the second. Waiting for the
		# set instead turns that into a difference in how long a run takes rather than a
		# difference in what it reports, which is `film_loop_nesting.gd`'s rule and the
		# same argument `gate.sh`'s header makes about `play_suspends`.
		# The init having run is half the condition. Painted-before-the-init is the
		# score's doing and says nothing about the scene.
		if frames.has(int(scene["init"])) and _all_painted(preview, want, on_channel):
			break

	var visited: Array = frames.keys()
	visited.sort()
	print("  pressed  : %d %s %s" % [pressed,
		"key(s)" if not press_keys.is_empty() else "click(s)",
		"(control run: nothing pressed)" if no_input
			else (str(scene["key_names"]) if not press_keys.is_empty()
				else "on channel(s) %s" % str(clicks))])
	print("  played   : %d process frame(s), %d distinct frame(s) f%s..f%s, %d sampler pass(es)"
		% [spent, visited.size(),
		str(visited[0]) if visited.size() > 0 else "?",
		str(visited[-1]) if visited.size() > 0 else "?", samples])
	if _verbose:
		print("  frames   : %s" % str(visited))
	# Occupancy, and the same set the line below prints. The eight process frames awaited
	# after the landing carry the playhead through the init -- that is what `LEAD_IN` is
	# for -- so a record that opened at the sampler's first pass could not contain it, and
	# `eat.dir`, whose init is its own frame 0, read `init ran: NO` on a run where it
	# demonstrably had. `_note_frame` records the settle frames too, so this reads a set
	# that holds every frame the playhead stood on since the landing.
	#
	# **Occupancy and not `here >= init`**, which is what "at or past" would have been and
	# would have been worse: a scene landed elsewhere in the movie is past its own init's
	# frame number from the first sample, and the answer would have been `yes` for every
	# scene whose init is behind the landing. A frame nobody stood on ran no `exitFrame`,
	# and a jump over the init is a jump over its script, so the frame the playhead
	# occupied is the only thing that answers this.
	var reached_init := frames.has(int(scene["init"]))
	if left_for != "":
		print("  LEFT     : a click sent the movie to %s; the run stops there" % left_for)
	print("  init ran : %s (f%d %s in the frames played)" % [
		"yes" if reached_init else "NO", int(scene["init"]),
		"is" if reached_init else "is NOT"])
	var chans: Array = watched.keys()
	chans.sort()
	for channel in chans:
		# Which of the three the channel is, because they are not the same evidence. A
		# claimed channel is off the score, so a member on it can only be this scene's
		# assignment; a dressed-but-unclaimed one is still shared with the score, and the
		# score may have put that member there. `puppeted` is the third and it is not a
		# shade of either: the engine reported the puppet flag set on a channel the static
		# scan could not spell, so the channel *is* off the score and calling it `dressed`
		# -- which is what a two-word label did to `fritz2`'s channel 10 -- states the
		# opposite of what the movie did.
		var label := "dressed"
		if (scene["claimed"] as Array).has(int(channel)):
			label = "claimed"
		elif runtime.has(int(channel)):
			label = "puppeted"
		if alive.has(int(channel)):
			var seen: Dictionary = alive[channel]
			var members: Array = seen.keys()
			members.sort()
			var parts: Array = []
			for member in members:
				parts.append("%d on %d frame(s)" % [int(member), int(seen[member])])
			print("  ch %-3d   : %-9s visible with %s" % [
				int(channel), label, ", ".join(parts)])
		else:
			print("  ch %-3d   : %-9s never visible" % [int(channel), label])
		print("             %-9s %s" % ["position",
			_position_words(positions.get(int(channel), {}))])
	# Now that the rows above cover every watched channel rather than only the ones that
	# became visible, this fires for a scene the sampler had nothing to watch at all --
	# no claim it could bound, no assignment, and no puppet flag anywhere in the run.
	if chans.is_empty():
		print("  channels : nothing to watch — %s (claimed), %s (dressed), and no channel"
			% [str(scene["claimed"]),
				str((scene["assigned_channels"] as Dictionary).keys())]
			+ " reported the puppet flag while the run played")
	# Which kind of evidence each row rests on, in one line, because that is the question
	# a reader of this table actually has. A row with a member change and no motion is a
	# member-swapping scene; a row with motion and one member is a moving one; a row with
	# neither is the row that used to be the *whole* table for `fritz2` and read as a dead
	# game. Compared against the `--no-input` control, not read alone: the score swaps and
	# moves sprites of its own, and only the difference between the two runs is the player.
	var swapped: Array = []
	var shifted: Array = []
	var flat: Array = []
	for channel in chans:
		var members := int((alive.get(int(channel), {}) as Dictionary).size())
		# `steps` and not the size of the point set, because a channel that returns to
		# where it started has one point and moved twice. This line is the one that gets
		# quoted, so it reads the number that means "it moved on this run".
		var steps := int((positions.get(int(channel), {}) as Dictionary).get("steps", 0))
		if members > 1:
			swapped.append(int(channel))
		if steps > 0:
			shifted.append(int(channel))
		if members <= 1 and steps == 0:
			flat.append(int(channel))
	print("  signals  : member change on ch %s; motion on ch %s; neither on ch %s"
		% [str(swapped), str(shifted), str(flat)])
	var els: Dictionary = scene["elements"]
	var keys: Array = els.keys()
	keys.sort_custom(func(a, b): return int(els[a]["id"]) < int(els[b]["id"]))
	# Two different questions, because a film loop is *painted* and a bitmap is
	# *decoded*. A type-2 member never reaches `_textures` at all -- `_texture_for` is
	# bitmap-and-shape only, which is the whole origin of the bug this survey exists
	# beside -- so asking the texture cache about a loop answers "never" for a loop that
	# drew perfectly. `_loops` is the painter's parse cache, keyed `"lib:id"`, and a key
	# in it means `paint_loop` opened that member to draw it.
	var painted: Dictionary = preview.get("_loops")
	for key in keys:
		var el: Dictionary = els[key]
		if int(el["type"]) == LOOP_TYPE:
			var chans_of: Array = (on_channel.get(str(key), {}) as Dictionary).keys()
			chans_of.sort()
			var verdict := "never painted — not in the painter's loop cache"
			if painted.has(str(key)):
				verdict = "PAINTED"
				if baseline.has(str(key)):
					verdict += " (the score had parsed it before the init too)"
			verdict += ", dressed onto ch %s after the init" % str(chans_of) \
				if not chans_of.is_empty() else ", never dressed onto a claimed channel"
			print("  %-9s: %-9s %-14s %s" % [str(key), "filmLoop",
				('"%s"' % str(el["name"])).left(14), verdict])
			for kid in el["loop_children"]:
				var inner: Array = kid["children"]
				print("             nested %s %s: %d of %d of its own children reached the"
					% [str(kid["key"]),
						"PAINTED" if painted.has(str(kid["key"])) else "NOT painted",
						_decoded(preview, inner), inner.size()]
					+ " texture cache")
			continue
		print("  %-9s: %-9s %-14s %s" % [str(key), str(el["type_name"]),
			('"%s"' % str(el["name"])).left(14),
			("DECODED, texture key %s" % str(reached[key])) if reached.has(key)
				else "no texture key — never decoded"])
	var stats: Dictionary = preview.get("_loop_stats")
	var stat_keys: Array = stats.keys()
	stat_keys.sort()
	for key in stat_keys:
		print("  tally    : %-34s %d" % [str(key), int(stats[key])])
	preview.queue_free()
	await process_frame


## Note that the playhead is standing on this frame, and snapshot the painter's parse
## cache the first time that frame is the scene's init.
##
## Called from the settle loop *and* from the sampler, which is the only reason it is a
## function. `init ran` used to be a flag the sampler set on `here == init`, and the
## sampler's first pass is eight process frames after the landing: the landing is
## `LEAD_IN` before the init, so the playhead crosses the init inside those eight and
## the flag was answering about a window that begins after the frame it asks about.
## Measured on `piposh-dream/fritz2.dir` `actionbegins@f254` -- landing f252, first
## sampled frame f256, `init ran : NO` about an init whose `puppetSprite` the same run
## reports the interpreter reaching.
##
## The baseline is captured here rather than at the call site so it cannot drift from the
## frame it is a baseline *for*: it is what `_loops` held when the playhead first stood
## on the init, and taking it a pass later would count the init's own paints as the
## score's.
##
## **The record is complete rather than a sample, and that is the engine's property and
## not this file's luck.** `frame_loop.gd:tick` takes at most one score step per engine
## tick and keeps no queue behind it (its own "One score step per tick at most", measured
## against `Score::update`), so `_index` changes at most once per process frame and a
## caller that looks once per process frame sees every value it takes.
##
## So a gap in the printed frame list is the *movie* jumping and not this missing a look,
## and the first run after the fix is the worked example: `actionbegins@f254` records
## f252, f254, f255.. and no f253, because f252's own frame script (`3:2`) is
## `if not soundBusy(1) then go(marker(1))` and `marker(1)` from there is `actionbegins`
## at f254. f253 ran no `exitFrame` and belongs out of the set.
func _note_frame(preview: Node, frames: Dictionary, baseline: Dictionary,
		init: int) -> void:
	var here := int(preview.call("current_frame"))
	var first := here == init and not frames.has(init)
	frames[here] = true
	if not first:
		return
	for key in preview.get("_loops") as Dictionary:
		baseline[str(key)] = true


## Which channels this movie has taken off the score, right now.
##
## Asked of the engine and not of the scripts. `puppetSprite` sets a flag the preview
## holds per channel, and `the puppet of sprite N` is the read for it, so the run knows
## something the static scan cannot: `fritz2.dir` claims channels 10..13 inside a
## `repeat with i = 10 to 13`, and a bare loop variable is exactly the operand
## `_operand` refuses to bound.
##
## Enumerated over `_overrides` because that is where the flag lives -- one entry per
## channel any script has touched -- rather than over a channel range, which would be
## both a per-frame scan of a hundred-odd channels and the kind of number this file has
## none of. `frame_sprites` is the wrong enumeration for the same reason it is the right
## guard below: a channel puppeted while the score had nothing for it carries an empty
## record and never reaches that list (`sprite_state.gd:with_puppets`), so asking it
## would drop precisely the channels a script invented.
func _puppeted_now(preview: Node) -> Array:
	var out: Array = []
	for number in preview.get("_overrides") as Dictionary:
		if int(preview.call("lingo_sprite_prop", int(number), "puppet")) == 1:
			out.append(int(number))
	return out


## Note where a channel is standing, into its running record.
##
## **Only ever called for a channel the frame offers**, and that guard is the whole
## reason this is a function rather than two lines at the call site. `channel.gd:read`
## answers from `EMPTY_CHANNEL` for a channel with no sprite record and no override, and
## `EMPTY_CHANNEL` has no `loch` or `locv` row, so the `get` default comes back: an
## absent channel reports (0, 0) and reads as a sprite parked at the stage origin, which
## is indistinguishable from one that is really there and really at the origin. The
## existing `visible` guard does **not** exclude it -- `EMPTY_CHANNEL`'s own `visible`
## is `1` -- which is why this file's channel table has always been able to carry a row
## reading `member 0` for a channel no frame ever had, and it is the trap
## `tools/puzzle_board.gd` has its own paragraph about.
##
## `frame_sprites` is the frame's own sprite list merged `with_puppets`, so presence in
## it is exactly the condition under which the read reaches the override table or the
## score rather than a default.
##
## Four numbers, and none of them is a boolean. The distinct *points* and the distinct
## values per axis, because a sprite that oscillates back to where it started visits few
## points and is really moving, and because the axis ranges are what say whether a
## fighter walked sideways (`locH -/+ 17`) or was knocked up and down (`locV -/+ 17`).
## And **`steps`, the number of samples on which the position differed from the one
## before it**, because the other three are *sets* and a set can be identical across two
## runs that moved very differently: `fritz2`'s ch11 walks the same 17-pixel grid between
## the same two constrained ends whether or not a key is pressed, so its point set and
## both its ranges match its own control exactly and only how *often* it moved does not.
## A set answers "can this channel move at all"; `steps` answers "did it move on this
## run", and the second is the one an input claim needs.
##
## `watched` is the denominator and it is per channel rather than the run's own sample
## count, because a channel found at runtime joins the watch list when the init puppets
## it. Counting its gap against the whole run would report a sprite as undrawn for
## frames on which nothing was asking about it. `steps` is not normalised against it and
## must be read beside it: a run that stops early because `_all_painted` fired has fewer
## samples to move on.
##
## **The gap this leaves, stated rather than left to be found: the sampler runs once per
## score-frame transition**, so a handler that moves a sprite and calls `updateStage`
## several times inside one held frame contributes one sample. That is how a Director
## movie animates without the score (`scenes/preview/README.md`), and it is the next
## instance of exactly the class of blind spot this function was added for. Neither
## `fritz2.dir` nor `hatul2.dir` is that shape -- both move on `exitFrame` -- so it does
## not touch the numbers in the header.
func _note_position(preview: Node, positions: Dictionary, channel: int,
		offered: bool) -> void:
	var spot: Dictionary = positions.get(channel, {
		"watched": 0, "drawn": 0, "steps": 0, "last": "", "points": {}, "h": {}, "v": {}})
	spot["watched"] = int(spot["watched"]) + 1
	positions[channel] = spot
	if not offered:
		return
	var h := int(preview.call("lingo_sprite_prop", channel, "loch"))
	var v := int(preview.call("lingo_sprite_prop", channel, "locv"))
	var here := "%d,%d" % [h, v]
	spot["drawn"] = int(spot["drawn"]) + 1
	if str(spot["last"]) != "" and str(spot["last"]) != here:
		spot["steps"] = int(spot["steps"]) + 1
	spot["last"] = here
	(spot["points"] as Dictionary)[here] = true
	(spot["h"] as Dictionary)[h] = true
	(spot["v"] as Dictionary)[v] = true


## One channel's position record, as a sentence.
##
## An empty record is a channel no frame ever offered, and it says so rather than
## printing a position, for `_note_position`'s reason: the only position available for
## such a channel is a default, and a default that looks like a measurement is worse
## than a gap that says it is one.
static func _position_words(spot: Dictionary) -> String:
	if spot.is_empty() or int(spot["drawn"]) == 0:
		return "not read — no frame offered this channel (0 of %d sample(s))" % [
			0 if spot.is_empty() else int(spot["watched"])]
	var hs: Array = (spot["h"] as Dictionary).keys()
	var vs: Array = (spot["v"] as Dictionary).keys()
	hs.sort()
	vs.sort()
	var points: Dictionary = spot["points"]
	var drawn := "%d of %d sample(s) drawn" % [int(spot["drawn"]), int(spot["watched"])]
	if points.size() == 1:
		return "STILL at (%d, %d) on %s" % [int(hs[0]), int(vs[0]), drawn]
	return "MOVED %d time(s) over %d point(s) on %s," % [
			int(spot["steps"]), points.size(), drawn] \
		+ " h %d..%d (%d distinct), v %d..%d (%d distinct)" % [
			int(hs[0]), int(hs[-1]), hs.size(), int(vs[0]), int(vs[-1]), vs.size()]


## Has every film loop the scene assigns reached the painter's parse cache?
##
## Only the loops. A bitmap element may legitimately never be decoded -- COMEIN's
## `1:87` blank is assigned onto channels that are hidden at the time, and
## `_effective` answers `{}` for a hidden sprite, so the painter never asks for it --
## and waiting for it would spend the whole ceiling on every scene.
func _all_painted(preview: Node, want: Dictionary, on_channel: Dictionary) -> bool:
	var painted: Dictionary = preview.get("_loops")
	var loops := 0
	for key in want:
		if int(want[key]) != LOOP_TYPE:
			continue
		loops += 1
		if not painted.has(str(key)) or not on_channel.has(str(key)):
			return false
	return loops > 0


## How many of a list of `"lib:id"` members the painter asked the cast to decode.
func _decoded(preview: Node, members: Array) -> int:
	var hit := {}
	for key in preview.get("_textures") as Dictionary:
		for member in members:
			if str(key).begins_with("%s:" % str(member)):
				hit[str(member)] = true
	return hit.size()


## The click point out of the entry line the derivation wrote, so the played half and
## the static half cannot disagree about where the hotspot is.
func _centre_of(entry: String) -> Vector2:
	var re := RegEx.create_from_string("centre \\((-?[0-9]+), (-?[0-9]+)\\)")
	var hit := re.search(entry)
	if hit == null:
		return Vector2.ZERO
	return Vector2(int(hit.get_string(1)), int(hit.get_string(2)))


## Which visible channels the engine's own click descent would send a `mouseUp` to on this
## frame, minus the ones that leave the movie. Asked of `interaction.gd:script_for_click`
## rather than derived, so what is clicked is what a click reaches.
##
## `_hotspots` derives the leaves-the-movie set from **sprite behaviours** only, and it says
## so; a back-to-the-menu button kept as a *cast* script is invisible to it and the click
## descent answers for one exactly as it does for a game piece. Measured on
## `piposh-dream/hex2.dir`: ch90's `CastScript 306` ends the run on `mainmenu.dir` after seven
## clicks, so the scene's own outcome frames can never be reached and criterion 4 fails for a
## reason that is this file's rather than the engine's. `--avoid` is the manual half, for the
## channels a scan cannot find.
func _live_hotspots(preview: Node, scene: Dictionary) -> Array:
	var out: Array = []
	var sprites: Array = preview.call("frame_sprites")
	for value in sprites:
		var raw: Dictionary = value
		var channel := int(raw["channel"])
		if (scene["avoid_channels"] as Array).has(channel) or out.has(channel):
			continue
		if _avoid.has(channel):
			continue
		if (preview.call("_effective", raw) as Dictionary).is_empty():
			continue
		var answer: Array = Interaction.script_for_click(preview, channel, sprites)
		if answer.size() < 2 or (answer[0] as Dictionary).is_empty():
			continue
		if str(answer[1]) != "sprite":
			continue
		out.append(channel)
	return out


## The middle of what a channel is drawing, so a click lands on the artwork rather than on
## the corner of a score rect a swapped member does not fill.
func _centre_of_channel(preview: Node, channel: int) -> Vector2:
	for value in preview.call("frame_sprites"):
		var raw: Dictionary = value
		if int(raw["channel"]) != channel:
			continue
		var live: Dictionary = preview.call("_effective", raw)
		if live.is_empty():
			return Vector2.ZERO
		var rect: Rect2 = preview.call("_sprite_rect", live)
		return rect.get_center()
	return Vector2.ZERO


func _press(preview: Node, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	preview.call("_dispatch_key", down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	preview.call("_dispatch_key_up", up)


## One scene, printed. True when it assigns a loop that nests.
func _report(scene: Dictionary, table, score, labels, cover: Dictionary) -> bool:
	var run: Array = scene["run"]
	print("-".repeat(78))
	print("scene      : %s" % str(scene["name"]))
	print("  init     : f%d, marker %s, frame script %s — %s" % [
		int(scene["init"]), _marker_label(labels, int(scene["init"])),
		str(scene["init_script"]),
		"it claims a channel" if str(scene["rule"]) == "claim"
			else "it dresses a channel and claims none, and nothing in this movie"
				+ " mentions puppetSprite"])
	print("  span     : f%d..f%d (%d frames), scripts %s" % [
		int(run[0]), int(run[-1]), run.size(), str(scene["scripts"])])
	# Derived against claimed, compared here rather than left to the reader. The
	# docstring's argument for the `<int> + <var>` rule is that the movie corroborates
	# it -- the channels the arithmetic yields are the channels the init took off the
	# score -- and an argument from a comparison nobody runs is the stale-claim shape
	# `AGENTS.md` opens with.
	var claimed: Array = scene["claimed"]
	var assigned: Array = (scene["assigned_channels"] as Dictionary).keys()
	assigned.sort()
	var extra: Array = []
	for channel in assigned:
		if not claimed.has(int(channel)):
			extra.append(int(channel))
	if str(scene["rule"]) == "dress":
		# Not the same statement as the line below it, and the difference is the whole
		# of what the two rules mean. Every channel here is still the score's, so a
		# member seen on one is this scene's assignment *or* the score's own -- which
		# is why `--play`'s sampler labels these rows `dressed` and why an auto-puppet
		# reverting on a backward `go` was a bug the score could cause at all
		# (`docs/bugs-closed.md` 120).
		print("  dresses  : nothing claimed — channels %s are dressed by this run's"
			% str(assigned) + " scripts and stay the score's, as auto-puppets")
	else:
		print("  claims   : channels %s claimed by the init; %s dressed by its handlers — %s"
			% [str(claimed), str(assigned),
				"agree" if extra.is_empty()
					else "handlers also dress %s, unclaimed" % str(extra)])
	print("  markers  : %s" % str(_markers_in(labels, int(run[0]), int(run[-1]))))
	print("  exits to : %s" % str(scene["exits"]))

	var els: Dictionary = scene["elements"]
	var keys: Array = els.keys()
	keys.sort_custom(func(a, b): return int(els[a]["id"]) < int(els[b]["id"]))
	print("  elements : %d member(s) assigned onto %d channel(s)" % [
		keys.size(), (scene["assigned_channels"] as Dictionary).size()])
	var nests := false
	var shown := 0
	for key in keys:
		var el: Dictionary = scene["elements"][key]
		var chans: Array = (el["channels"] as Dictionary).keys()
		chans.sort()
		if not _verbose and shown >= 12:
			print("     ... and %d more (use --verbose)" % (keys.size() - shown))
			break
		shown += 1
		var what := str(el["type_name"])
		if int(el["type"]) == LOOP_TYPE:
			what = "filmLoop %d frames looping=%s" % [
				int(el["frames"]), str(el["looping"])]
		print("     %-9s %-34s on ch %-14s %s" % [
			"%d:%d" % [int(el["lib"]), int(el["id"])],
			"%s %s" % [what, ('"%s"' % str(el["name"])) if str(el["name"]) != "" else ""],
			str(chans), str(el["how"])])
		if int(el["type"]) != LOOP_TYPE:
			continue
		var kids: Array = el["loop_children"]
		if kids.is_empty():
			print("        children: %d, none a film loop" % int(el["child_count"]))
			continue
		nests = true
		for kid in kids:
			print("        NESTS   : child %s is a filmLoop, %d frames looping=%s%s"
				% [str(kid["key"]), int(kid["frames"]), str(kid["looping"]),
					(' "%s"' % str(kid["name"])) if str(kid["name"]) != "" else ""])
			print("                  its own children: %s" % str(kid["children"]))

	for note in scene["unbounded"]:
		print("  UNBOUND  : %s" % str(note))

	print("  entry    : %s" % str(scene["entry"]))
	# Printed beside the entry rather than inside it, because they are two different
	# statements and one used to carry the other's number: the entry says *how* a player
	# gets in, and this says where `--play` puts the playhead to reproduce it. When
	# `_entry` spelled a frame of its own the two drifted apart the moment `_landing`
	# changed, and a survey whose static half and played half disagree about the frame is
	# a survey nobody can quote.
	print("  landing  : f%d, %s" % [int(scene["land"]), str(scene["land_by"])])
	if _show_source:
		for key in scene["sources"]:
			print("  --- script %s" % str(key))
			for line in str(scene["sources"][key]).split("\n"):
				print("      %s" % line)
	return nests


## Frame -> the narrowest frame-script interval covering it.
##
## `scenes/preview/scripts.gd:for_frame`'s rule, carried rather than called: that
## function takes the preview node and resolves through `host._script_in_lib`, so a
## static pass cannot use it. The main channel's own script slot is deliberately
## *not* consulted — this asks which frames a script *runs on as a span*, and the
## per-frame slot answers a different question that has no span to make a run out
## of.
func _coverage(score) -> Dictionary:
	var out := {}
	for interval in score.intervals():
		if str(interval["kind"]) != "frame":
			continue
		var span := int(interval["end"]) - int(interval["start"])
		var entry := {
			"lib": _lib(int(interval["script_cast_lib"])),
			"member": int(interval["script_member"]),
			"span": span,
		}
		for frame in range(int(interval["start"]), int(interval["end"]) + 1):
			if out.has(frame) and int(out[frame]["span"]) <= span:
				continue
			out[frame] = entry
	return out


## The covered frames as maximal contiguous runs.
func _runs(cover: Dictionary) -> Array:
	var frames: Array = cover.keys()
	frames.sort()
	var out: Array = []
	var run: Array = []
	for frame in frames:
		if not run.is_empty() and int(frame) != int(run[-1]) + 1:
			out.append(run)
			run = []
		run.append(int(frame))
	if not run.is_empty():
		out.append(run)
	return out


## How many distinct covered-frame scripts mention `puppetSprite`, split by what
## they do with it. Printed beside the scene count because the gap between the two
## is the whole of the discriminator this file rests on: a movie where every mention
## is a claim is a movie where the discriminator has not been exercised, and the
## reader should know that before trusting the scene count.
func _puppet_sites(table, cover: Dictionary) -> Dictionary:
	var out := {"mention": 0, "claim": 0, "release": 0}
	var seen := {}
	var re := RegEx.create_from_string(PUPPET)
	for frame in cover:
		var key := "%d:%d" % [int(cover[frame]["lib"]), int(cover[frame]["member"])]
		if seen.has(key):
			continue
		seen[key] = true
		var hits := re.search_all(_source(table, int(cover[frame]["lib"]),
			int(cover[frame]["member"])))
		if hits.is_empty():
			continue
		out["mention"] = int(out["mention"]) + 1
		var claims := false
		for hit in hits:
			if str(hit.get_string(2)).strip_edges() == "1":
				claims = true
		out["claim" if claims else "release"] = int(out["claim" if claims else "release"]) + 1
	return out


## Every scene in the movie: a covered run holding an init, with the members its own
## scripts assign. `may_dress` is the movie-level gate on the second init rule, and
## the caller reads it off `_puppet_sites`.
func _scenes(table, score, labels, cover: Dictionary, runs: Array,
		may_dress: bool) -> Dictionary:
	var claim_sites := 0
	var by_rule := {"claim": 0, "dress": 0}
	var list: Array = []
	for run in runs:
		var found := _init_of(table, cover, run, may_dress)
		claim_sites += int(found["claim_sites"])
		if int(found["frame"]) < 0:
			continue
		by_rule[str(found["rule"])] = int(by_rule[str(found["rule"])]) + 1
		list.append(_scene(table, score, labels, cover, run, int(found["frame"]),
			str(found["script"]), found["claimed"], str(found["rule"])))
	_disambiguate(list)
	return {"list": list, "claim_sites": claim_sites, "by_rule": by_rule}


## One run's init, and which of the two rules found it. `frame` is -1 for a run that
## holds neither, and `claim_sites` counts every claiming frame in the run rather than
## only the init -- `rating/blatack1.dir` re-arms its channels partway through a fight.
##
## The claim rule is tried first and always, and the dressing rule only where the
## caller says the movie never mentions `puppetSprite` at all, so the two can never
## disagree about a run: a movie with a claim in it has the fallback switched off
## whole, which is what makes this a fallback and keeps COMEIN's ending screens out.
func _init_of(table, cover: Dictionary, run: Array, may_dress: bool) -> Dictionary:
	var puppet := RegEx.create_from_string(PUPPET)
	var out := {"frame": -1, "script": "", "claimed": [] as Array, "rule": "",
		"claim_sites": 0}
	for frame in run:
		var lib := int(cover[frame]["lib"])
		var member := int(cover[frame]["member"])
		var src := _source(table, lib, member)
		var mine := {}
		for hit in puppet.search_all(src):
			# The flag, not the call. `, 0` hands the channel back, and six of
			# COMEIN's twelve sites are that -- the losing screens.
			if str(hit.get_string(2)).strip_edges() != "1":
				continue
			for channel in _operand(str(hit.get_string(1)), src)["values"]:
				mine[int(channel)] = true
		if mine.is_empty():
			continue
		out["claim_sites"] = int(out["claim_sites"]) + 1
		if int(out["frame"]) >= 0:
			continue
		var chans: Array = mine.keys()
		chans.sort()
		out["frame"] = int(frame)
		out["script"] = "%d:%d" % [lib, member]
		out["claimed"] = chans
		out["rule"] = "claim"
	if int(out["frame"]) >= 0 or not may_dress:
		return out
	for frame in run:
		var lib2 := int(cover[frame]["lib"])
		var member2 := int(cover[frame]["member"])
		if not _dresses_a_channel(_source(table, lib2, member2)):
			continue
		out["frame"] = int(frame)
		out["script"] = "%d:%d" % [lib2, member2]
		out["rule"] = "dress"
		break
	return out


## Does this script put a member on a sprite channel? The same two assignment
## spellings `_scene` reads a scene's elements out of, asked as a yes or no --
## reused rather than restated, so a spelling this file learns to read becomes a
## spelling it can derive an init from in the same edit.
##
## Presence, not a resolved channel. `puzzle.dir` dresses `sprite gsnum` inside a
## `repeat`, and a rule that required the channel to be bounded would find nothing
## there and reintroduce the false negative it exists to fix.
func _dresses_a_channel(src: String) -> bool:
	if src == "":
		return false
	if RegEx.create_from_string(SET_MEMBER).search(src) != null:
		return true
	return RegEx.create_from_string(DOT_MEMBER).search(src) != null


## `claimed` or `dressed`, which is how every line of the report says which rule
## found the scene. The same two words `_play` labels a sampled channel with.
static func _rule_word(scene: Dictionary) -> String:
	return "claimed" if str(scene["rule"]) == "claim" else "dressed"


## One scene, filled in: its scripts, the members they assign, and its entry.
func _scene(table, score, labels, cover: Dictionary, run: Array, init: int,
		init_script: String, claimed: Array, rule: String) -> Dictionary:
	var set_re := RegEx.create_from_string(SET_MEMBER)
	var dot_re := RegEx.create_from_string(DOT_MEMBER)
	var member_re := RegEx.create_from_string(MEMBER_OF)
	var named_re := RegEx.create_from_string(NUMBER_OF)

	# The scene's own scripts: the frame scripts covering its frames, and the
	# sprite behaviours whose interval overlaps them. Both can assign a member, and
	# leaving the behaviours out would report a scene's elements as whatever half of
	# them the frame scripts happen to own.
	var scripts := {}
	var order: Array = []
	for frame in run:
		var key := "%d:%d" % [int(cover[frame]["lib"]), int(cover[frame]["member"])]
		if not scripts.has(key):
			scripts[key] = [int(cover[frame]["lib"]), int(cover[frame]["member"])]
			order.append(key)
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		if int(interval["end"]) < int(run[0]) or int(interval["start"]) > int(run[-1]):
			continue
		var key2 := "%d:%d" % [
			_lib(int(interval["script_cast_lib"])), int(interval["script_member"])]
		if scripts.has(key2):
			continue
		scripts[key2] = [_lib(int(interval["script_cast_lib"])),
			int(interval["script_member"])]
		order.append(key2)

	var elements := {}
	var assigned := {}
	var unbounded: Array = []
	var sources := {}
	for key in order:
		var lib: int = scripts[key][0]
		var member: int = scripts[key][1]
		var src := _source(table, lib, member)
		if src == "":
			continue
		sources[key] = src
		var found: Array = []
		for hit in set_re.search_all(src):
			found.append([str(hit.get_string(2)), str(hit.get_string(3)),
				str(hit.get_string(1)) != ""])
		for hit in dot_re.search_all(src):
			found.append([str(hit.get_string(1)), str(hit.get_string(3)),
				str(hit.get_string(2)) != ""])
		for pair in found:
			var chan_expr: String = pair[0]
			var rhs: String = pair[1]
			var is_num: bool = pair[2]
			var chans: Dictionary = _operand(chan_expr, src)
			if (chans["values"] as Array).is_empty():
				unbounded.append("%s: channel `%s` unbounded" % [key, chan_expr.strip_edges()])
				continue
			# A name reference is resolved before any arithmetic is looked for, because
			# it is not arithmetic: `the number of member "dotdot" of castLib 1` is a
			# lookup, and treating it as an unbounded expression loses a member the
			# container can name exactly.
			var named := named_re.search(rhs)
			if named != null:
				var named_lib := lib
				if str(named.get_string(2)) != "":
					var nl: Dictionary = _operand(str(named.get_string(2)), src)
					if not (nl["values"] as Array).is_empty():
						named_lib = _lib(int((nl["values"] as Array)[0]))
				var by_name := _number_of(table, named_lib, str(named.get_string(1)))
				if by_name <= 0:
					unbounded.append("%s: member \"%s\" names nothing in cast %d"
						% [key, str(named.get_string(1)), named_lib])
					continue
				_record(table, elements, assigned, named_lib, by_name, chans["values"],
					"named \"%s\"" % str(named.get_string(1)))
				continue
			# `member(id, lib)` names its own library; `memberNum` and a bare number
			# do not, and the loop's own library is then the answer.
			var wrapped := member_re.search(rhs)
			var id_expr := str(wrapped.get_string(1)) if wrapped != null else rhs
			var lib_expr := str(wrapped.get_string(2)) if wrapped != null else ""
			if wrapped == null and not is_num:
				# `set the member of sprite N to <not a member() call>` is a member
				# reference this scan cannot follow -- a variable holding one, say.
				unbounded.append("%s: member expression `%s` is not a member() call"
					% [key, rhs.strip_edges()])
				continue
			var ids: Dictionary = _operand(id_expr, src)
			if (ids["values"] as Array).is_empty():
				unbounded.append("%s: member `%s` unbounded" % [key, id_expr.strip_edges()])
				continue
			var target_lib := lib
			if lib_expr != "":
				var libs: Dictionary = _operand(lib_expr, src)
				if not (libs["values"] as Array).is_empty():
					target_lib = _lib(int((libs["values"] as Array)[0]))
			var how := "literal" if str(ids["how"]) == "" else str(ids["how"])
			for id in ids["values"]:
				_record(table, elements, assigned, target_lib, int(id),
					chans["values"], how)

	var exits := _exits(sources, labels, int(run[0]), int(run[-1]))
	var hotspots := _hotspots(table, score, run)
	var landing := _landing(labels, run, init)
	var controls := _controls(table, _source(table, int(init_script.split(":")[0]),
		int(init_script.split(":")[1])))
	return {
		"name": _name_of(labels, init, exits),
		"land": int(landing["frame"]), "land_by": str(landing["why"]),
		"keys": controls["keys"], "key_names": controls["names"],
		"avoid_channels": hotspots["avoid"],
		"run": run, "init": init, "init_script": init_script, "rule": rule,
		"claimed": claimed, "scripts": order, "exits": exits,
		"elements": elements, "assigned_channels": assigned,
		"unbounded": unbounded, "sources": sources,
		"entry": _entry(table, score, cover, run, init),
	}


## Which channels of this scene a click must **not** go to: the ones whose behaviour names
## another container. Those are the way back to the menu, and clicking one ends the run on a
## screen that reads exactly like a freeze (`director-qa-playthrough`'s first named false
## finding).
##
## What a click *may* go to is not derived here, because the engine answers it better than a
## scan can. `interaction.gd:script_for_click` is the click descent itself, and it resolves
## the sprite's behaviour **or the live member's cast script** — which is where this title
## keeps its board games: `hex1.dir`'s pieces carry no behaviour at all and member 3's own
## cast script is the handler. A scan of `member["source"]` finds nothing for those, because
## a bitmap's cast script is a separate script member.
func _hotspots(table, score, run: Array) -> Dictionary:
	var mouse := RegEx.create_from_string(MOUSE_GO)
	var leaves := RegEx.create_from_string("(?i)\\.(dxr|dir)\"")
	var avoid := {}
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		if int(interval["end"]) < int(run[0]) or int(interval["start"]) > int(run[-1]):
			continue
		var src := _source(table, _lib(int(interval["script_cast_lib"])),
			int(interval["script_member"]))
		if src == "" or mouse.search(src) == null or leaves.search(src) == null:
			continue
		avoid[int(interval["channel"])] = true
	var list: Array = avoid.keys()
	list.sort()
	return {"avoid": list}


## Where to put the playhead for a walk-in entry, and why.
##
## **As late as the movie allows and never on the init**, which is two rules pulling in
## opposite directions and one answer.
##
## Landing on the init is the entry `AGENTS.md` forbids: the score's own arrival at that
## frame is what runs the `puppetSprite`s, and jumping there leaves a scene whose channels
## were never claimed. So `LEAD_IN` frames before it.
##
## Landing at the *span's* start -- which is what this file did -- is wrong in both
## directions. Too late for `MAZE1.dir`, which sets `psilot`, the lives its maze reads on
## every collision, in the frame script under its own `actionbegins` marker at f117 and
## arms the maze at f123: a landing at f121 runs the second and not the first, and a
## measured run then reported `psilot` unset for its whole length. Too *early* for
## `hex1.dir`, whose covered run reaches back into 70 frames of `soundBusy`-gated speech
## before the board's init at f202 -- real audio time, minutes of it -- so a 4,000-frame
## run landing at f127 never arrived at the init at all.
##
## The answer is the `action*` marker where the movie has one at or before the init (six of
## this title's minigames do, and it is the movie's own statement of where its game
## begins), else `LEAD_IN` before the init. `tools/cast_script_sprite.gd` reached the same
## number for `hex1` by hand and measured that it produces the same board as walking the
## whole intro.
func _landing(labels, run: Array, init: int) -> Dictionary:
	var action := -1
	var re := RegEx.create_from_string("(?i)action")
	for marker in labels.markers:
		var frame := int(marker["frame"])
		if frame > init or re.search(str(marker["name"])) == null:
			continue
		if frame > action:
			action = frame
	if action >= 0 and action < init:
		return {"frame": maxi(0, action - LEAD_IN),
			"why": "%d before the movie's own `action*` marker at f%d, and left to walk in"
				% [LEAD_IN, action]}
	return {"frame": maxi(0, init - LEAD_IN),
		"why": "%d before the init, and left to walk in" % LEAD_IN}


## Which keys a scene wants, read out of the primary key handlers its init installs.
##
## `set the keyUpScript to "westup"` names a handler; that handler's `the keyCode = N`
## tests and its `case the keyCode of` arms are the control scheme. The arms are only
## counted inside a `case` on `the keyCode` -- `westup` also has
## `case the memberNum of sprite ... of` whose arms are 36, 37 and 43, and counting those
## makes this report a gunfight played with Enter, L and Comma.
func _controls(table, init_source: String) -> Dictionary:
	var handlers := {}
	for hit in RegEx.create_from_string(KEY_INSTALL).search_all(init_source):
		handlers[str(hit.get_string(1))] = true
	var mac := {}
	for lib in (table.cast_libs as Dictionary).keys():
		var cast = table.cast_for(int(lib))
		if cast == null:
			continue
		for number in cast.member_numbers():
			var src := str(cast.member(int(number)).get("source", ""))
			if src == "":
				continue
			for name in handlers:
				var body := _handler_body(src, str(name))
				if body == "":
					continue
				for hit in RegEx.create_from_string(KEYCODE_TEST).search_all(body):
					mac[int(hit.get_string(1))] = true
				var in_case := false
				for line in body.split("\n"):
					if RegEx.create_from_string("(?i)^\\s*case\\b").search(line) != null:
						in_case = RegEx.create_from_string(
							KEYCODE_CASE).search(line) != null
						continue
					if RegEx.create_from_string("(?i)^\\s*end\\s+case").search(line) != null:
						in_case = false
						continue
					if not in_case:
						continue
					var arm := RegEx.create_from_string("^\\s*([0-9]+)\\s*:").search(line)
					if arm != null:
						mac[int(arm.get_string(1))] = true
	var codes: Array = mac.keys()
	codes.sort()
	var keys: Array = []
	var names: Array = []
	for code in codes:
		var godot: int = int(MAC_TO_GODOT.get(int(code), -1))
		if godot < 0:
			continue
		keys.append(godot)
		names.append(OS.get_keycode_string(godot))
	# No fallback. A scene whose init installs no primary key script is a scene with no
	# keyboard, and the empty list is what routes it to the mouse driver below: `eat.dir`
	# and the Hexxagon board are both mouse scenes, and an arrow-key default made this file
	# press keys nothing reads and then report that nothing changed.
	return {"keys": keys, "names": names}


## One handler's body out of a script's text, "" where the script has no such handler.
func _handler_body(src: String, name: String) -> String:
	var out: Array = []
	var inside := false
	var re := RegEx.create_from_string("(?i)^\\s*on\\s+%s\\b" % name)
	for line in src.split("\n"):
		if re.search(line) != null:
			inside = true
			continue
		if not inside:
			continue
		if RegEx.create_from_string("(?i)^\\s*on\\s+[a-z_]").search(line) != null:
			break
		if RegEx.create_from_string("(?i)^\\s*end\\s*$").search(line) != null:
			break
		out.append(line)
	return "\n".join(out)


## The markers this scene's own scripts leave for, and which of them are outside
## it: `go("fritzwin")` and `go("fritzend")` in the throw and collision handlers.
##
## Worth deriving because they are the only place in the container that **names the
## character** — the init's own marker is `return1`, which numbers the scenes and
## says nothing about whose game it is. A scene called `return5` and a scene called
## `hatuli` are the same finding and only one of them can be read.
func _exits(sources: Dictionary, labels, from: int, to: int) -> Array:
	var go := RegEx.create_from_string("(?i)go\\s*(?:to\\s*)?\\(?\\s*\"([^\"]+)\"")
	var seen := {}
	for key in sources:
		for hit in go.search_all(str(sources[key])):
			var name := str(hit.get_string(1))
			var frame := int(labels.labels.get(name.to_lower(), -1))
			if frame < 0 or (frame >= from and frame <= to):
				continue  # unresolvable, or a jump inside the scene's own span
			seen[name] = frame
	var out: Array = []
	for name in seen:
		out.append("%s f%d" % [str(name), int(seen[name])])
	out.sort()
	return out


## What to call a scene. Its init's marker where it has a name, and the longest
## common prefix of the names it exits to where those agree on one — which for
## COMEIN turns `return1` into `fritz`, because the scene leaves for `fritzend` and
## `fritzwin` and for nothing else.
func _name_of(labels, init: int, exits: Array) -> String:
	var stem := ""
	for entry in exits:
		var name := str(entry).split(" ")[0]
		if stem == "":
			stem = name
			continue
		var shared := 0
		while shared < stem.length() and shared < name.length() \
				and stem[shared] == name[shared]:
			shared += 1
		stem = stem.substr(0, shared)
	if stem.length() >= 3:
		return stem
	var marker := str(labels.marker_at(init))
	return marker if marker != "" else "f%d" % init


## Scenes that derived the same name are told apart by their init frame. Three of
## `rating/blatack1.dir`'s exit to the same marker and so earn the same stem, and a
## report with three rows called `egozdead` is a report nobody can quote from.
static func _disambiguate(list: Array) -> void:
	var tally := {}
	for scene in list:
		tally[str(scene["name"])] = int(tally.get(str(scene["name"]), 0)) + 1
	for scene in list:
		if int(tally[str(scene["name"])]) > 1:
			scene["name"] = "%s@f%d" % [str(scene["name"]), int(scene["init"])]


## One member landing on some channels, folded into the scene's element set.
func _record(table, elements: Dictionary, assigned: Dictionary, lib: int, id: int,
		channels: Array, how: String) -> void:
	var key := "%d:%d" % [lib, id]
	if not elements.has(key):
		elements[key] = _element(table, lib, id)
	for channel in channels:
		assigned[int(channel)] = true
		(elements[key]["channels"] as Dictionary)[int(channel)] = true
	if not (elements[key]["how"] as Array).has(how):
		(elements[key]["how"] as Array).append(how)


## A member number for a name, in one library. 0 where the cast has no such name.
func _number_of(table, lib: int, name: String) -> int:
	var cast = table.cast_for(lib)
	if cast == null:
		return 0
	return int(cast.number_of(name))


## One assigned member: what it is, and what is inside it if it is a film loop.
func _element(table, lib: int, id: int) -> Dictionary:
	var m: Dictionary = table.get_member(lib, id)
	var out := {
		"lib": lib, "id": id, "type": int(m.get("type", 0)),
		"type_name": str(m.get("type_name", "absent")),
		"name": str(m.get("name", "")), "how": [] as Array,
		"channels": {}, "frames": 0, "looping": false,
		"child_count": 0, "loop_children": [] as Array,
	}
	if int(m.get("type", 0)) != LOOP_TYPE:
		return out
	out["looping"] = bool(m.get("looping", true))
	# Through the preview's own entry point, so the nesting reported is the one the
	# painter walks rather than a second reading written here.
	var loop = FilmLoopView.open_loop(lib, m, table)
	if loop == null:
		return out
	out["frames"] = int(loop.frame_count)
	var seen := {}
	for i in loop.frame_count:
		for kid in loop.children(i):
			var kid_lib: int = FilmLoopView.child_lib(kid, lib, table)
			if kid_lib < 0:
				continue
			var kid_key := "%d:%d" % [kid_lib, int(kid["cast_id"])]
			if seen.has(kid_key):
				continue
			seen[kid_key] = true
			var cm: Dictionary = table.get_member(kid_lib, int(kid["cast_id"]))
			if int(cm.get("type", 0)) != LOOP_TYPE:
				continue
			var inner = FilmLoopView.open_loop(kid_lib, cm, table)
			var grandkids := {}
			if inner != null:
				for j in inner.frame_count:
					for gk in inner.children(j):
						var gk_lib: int = FilmLoopView.child_lib(gk, kid_lib, table)
						grandkids["%d:%d" % [gk_lib, int(gk["cast_id"])]] = true
			var names: Array = grandkids.keys()
			names.sort()
			(out["loop_children"] as Array).append({
				"key": kid_key, "name": str(cm.get("name", "")),
				"frames": 0 if inner == null else int(inner.frame_count),
				"looping": bool(cm.get("looping", true)),
				"children": names,
			})
	out["child_count"] = seen.size()
	return out


## How a player gets into this scene.
##
## An idle span is a closed loop of frames whose last frame's script sends the
## playhead back to the marker covering it, so nothing in the score can leave it
## and whatever does is a sprite behaviour. Where the run has such a frame *before*
## its init, the way in is a click; where it has none, the movie plays in on its
## own and the entry is the run's first frame.
func _entry(table, score, cover: Dictionary, run: Array, init: int) -> String:
	var holds := RegEx.create_from_string(HOLDS)
	var gated := RegEx.create_from_string(SOUND_GATED)
	var mouse := RegEx.create_from_string(MOUSE_GO)
	var at := -1
	for frame in run:
		if int(frame) >= init:
			break
		var src := _source(table, int(cover[frame]["lib"]), int(cover[frame]["member"]))
		if holds.search(src) != null and gated.search(src) == null:
			at = int(frame)
	if at < 0:
		return "walk in: no closed loop before f%d" % init

	# The span the loop covers: back to the marker the jump returns to, which is the
	# last covered frame before it that is not part of the same jump. The score's own
	# sprite intervals over that span are where the way out has to be.
	var span_from := at
	for interval in score.intervals():
		if str(interval["kind"]) != "sprite":
			continue
		if int(interval["end"]) < at or int(interval["start"]) > at:
			continue
		var lib := _lib(int(interval["script_cast_lib"]))
		var member := int(interval["script_member"])
		var src := _source(table, lib, member)
		if mouse.search(src) == null or not src.to_lower().contains("go"):
			continue
		var channel := int(interval["channel"])
		var rect := _rect_of(table, score, channel, at)
		span_from = int(interval["start"])
		return ("click: idle loop holds at f%d (%d:%d), left by ch %d behaviour %d:%d "
			% [at, int(cover[at]["lib"]), int(cover[at]["member"]), channel, lib, member]
			+ "on mouse -> go; sprite spans f%d..f%d, rect %s, centre (%d, %d)"
			% [int(interval["start"]), int(interval["end"]), str(rect),
				int(rect.get_center().x), int(rect.get_center().y)])
	return "click: idle loop holds at f%d but no mouse behaviour over it" % span_from


## A channel's stage rect on a frame, from the score's own record.
func _rect_of(table, score, channel: int, frame: int) -> Rect2:
	for sprite in score.frame(frame).get("sprites", []):
		if int(sprite["channel"]) != channel:
			continue
		var m: Dictionary = table.get_member(
			int(sprite["cast_lib"]), int(sprite["cast_id"]))
		return Geometry.stage_rect(sprite, m)
	return Rect2()


## What integers an operand can be, and how it was decided.
##
## A literal, or `<int> + <var>` in either order — in which case the variable's
## range is whatever the same handler compares it against. `if (x = 1) or (x = 2)`
## bounds `x` to 1 and 2, and `x = random(5)` contributes nothing because it is not
## a literal comparison. Loose about which of the two an author meant, because
## Lingo spells assignment and equality the same way and the union is the honest
## answer either way: an assignment of a literal is a value the variable takes, and
## a comparison against one is a value it is expected to take.
func _operand(expr: String, source: String) -> Dictionary:
	var text := expr.strip_edges()
	while text.begins_with("(") and text.ends_with(")"):
		text = text.substr(1, text.length() - 2).strip_edges()
	if text.is_valid_int():
		return {"values": [int(text)], "how": ""}
	var sum := RegEx.create_from_string(
		"(?i)^(?:([0-9]+)\\s*\\+\\s*([a-z_][a-z0-9_]*)|([a-z_][a-z0-9_]*)\\s*\\+\\s*([0-9]+))$")
	var hit := sum.search(text)
	if hit == null:
		return {"values": [] as Array, "how": "unbounded `%s`" % text}
	var base := int(hit.get_string(1) if str(hit.get_string(1)) != "" else hit.get_string(4))
	var name := str(hit.get_string(2) if str(hit.get_string(2)) != "" else hit.get_string(3))
	var offsets := _bounds(name, source)
	if offsets.is_empty():
		return {"values": [] as Array, "how": "unbounded `%s`" % text}
	var values: Array = []
	for offset in offsets:
		values.append(base + int(offset))
	return {"values": values, "how": "derived %d+%s, %s in %s" % [
		base, name, name, str(offsets)]}


## The literals a handler compares or assigns a name against, ascending.
func _bounds(name: String, source: String) -> Array:
	var re := RegEx.create_from_string(
		"(?i)(?<![a-z0-9_])%s\\s*=\\s*(-?[0-9]+)(?![0-9])" % name)
	var seen := {}
	for hit in re.search_all(source):
		seen[int(hit.get_string(1))] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## A member's Lingo text, or "". `director_cast.gd` puts it in `member["source"]`.
func _source(table, lib: int, member: int) -> String:
	if member <= 0:
		return ""
	var m: Dictionary = table.get_member(lib, member)
	return str(m.get("source", ""))


## The score writes a script's library raw; `scripts.gd:in_lib` normalises it.
## Missing this resolves the number in the wrong cast, where it finds a stranger.
func _lib(raw: int) -> int:
	return 1 if raw <= 0 or raw == 0xFFFF else raw


func _marker_label(labels, frame: int) -> String:
	for i in labels.markers.size():
		if int(labels.markers[i]["frame"]) != frame:
			continue
		var name := str(labels.markers[i]["name"])
		return "%d \"%s\"" % [i, name] if name != "" else "%d (unnamed)" % i
	return "none at this frame"


func _markers_in(labels, from: int, to: int) -> Array:
	var out: Array = []
	for marker in labels.markers:
		var frame := int(marker["frame"])
		if frame < from or frame > to:
			continue
		out.append("f%d %s" % [frame,
			str(marker["name"]) if str(marker["name"]) != "" else "(unnamed)"])
	return out
