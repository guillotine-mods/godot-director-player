extends SceneTree
## Open every movie a title ships and ask whether a player could get out of it.
##
##   godot --headless --path . --script tools/liveness_sweep.gd
##   godot --headless --path . --script tools/liveness_sweep.gd -- --root piposh-dream
##   godot --headless --path . --script tools/liveness_sweep.gd -- --limit 12
##   godot --headless --path . --script tools/liveness_sweep.gd -- --only ques.dir --click
##   godot --headless --path . --script tools/liveness_sweep.gd -- --only mainmenu.dir --scenes
##
##   --root R      the corpus (`DirectorPaths` honours it; default the config's)
##   --only S      visit only containers whose path contains S
##   --limit N     visit at most N containers, in sorted order (0 = all)
##   --start N     skip the first N containers, so two runs can split a corpus
##   --budget-ms N stop starting new containers after N ms of wall clock (0 = none)
##   --ticks N     unexcused score ticks to watch each container for (default 120)
##   --window N    score ticks a verdict is read over (default 60)
##   --settle N    score ticks to let a container open in (default 24)
##   --click       after the watch, click each eligible sprite and watch again
##   --clicks N    how many hotspots to try per container (default 3)
##   --ff N        ceiling for the adaptive fast-forward rate (default 120)
##   --speech N    mix every sound N times faster, so a `soundBusy` wait costs a
##                 fraction of the wall clock it used to (default 8; 1 is real time)
##   --scenes      after the container watch, enter every marker of the movie in
##                 turn and judge each one
##   --scene S     with --scenes, walk only markers whose name contains S
##   --scene-ticks N unexcused ticks bought per scene (default 90)
##   --strict      make the low-confidence `trap` verdict a failure too
##   --verbose     print a line for every container, not only the findings
##
## ## Why this exists
##
## `gate.sh` tests mechanisms one at a time. Nothing walks the corpus asking the
## player's question -- *am I stuck?* -- and the bug that prompted this file is
## the proof: opening the save screen in `piposh-dream` made the playhead
## ping-pong for ever between `ques.dir` frame 803 (the panel, 4 sprites) and
## `Saves.dir` frame 27 (0 sprites, a black stage), because a `play done` return
## re-ran the caller's `exitFrame`, which contained the `play` that had parked it.
## The screen alternated with black for as long as it was open and was never
## clickable.
##
## Nothing in the gate could have caught that. `movie_churn` counts movie changes
## but only on the boot movie, driving `_advance` synthetically. `playhead_escape`
## watches a reachable set but only after one scripted click in one room of one
## title, and it reads `_index` alone -- a number that means nothing across a
## movie boundary. `skip_state` asserts the movie can still move, and a ping-pong
## moves every single step. **No harness had ever looked at a second container of
## a second title at all.**
##
## ## The hard part is not finding stuck movies, it is not crying wolf
##
## `go to the frame` is how every room in every one of these titles stands still.
## A room waiting for a click is a playhead that never moves, on a frame whose
## `exitFrame` jumps to itself, with nothing on the clock -- which is, read
## naively, indistinguishable from a hang. A detector that reports those reports
## 300 rooms and is worth less than nothing.
##
## Four things are treated as an *answer* to "why is the playhead not moving",
## and a tick that has any of them clears the window rather than annotating it,
## so a trap has to be `--window` **consecutive** unexplained score ticks:
##
##   * `FrameClock.hold_reason()` is non-empty -- a tempo delay, a transition, a
##     palette effect, the tempo channel's wait-for-click or wait-for-sound;
##   * the movie is **polling `soundBusy`** and a sound is in fact playing --
##     Director's wait-for-speech idiom, and the one `playhead_escape` names;
##   * Director's `pause` is in effect (`preview_lingo_host.playback_paused`), the
##     one hold that names no destination and stops the playhead outright;
##   * the movie called `quit`/`halt` (`stopped`), which is an ending, not a hang.
##
## **The `soundBusy` clause is a poll, not a mixer reading, and that distinction
## is the whole difference between a detector and a blank page.** "Some channel is
## busy" was the first rule, taken from `playhead_escape`, and measured against
## this corpus it excused *every tick of every movie*: these titles run background
## music, so a channel is busy from the first frame to the last and the sweep
## reported six movies as fully accounted for while looking at nothing. Director's
## own evidence that a movie is waiting for a sound is that it **asks** --
## `preview_lingo_host.reached["soundbusy"]` counts the calls -- so the excuse is
## granted for the ticks between two polls and not for a soundtrack.
##
## What is left after that is a playhead the engine cannot account for, and the
## verdicts below split it by **what is on the stage**, because that is the half
## `playhead_escape` does not look at and the half the reported bug lived in:
##
##   `parked`      one (movie, frame) for the whole window, and something is
##                 drawn on it. This is `go to the frame`. **Not a finding** --
##                 it is the single most common state in the corpus.
##   `blank-park`  the same, with **nothing drawn**. A black stage the playhead
##                 will not leave and no hold explains. There is no legitimate
##                 form of this.
## The three cycle verdicts below additionally require that the playhead **came
## back** to a state it had already left. A window holding two to four states is
## also what a playhead walking through those frames and parking on the last of
## them looks like, and that walk is not a finding; see `_read_window`.
##
##   `ping-pong`   two to four revisited states spanning **two or more movies**.
##                 The reported bug exactly. Two containers cannot be trading
##                 places for a reason the player is waiting on.
##   `blank-cycle` two to four revisited states in one movie, at least one of which
##                 draws nothing. The screen alternating with black.
##   `trap`        two to four revisited states in one movie, all of them drawn,
##                 **and nothing on any of them answers the mouse**. The
##                 `playhead_escape` shape (DAY1's `<character>clicktalk` pair).
##                 Still low confidence and still not a failure unless
##                 `--strict`, because the sweep drives no keyboard and a room
##                 that only a keystroke leaves is the same shape.
##   `sound-park`  the whole watch was excused by the `soundBusy` clause and the
##                 playhead never left four states. `reached` cannot say *which*
##                 channel was polled, so a loop waiting on a channel that never
##                 falls silent is excused for ever; this is that blind spot
##                 reported instead of hidden. **Not a failure** -- an
##                 uninterruptible cut scene is the same shape.
##
## ## Why `trap` needs a second source, and why that source is the mouse
##
## **The playhead alone cannot tell an authored idle loop from a confinement**, and
## every `trap` this file has ever reported was the former. `SACHROOM.dir` was a
## walk that parked (`docs/bugs-closed.md` 69, fixed by the arrivals rule below);
## nine `<character>clicktalk` pairs were two-frame loops on a cold entry
## (`bugs.md` 36); and `piposh-dream/puzzle.dir` is a 4x4 sliding puzzle whose
## `exitFrame` on the last frame of its four is `go("start")`, for ever, by
## design -- the very property `tools/puzzle_board.gd` is built on. All three are
## "two to four revisited drawn states with no hold", so no rule about *where the
## playhead went* can separate them. Widening the excuse to "a backward `go`
## happened during the window" would be worse than reporting them: a `play` is
## exactly what parked the `ques.dir`/`Saves.dir` bug this file was written from,
## so that excuse disables the detector for its founding case.
##
## What separates the two is not the playhead, it is **whether the player has
## anything to do**. Director gives a room three ways out -- the score, a click, a
## keystroke -- so a loop the score will not leave and that offers no click is one
## the player cannot leave either, and one that offers a click is a room *waiting*
## (`director-qa-playthrough`: "waiting for input is recurrence, not stillness").
## So the trap arm asks the engine's own `respondsToMouse` (§4.3, through
## `_responds_to_mouse`) and withholds the verdict when any state in the cycle
## carries an eligible sprite. Measured on the case above:
## `tools/click_eligibility.gd --root piposh-dream --file puzzle.dir` reports
## **13 of 13 frames** with at least one eligible sprite, 259 of 301 sprite
## records answering a click -- an independent reading, from a cold score walk
## rather than from this sampler.
##
## Three properties of that rule, each load-bearing:
##
##   * **It is granted per cycle, never per movie or per tick.** `ping-pong` and
##     `blank-cycle` are decided above the trap arm and are deliberately *not*
##     excused by it: two containers trading places is a finding whoever can be
##     clicked, and a frame drawing nothing is a black stage whoever can be
##     clicked. `_assert_rules` pins both with all-clickable windows, because an
##     excuse that reaches them is how this change would go wrong.
##   * **Eligibility is asked once per state, and only on a revisit.** See
##     `_watch`: the answer is cached per `(movie, frame)` and computed the second
##     time the playhead arrives there, so a movie walking through 120 frames pays
##     nothing and a movie in a four-state loop pays four questions. That is not
##     only cost -- asking it of every sprite of every sample cost a factor of nine
##     and aliased the sampler into blindness once already (see `_sample`).
##   * **An unprobed state reads as "not clickable", and that cannot invent a
##     finding.** A window only reaches the trap arm when it has strictly more
##     arrivals than states, which means it contains a revisit, which is exactly
##     where the probe fires -- so every window that can be called a trap carries
##     at least one real eligibility answer. Keep that ordering if this is ever
##     moved.
##
## What the rule does not claim is that the click *works*: eligibility says a
## sprite answers the mouse, not that its handler leads anywhere, and the sweep
## enters every container cold so a gate on a global may make every hotspot inert.
## A cycle cleared this way is therefore reported as a counted `idle loops` line
## rather than dropped silently, so a human can still look at the list.
##
## Two more findings come from outside the playhead:
##
##   `lingo`       the interpreter recorded an error while the movie ran --
##                 "step budget exhausted", a repeat that did not terminate,
##                 handler recursion, an unknown statement. `LingoInterpreter`
##                 clears `errors` at the start of every dispatch, so nothing in
##                 the port had ever read them during play; they are polled here
##                 on every process frame and accumulated. **This one is
##                 lossy and the reason is worth knowing before trusting a clean
##                 run**: `reset_steps` clears the list at the *start* of a
##                 dispatch, and one score step dispatches `idle`, `exitFrame`,
##                 `prepareFrame` and `enterFrame` back to back inside a single
##                 process frame -- so an error raised in any but the last of them
##                 is gone before this can look. What survives is what the last
##                 dispatch of each process frame recorded. A `lingo` finding is
##                 therefore real; the absence of one is not proof. Making it
##                 sound needs a durable sink in the interpreter, which is
##                 `bugs.md` territory rather than this tool's.
##   `no-open`     `go to movie` did not land on the container, or it loaded no
##                 score.
##
## **A blank verdict is withheld while a Movie-In-A-Window is open**, because the
## window is a separate node with its own playhead and the stage underneath it is
## legitimately bare. That exemption is the one place this file can be talked out
## of a finding, and it is narrow on purpose.
##
## ## How it is driven, and what that costs
##
## Real awaited process frames, never a synthetic tick loop: a `for i in N: tick()`
## advances the runtime's clock and not the audio server's, so every `soundBusy`
## guard holds for ever and every scene with speech in it reads as stuck
## (`bugs.md` 22, diagnosed wrong twice, and the reason the sound clause above is
## an excuse rather than an assertion).
##
## Real frames at 8 fps are slow -- measured headless, 7 score ticks a second, so
## one container would take 20 s and a corpus three quarters of an hour. So the
## sweep runs with the **fast-forward toggle** (`--ff`, default 30), which scales
## the delta the clock is told about and therefore the frames *and the holds*
## together, leaving the score's own rate untouched.
##
## The ceiling on that is **aliasing**, and it is the sampler's own failure mode:
## two score ticks between two samples turn a period-2 ping-pong into a constant,
## and the detector then reports the shape it exists to find as a healthy park.
## The clock takes at most one score step per process frame now -- it re-arms
## absolutely and drops what it could not afford, as `Score::updateNextFrameTime`
## does -- so a sampler that reads once per process frame can no longer skip a
## tick, and the stride below should read 1 throughout. It used to take four in
## one frame whenever the machine fell behind, which aliased whatever `--ff`
## said. The machinery is kept rather than deleted because the property it
## guards is the sampler's and not the clock's: a sample taken every *other*
## process frame would alias again, and a harness that can only be right while
## another file behaves is the shape this repo keeps being bitten by. Every
## sample carries the **stride** it was taken at
## and a sample that skipped a tick *clears the window* exactly as a hold does --
## so aliasing can cost a finding and can never invent one. What it cannot do is
## go unnoticed: the coverage (contiguously sampled ticks over ticks watched) is
## printed and asserted, because a sweep that saw a third of the movie and
## reported it clean is the dark-harness failure with extra steps. What coverage
## does **not** answer is how much *movie* was watched -- that is the section
## below, and trusting the one number for both questions is `bugs.md` 128.
##
## ## The watch is paid for in ticks a rule can be read over
##
## Sound is the one thing fast-forward cannot scale -- the mixer runs on the audio
## server's clock -- so a `soundBusy` wait takes as long as the sound does however
## fast the score runs. At `--ff 30` the score runs about 28 ticks a second while
## the mixer runs at one, so a four-second opening line -- 34 ticks at the movie's
## own authored rate -- costs about 115 ticks of watch.
##
## **`--ff` still cannot scale it and `--speech` now does**, through the audio
## server's own multiplier rather than the frame clock's; the section below this
## one is the measurement that made it necessary, and `SPEECH` is why it is a
## speed-up rather than a thirteenth excuse. Everything in the rest of this section
## stands: the budget still buys unexcused ticks, and the reason a sound wait is
## expensive has not changed, only how much of it there is to sit through.
##
## **That used to be charged to the same budget as a live tick**, and on a talkative
## title it was the whole budget. Measured over `piposh-dream` with
## `--click --strict --verbose`, at 52 movies in 371 s: 42 of the 52 ended their
## watch with a `wait for sound` hold on it, **19 of them held on every single
## watched tick**, and every one of the 52 read `ok`. `bugs.md` 128 measured the
## same command at 46 of 51 held, 39 of those for 100 or more of the 120 ticks and
## 22 for all 120, with 9 clicks landing across 51 poked movies -- the two runs
## differ because containers share one session and leak state in visit order, which
## is this file's second documented caveat, and they agree on the shape. Every
## excuse was granted correctly and every verdict was right; the watch simply never
## reached the frame the room's hotspots are on.
##
## So `--ticks` buys **unexcused** ticks -- exactly the ticks `_judge` builds a
## window out of, and the predicate is `_judgeable` in one place for all three
## readers of it. A held or skipped tick is watched, sampled, counted in the
## report and **not charged**, so what bounds a watch is `WATCH_CAP_MS`, which is
## what already bounded every art-heavy movie in this corpus. Two numbers say how
## that went and are printed every run: the `depth` line (unexcused ticks obtained
## per watch, and how many watches the wall-clock ceiling cut short) and
## `unjudged`.
##
## Two things this deliberately does not change. A hold still *clears* the window
## rather than annotating it, so nothing about what counts as a finding moved --
## only how long the sweep is willing to wait for one. And a skipped tick is
## uncharged and still clearing, so **aliasing can still cost a finding and can
## still never invent one**; `_assert_rules` pins that with the founding ping-pong
## every one of whose samples carries a stride of 2.
##
## What it does change is what `coverage` is for, and the split is worth stating
## because the old number was trusted for both halves while it could only ever
## answer one. Coverage is contiguously sampled ticks over ticks run: it answers
## **"did the sampler see the ticks that happened"**, which is the aliasing
## question, and it read 100% for the sweep above because a held tick is a sampled
## one. It was never a measure of how much *movie* was watched. That question is
## `unjudged`'s, and it is asked properly now: a movie whose longest run of
## judgeable ticks never reached `--window` is named, so a watch that spent its
## whole wall clock inside a cut scene reads as unlooked-at rather than as clean.
## Neither number is higher-is-better and neither substitutes for the other.
##
## ## What was eating the ceiling: the movie's own speech, and nothing else
##
## `bugs.md` 128 left `WATCH_CAP_MS` binding where `--ticks` used to, and the
## obvious next move -- raise the ceiling -- multiplies a corpus cost that was
## already 2.5x. So the cost was measured first, with `tools/scratch/watch_cost.gd`
## and with this sweep's own hold histogram, and it is not where the entry's
## remaining suspects put it.
##
## Over `piposh-dream`, `--click --strict --verbose` at the old `--ff 30`, 52 of 52
## movies in **974.8 s** (the entry's 946 s, reproduced), the 52 first watches
## sampled **19,177** score ticks and this is what they were:
##
##   | wait for sound | 15,435 | 80.5% |
##   | wait for click |    515 |  2.7% |
##   | transition     |     24 |  0.1% |
##   | pause          |      1 |     - |
##   | **judgeable**  |  3,202 | 16.7% |
##
## 3,202 is `depth`'s own figure to the tick. **Four fifths of the sweep's wall
## clock is spent watching the title talk.** It is not decode and it is not paint:
## the profiler puts 98-99% of every watch inside `await process_frame` and the
## sampler's own questions at about 1%, and on an idle machine the process loop
## ran at 117 frames a second -- 8.5 ms a frame -- while `--ff 30` drew 26 score
## ticks out of it.
##
## Sound is the one hold `--ff` cannot scale, because the mixer runs on the audio
## server's clock and not on the one the fast-forward multiplies. But that clock
## has a multiplier of its own: `AudioServer.playback_speed_scale`, which is what
## `--speech` sets. A `soundBusy` poll then retires N times sooner, every cue
## point inside the sound passes N times sooner in wall clock and at the same
## place in the sound, and the frame the movie moves on at is the frame it always
## moved on at.
##
## **It is a speed-up and not an excuse, and that is what makes it safe.** Every
## other mechanism in this file *forgives* a tick; this one makes the tick that
## was being forgiven arrive sooner. The movie runs the same handlers in the same
## order at the same frames, so a window read after a line of speech is a window a
## player also reaches -- later.
##
## Where it is unfaithful it is unfaithful in the conservative direction. At
## `--ff 120` against a corpus authored at 8-15 fps the score runs 8 to 15 times
## real time and speech runs 8, so the sweep still sits out proportionally *more*
## of a wait than the original did. Nothing is reached earlier in the movie's own
## time than the original reaches it, which is the direction that cannot invent a
## finding. `--speech 1` restores real time and is what to re-read a finding at.
##
## **What it bought, paired.** All 52 containers of `piposh-dream` with
## `--click --strict --verbose`, the two arms the same code and the same machine,
## `--ff 30 --speech 1` against the new defaults `--ff 120 --speech 8`. The control
## arm reproduces the pre-change baseline on every line it shares with it
## (974.8 s / mean 62 / 28 capped / 34 unjudged), which is what makes it a control:
##
##   |                                   | before   | after |
##   |-----------------------------------|----------|-------|
##   | wall clock                        | 984.9 s  | **869.2 s** |
##   | unexcused ticks watched           | 3,227    | **5,962** |
##   | mean depth, of the 120 asked      | 62       | **115** |
##   | watches that hit the 20 s ceiling | 28 of 52 | **3 of 52** |
##   | movies with no window at all      | 34 of 52 | **17 of 52** |
##   | **marker regions judged**         | **212 of 2,732** | **743 of 2,732** |
##   | marker regions entered            | 300      | **826** |
##   | findings                          | 0        | 0 |
##
## Nearly twice the depth and three and a half times the rooms, in *less* wall
## clock, and **the same verdicts** -- which is the row that says the speed-up did
## not change what the sweep is looking at. The same pair over the first twelve
## containers, run back to back on a contended machine, moved 476.3 s to 262.7 s
## and 42 regions to 244.
##
## The seventeen that still have no window are the dinner-table scenes, which are
## dialogue end to end: at `--speech 8` they now *move* (`dinner1.dir` went from 88
## states over 523 ticks to 419 over 430) and still never offer sixty consecutive
## unexcused ticks, because a line of speech lands every few ticks for the length
## of the scene. That is an honest reading of a cut scene and not a defect left
## over; what reaches those rooms is `--scenes`, which enters the markers *after*
## the dialogue directly.
##
## **What every absolute number above was measured on.** Two to six other headless
## Godot processes shared this machine for most of these runs, which is the
## condition `AGENTS.md` and this file's own last bullet both warn about, and it
## moved the frame time from 8.5 ms to as much as 530 ms. So the *ratios* here are
## the result -- the hold histogram, which is load-independent because a sound
## takes as long as it takes whatever the machine is doing, and the paired A/B
## below, where both arms ran back to back through the same contention. The wall
## clocks are this machine on that afternoon and are not a baseline anybody should
## compare a different day against; re-measure both arms rather than one.
##
## ## What this sweep does not cover
##
## Stated here rather than discovered later:
##
##   * **Containers are opened from the boot movie's session, not cold.** One
##     preview is booted and every container is reached with `lingo_go_movie`, the
##     same call the F12 picker makes. Globals the boot movie set are therefore in
##     scope, and globals a *room chain* would have set are not -- so a movie that
##     needs `globalday` still opens with it VOID. That is a real player path (the
##     picker) and it is not the only one; `playhead_escape --cold` documents the
##     same gap from the other end. `--via` is deliberately absent: making the
##     sweep walk each movie's own entry chain is the next tool, not this one.
##   * **State leaks between containers**, in visit order, because they share one
##     session. That is closer to play than a fresh boot per movie and it means a
##     finding is reproducible with `--only` *only if* the leak was not the cause.
##     Every finding therefore prints its own `--only` command, and one that does
##     not reproduce alone is itself a result worth having.
##   * **Only the stage playhead is watched.** A Movie-In-A-Window has its own,
##     and `movie_churn` is the only thing that looks at it.
##   * **Clicking is shallow.** `--click` presses eligible sprites one at a time
##     from the state the watch ended in, and never two in sequence, so a trap
##     three clicks deep into a dialogue is not reachable from here.
##   * **A movie that needs a keystroke is never woken.** `key_chain` and
##     `cannon_hit` drive keys; this drives none.
##   * **Every entry is cold, and `--scenes` makes that true per marker rather
##     than per container.** A marker reached by `go` has the movie open and the
##     globals the session has accumulated, and *not* whatever the room that
##     normally jumps there set on its way out. So a scene verdict is a lead for
##     `qa_walk`, never a filed bug, and it is reported outside the assertions for
##     that reason.
##   * **Nothing is asserted about what is drawn being *right*.** A frame that
##     draws fifteen sprites of the wrong artwork is `parked` and healthy here.
##   * **An art-heavy movie is watched for less movie than a light one, and a
##     loaded machine shortens every watch.** What bounds those movies is
##     `WATCH_CAP_MS` rather than `--ticks`: `piposh-dream`'s five `dinner` rooms
##     take 11-15 s to open and then fill the cap at about 3.3 score ticks a
##     second, against 30 on a light one. `--ff` does not fix it and neither does
##     standing the preloader down -- both measured, 95 to 101 ticks either way --
##     because the cost is the *paint*, not the decode-ahead.
##
##     Coverage stays honest, because what is sampled is sampled. What suffers is
##     the *window*: a watch that only ever reached 17 ticks cannot fill a
##     60-tick one, so no rule was ever read over that movie. The summary counts
##     those as `unjudged` and names them rather than letting them read as clean,
##     which is the difference between "we looked and it was fine" and "we did
##     not look". A run with many of them was measured on a busy machine and is a
##     run to repeat, not a result.
##
##     **Since the budget moved to unexcused ticks, that ceiling is the ordinary
##     bound rather than the exception**, so this bullet now describes most of the
##     corpus and not only its expensive rooms. The `depth` line is where a run
##     says how much movie it saw, and a loaded machine costs depth rather than
##     coverage -- the tick stream stays fully sampled either way.
##
##     **The paint reading above is about the `open`, and the `watch` is a
##     different question with a different answer.** Both are in the same seconds
##     column on the verbose line, which is how they came to be read as one cost.
##     Opening a `dinner` room is decode and paint; the twenty seconds after it
##     were four fifths `soundBusy`, which no amount of painting faster would have
##     bought back. See the section above.
##
## ## `visited: 52 of 52` was never a coverage figure, and now there is one
##
## A room in these titles is a **marker** and the frames under it are its
## animation, which is `director-qa-playthrough`'s rule and the reason the
## container is the wrong unit. `piposh-dream` ships 52 movies and declares
## **2,732 marker regions** across them; a sweep that opens each container and
## watches wherever its first frame parks has been reporting `visited: 52 of 52`
## over 52 of those 2,732, and the line reads like completeness.
##
## `6b42a128` is the same mistake with a number attached: a walk that played one
## scene per container reported eighteen day-2 scenes as covered when they had
## never been entered. So the `scenes` line counts regions, from the containers'
## own `VWLB` (`_marker_frames`), with the denominator read **before** the sweep
## starts -- a total that shrinks when a run is cut short is a total that always
## looks good -- and it separates three claims that are easy to run together:
##
##   * **entered**: a sample landed in the region.
##   * **judged by a full window**: `--window` consecutive judgeable ticks fitted
##     inside one region, which is exactly what `_read_window` reads a verdict
##     off. A rule could have fired here and did not.
##   * **judged by the playhead leaving**: the region carried a judgeable tick and
##     the playhead then went somewhere else and did not come back inside that
##     watch. The movie answered this file's own question -- *am I stuck?* -- in
##     the negative, about that room, itself.
##
## Both count as judged and the split is printed, because they are different
## evidence. Counting only the first credited **1 region of the 42 it had stood
## in** over two movies: a movie walking through its rooms straddles every window
## across a region boundary, and a straddling window is credited to neither side.
##
## `--scenes` then goes and gets the rest, by entering every marker with the
## movie's own `go` rather than replaying everything before it; see `_scenes` for
## why those verdicts are reported and never asserted. Measured on
## `MAINMENU.dir`, twelve markers: the container watch alone credits **1** of
## them, and the walk credits **11 of 12** -- ten of those by a full window -- in
## 16.6 s with no container reopened. It credited 10 before the settle was watched
## rather than waited out; the two it was missing sit on frames the playhead is
## past within eight ticks, so nothing had ever sampled them, and one of the two is
## reachable now. See `_scenes`.
##
## The walk is the expensive mode and the arithmetic is worth having before
## reaching for it: a title's markers outnumber its containers by roughly fifty to
## one here, and `COMEIN.dir` alone -- 83 markers -- took 426 s on a contended
## machine at `--scene-ticks 90`. So `--scenes` is a survey to point at a title or
## a container, `--start` and `--budget-ms` are how it is split across runs, and
## the cheap `scenes` line on an ordinary sweep is what every run prints.
##
## Title-agnostic: the rules below know tempo holds, sound channels and sprite
## counts, and no movie, room, channel or member.

const Harness := preload("res://tools/lib/harness.gd")
const Args := preload("res://tools/lib/args.gd")
const Paths := preload("res://director/director_paths.gd")
const ContainerName := preload("res://director/director_container.gd")
const ContainerFile := preload("res://director/director_file.gd")
const Labels := preload("res://director/director_labels.gd")

## Unexcused score ticks watched per container, and the length of the window a
## verdict is read over. `WATCH` is two windows so that `_judge`'s sliding window
## has somewhere to slide; one window exactly would give it a single position.
##
## It buys **unexcused** ticks -- see the header. A hold or a skipped tick is
## watched and reported and not charged, so a movie with a four-second opening line
## no longer spends its whole watch on it, and what bounds a watch in practice is
## `WATCH_CAP_MS`.
##
## **This length is not what keeps a walk from reading as a trap**, and saying so
## here was wrong for as long as the claim stood: `_judge` slides the window one
## sample at a time and keeps the *worst* position, so a single window straddling
## a four-frame walk is enough to produce a finding however long the watch is.
## What separates passing through from being stuck is the arrivals rule in
## `_read_window`, and nothing else.
##
## `WINDOW` at 60 is 7.5 s of an 8 fps movie -- longer than any gap between two
## lines of speech in this corpus, and long enough that a room's own idle loop
## has come round. It is half `playhead_escape`'s 120 because that harness reads
## one room and this one reads a corpus; the trade is stated rather than hidden,
## and `--window 120` buys the stricter reading back at twice the runtime.
const WATCH := 120
const WINDOW := 60
## Score ticks a container is given to run its opening frame before it is judged.
## Every movie here starts with an `on exitFrame` that initialises the room and
## jumps; judging before that has run judges the wrong frame.
const SETTLE := 24
## The largest reachable set that still counts as a trap rather than as a movie
## going about its business. Three in `playhead_escape`, four here, because a
## cycle that crosses a movie boundary costs two states before it has done
## anything at all.
const CYCLE_MAX := 4
## Director has eight sound channels; this corpus uses four.
const SOUND_CHANNELS := 8
## The fast-forward rate the sweep runs at, as a ceiling on the adaptive rate.
##
## **This was 30 on the grounds that four score steps per tick is where sampling
## starts to alias, and that reason no longer holds.**
## `director_frame_clock.gd:tick` takes at most **one** step per call and re-arms
## `_due_in` absolutely rather than by `+=`, dropping whatever it could not
## afford -- `Score::updateNextFrameTime`'s behaviour -- and this sampler awaits
## every process frame, so a stride above 1 is structurally unreachable however
## high this number is. Measured over four `piposh-dream` movies at `--ff` 30, 60,
## 120 and 240: **0 ticks skipped at every one of them**, and `tick/frame` pinned
## at 1.00 from 60 upward, which is the process loop and not this constant.
##
## So what `--ff` buys is only the ticks the machine can paint, and 30 was leaving
## most of them on the table: measured idle, the process loop ran at 117 frames a
## second while `--ff 30` drew 26 score ticks out of it -- 0.23 ticks per frame,
## four frames of paint per tick watched. 120 asks for one step per frame at that
## rate and asks for nothing extra on a machine that cannot keep up, because the
## clock drops what it cannot afford.
##
## The adaptive halving in `_watch` is kept exactly as it was. It is now a
## backstop for a sampler that misses a frame rather than the mechanism the rate
## depends on, and `porting-fidelity-verification`'s rule about harnesses that can
## only be right while another file behaves is why it stays.
const FF := 120.0
## The slowest the adaptive rate will go. Below every movie's authored rate in
## these corpora (8-15 fps), so at the floor the clock is asked for less than one
## score step per process frame however long a frame takes to paint.
const FF_FLOOR := 4.0
## Consecutive fully-sampled ticks before the rate is allowed back up.
const FF_RECOVER := 8
## The least of a container's watched ticks that has to be contiguously sampled
## for its verdict to mean anything. Half, because the windows are what matter
## and a run that keeps being broken by aliasing simply produces no window --
## which reads as "clean" and must therefore be reported as what it is.
const MIN_COVERAGE := 0.5
## Process frames given to `go to movie` before the arrival is judged.
const OPEN_FRAMES := 8
## Wall-clock ceilings, so one pathological container cannot eat the sweep.
##
## `CLICK_CAP_MS` is a third of the watch's, and `--click` shortens its tick
## budget to one window as well. Both are budget, not principle: the first watch
## has to be long enough to see a movie settle, while a click's watch only has to
## answer "did that leave the player somewhere they cannot get out of", which is
## exactly one window. Measured without them, on `piposh-dream`: `dinner1.dir`
## alone spent 30 s on its own watch and would have spent 90 s more on three
## clicks, which puts a 52-movie corpus past an hour and makes the flag one
## nobody runs.
const OPEN_CAP_MS := 8000
const WATCH_CAP_MS := 20000
const CLICK_CAP_MS := 12000
## How much faster than real time sounds are mixed.
##
## `--ff` scales the frames and every hold counted off the frame clock, and the
## header says sound is the one exception because the mixer runs on the audio
## server's clock. `AudioServer.playback_speed_scale` is that clock's own
## multiplier, so it is the same trick applied to the one hold `--ff` cannot
## reach: `soundBusy` retires N times sooner, every cue point inside the sound
## passes N times sooner in wall clock and at the same place in the sound, and a
## `play done` after a line of speech happens at the frame it always did.
##
## **This is a speed-up, not an excuse**, which is the distinction that decides
## whether it can invent a finding. The excuses in this file *forgive* a tick; this
## makes the tick that was being forgiven arrive sooner. What the movie does is
## unchanged -- the same handlers run in the same order at the same frames -- so a
## window built after a sound finished is a window a real player also reaches, just
## later.
##
## Eight because it is a whole number of poll intervals and because the corpus's
## own numbers say the wait, not the mixer, is what binds: measured over
## `piposh-dream` at `--speech 1`, `dinner1.dir` spent 512 of 523 watched ticks
## held on `wait for sound 1`. See the header section for the run-level figures.
const SPEECH := 8.0
## The scene walk's budget, in the same unit as `--ticks`: unexcused ticks.
##
## `WATCH` is two windows so `_judge`'s window has somewhere to slide; a scene
## gets one and a half, which is thirty positions rather than sixty. That is a
## deliberately cheaper reading and the trade is the whole reason the walk is
## affordable: a title's markers outnumber its containers by roughly an order of
## magnitude, so a scene costing what a container costs makes the walk one nobody
## runs. `--scene-ticks 120` buys the container's reading back.
const SCENE_WATCH := 90
## Score ticks a marker is given to arrive before it is judged. Far below
## `SETTLE`, and for a reason rather than for economy: `SETTLE` covers a *movie*
## opening -- `prepareMovie`, `startMovie` and a first frame that initialises the
## room -- while a marker jump inside an open movie is one frame entry.
const SCENE_SETTLE := 8
const SCENE_CAP_MS := 8000
## Consecutive process frames without a score tick that end a watch early, and
## what has to be true for the short one to apply.
##
## A movie under Director's `pause` counts no score ticks at all
## (`frame_loop.gd:tick` skips the counter before the hold is even tested), so a
## watch that waits for a tick budget waits for ever on the one state the engine
## can explain perfectly well. `hezsave.dir` is the corpus's example: it pauses on
## frame 8, and before this the sweep spent 80 s of its ceiling on it and reported
## "no score ticks observed" -- the shape of a hang, printed for the one thing
## that certainly is not one.
##
## **The short count applies only while the movie is paused or halted**, because
## those are the only two things that stop the counter, and a bare frame count is
## wrong the moment the adaptive rate slows down: at the floor a score tick is
## several process frames apart by design, and a 30-frame cutoff ended the watch
## of every expensive movie after six ticks. `QUIET_STALL` is the backstop for
## anything neither of those explains, and is deliberately far larger.
const QUIET_FRAMES := 30
const QUIET_STALL := 900

## Verdicts, worst first. The number is the severity a finding is ranked by.
const SEVERITY := {
	"no-open": 5,
	"ping-pong": 4,
	"blank-park": 4,
	"blank-cycle": 3,
	"lingo": 2,
	"trap": 1,
	"sound-park": 1,
}
## Which of them fail the run. `trap` joins this under `--strict`; see the header.
const FAILING := ["no-open", "ping-pong", "blank-park", "blank-cycle", "lingo"]

## The `--ff` ceiling for this run. On the tool rather than threaded through,
## because `_watch` lowers the live rate as it goes and has to know what it is
## allowed back up to; reading it off the node instead would let one slow movie
## pin every movie after it at the floor.
var _ff := FF
## The audio-server multiplier this run is mixing at, carried so the report can
## say it. A run that says `speech x8` and one that says `x1` are two different
## experiments and the number belongs next to the depth figures, not only in the
## command line somebody has since lost.
var _speech := SPEECH
## `<movie file, lower case>` -> the frame each of its marker regions starts at,
## in order, read from the containers' own `VWLB` before anything is opened.
##
## **A movie with no `VWLB` has one region and not none.** A room in these titles
## is a marker (`director-qa-playthrough`), so the marker count is the scene count
## -- but a movie that declares no marker still has a score somebody can be stuck
## in, and giving it zero scenes would make it the one movie a coverage number
## cannot fail to cover.
var _regions: Dictionary = {}
## `"<movie>:<region index>"` for every region a sample landed in, and for every
## region a whole window of judgeable ticks fitted inside. The first is "we were
## there", the second is "a rule was read over it", and the gap between them is
## the honest coverage figure -- `6b42a128` is what happens when the first is
## printed as if it were the second.
var _touched: Dictionary = {}
var _scenes_judged: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var h := Harness.new()
	await _sweep(h)
	quit(h.finish("every movie in the corpus is one a player could leave"))


## Returns whether it ran to a conclusion rather than whether the checks passed.
## A GDScript runtime error aborts this handler and leaves the case open, which
## `harness.gd` reports as FAIL rather than ending the run quietly.
func _sweep(h: Harness) -> bool:
	var args := Args.parse()
	var paths := Paths.new()
	if not paths.load_config():
		print("no game configured: %s must set [game] root and boot_movie" % Paths.CONFIG_PATH)
		h.begin("a corpus to sweep")
		h.check("the config names a game", false)
		return true

	var only := Args.text(args, "only", "").to_lower()
	var limit := Args.number(args, "limit", 0)
	# Where in the sorted list to begin. `--limit` alone can only ever cut the
	# corpus from the same end, so two runs of half a title cover the same half
	# twice; with this they cover it once each, which is what "split the work
	# across runs" needs to mean. `--start 26 --limit 26` is the second half.
	var start_at := Args.number(args, "start", 0)
	var budget_ms := Args.number(args, "budget-ms", 0)
	var ticks := Args.number(args, "ticks", WATCH)
	var window := Args.number(args, "window", WINDOW)
	var settle := Args.number(args, "settle", SETTLE)
	var clicking := Args.flag(args, "click")
	var clicks := Args.number(args, "clicks", 3)
	var strict := Args.flag(args, "strict")
	var verbose := Args.flag(args, "verbose")
	var scenes := Args.flag(args, "scenes")
	var scene_only := Args.text(args, "scene", "").to_lower()
	var scene_ticks := Args.number(args, "scene-ticks", SCENE_WATCH)
	_ff = float(Args.number(args, "ff", int(FF)))
	# Set once for the whole run, before a preview exists, because it is a property
	# of the audio server rather than of a movie. `--speech 1` restores real time
	# and is what to reach for when a finding needs to be re-read at the rate a
	# player hears.
	_speech = maxf(float(Args.number(args, "speech", int(SPEECH))), 0.01)
	AudioServer.playback_speed_scale = _speech

	# Movies only. A cast is a container and is in the index, and `go to movie` on
	# one loads no score -- the picker refuses them for the same reason.
	var movies: Array[String] = []
	for entry in paths.containers():
		if ContainerName.CAST.has(str(entry).get_extension().to_lower()):
			continue
		if only != "" and not str(entry).to_lower().contains(only):
			continue
		movies.append(str(entry))
	if start_at > 0:
		movies = movies.slice(mini(start_at, movies.size())) as Array[String]

	# Read before a preview exists, from the containers rather than from anything
	# the sweep does, so the denominator of the coverage figure is a property of
	# the title and not of how far this run got. A movie skipped by `--limit` still
	# counts its scenes against the total, which is the whole point of having one.
	for movie in movies:
		var resolved := paths.resolve(movie)
		if resolved != "":
			_regions[movie.get_file().to_lower()] = _marker_frames(resolved)

	_assert_rules(h)

	var case := "%s: every movie is one a player could leave" % paths.root.get_file()
	h.begin(case)
	if not h.check("the corpus holds movies to sweep", not movies.is_empty(),
			"%d movie(s)%s" % [movies.size(), "" if only == "" else " matching '%s'" % only]):
		h.complete(case)
		return true

	var preview: Node = load("res://scenes/director_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	var audio: Node = root.get_node_or_null("AudioDirector")
	if not h.check("AudioDirector is in the tree", audio != null):
		h.complete(case)
		return true
	# `_ticks` is this file's unit of time and it is not in
	# `tools/preview_surface.gd`'s asserted list, so a rename would make `get()`
	# answer null, `int(null)` answer 0, every window stay empty, and the whole
	# sweep report green over movies it never watched. That is the dark-harness
	# failure `scenes/preview/README.md` names; this is the guard against it.
	if not h.check("the movie's own tick counter is readable",
			preview.get("_ticks") != null):
		h.complete(case)
		return true
	preview.set("_fast_forward_fps", _ff)

	print("")
	print("root      : %s" % paths.root)
	print("movies    : %d" % movies.size())
	print("watch     : %d score ticks each, verdict over %d, settle %d, ff <= %.0f, "
			% [ticks, window, settle, _ff]
		+ "speech x%.0f%s" % [_speech,
			"" if not scenes else ", scenes %d tick(s) each" % scene_ticks])
	print("")

	var findings: Array[Dictionary] = []
	var visited := 0
	var skipped: Array[String] = []
	var started := Time.get_ticks_msec()
	var covered := 0.0
	var thin: Array[String] = []
	var unjudged: Array[String] = []
	# Cycles the trap arm declined because the player had something to click.
	# Counted and named rather than dropped, so a rule that starts excusing the
	# whole corpus is visible as a number instead of as a quiet green run --
	# `porting-fidelity-verification`'s "make forgiven visibly distinct from
	# resolved".
	var idle_loops: Array[String] = []
	# The budget's own accounting. `live` is the unexcused ticks the run obtained
	# across every first watch; `capped` and `stalled` are the watches the wall
	# clock and the stall backstop ended; `short` is the ones that ended on their
	# tick budget having spent it on something else, which is the defect
	# `bugs.md` 128 describes and the only one of the four that is asserted.
	var live := 0
	var capped: Array[String] = []
	var stalled: Array[String] = []
	var short: Array[String] = []
	# The scene walk's own accounting. `walked` is markers jumped to, `reopened` is
	# how often a scene left the container and had to be brought back, and the
	# coverage figures themselves live in `_touched`/`_scenes_judged` because the
	# container watch fills them too.
	var walked := 0
	var reopened := 0
	var missed := 0
	var scene_findings: Array[Dictionary] = []
	# Movies whose `VWLB` could not be read before the sweep started. Their regions
	# are missing from the denominator *and* from `_region_at`, so their samples
	# are credited to nothing -- a coverage figure that silently drops a container
	# is the one failure this number must not have.
	var no_index: Array[String] = []

	for movie in movies:
		if limit > 0 and visited >= limit:
			skipped.append(movie)
			continue
		if budget_ms > 0 and Time.get_ticks_msec() - started >= budget_ms:
			skipped.append(movie)
			continue
		visited += 1
		if not _regions.has(movie.get_file().to_lower()):
			no_index.append(movie.get_file())
		var seen: Dictionary = await _visit(
			preview, audio, movie, settle, ticks, window)
		covered += float(seen.get("coverage", 1.0))
		if float(seen.get("coverage", 1.0)) < MIN_COVERAGE:
			thin.append("%s %d%%" % [movie.get_file(),
				int(round(float(seen["coverage"]) * 100.0))])
		# Everything from here to the `--click` block is read off the **first**
		# watch, before a poke can replace the verdict: a poke that finds
		# something must not also erase what the watch measured.
		#
		# A movie whose longest run of judgeable ticks never reached `window` was
		# never judged by any of the rules -- there was no window to read one
		# over. It is not a finding and it is not a clean bill of health either,
		# and the difference is only visible if it is counted. **This used to ask
		# how many ticks were sampled**, a question a movie held on a sound for
		# its whole watch answers with the full number while offering no window at
		# all, so the counter read clean over exactly the movies `bugs.md` 128 is
		# about.
		if int(seen.get("judged", 0)) < window and not _clock_stopped(preview):
			unjudged.append("%s %d/%d" % [
				movie.get_file(), int(seen.get("judged", 0)), window])
		live += int(seen.get("live", 0))
		match str(seen.get("ended", "")):
			"capped":
				capped.append(movie.get_file())
			"stalled":
				stalled.append(movie.get_file())
			"short":
				# The pinning check for the budgeting rule, and the one thing in
				# this block that is asserted. A watch may stop because it spent
				# its unexcused-tick budget, because the wall clock ran out or
				# because the score's clock stopped; there is no fourth reason, so
				# one is a budget being charged for something other than the ticks
				# a rule can be read over. That is what `bugs.md` 128 is, and it
				# is what reverting `_watch`'s loop condition to raw score ticks
				# produces -- verified by doing exactly that and watching this go
				# red over `piposh-dream`.
				#
				# Read off the first watch of each container only. `_poke` runs the
				# same `_watch` with the same budget, so a rule broken there is
				# broken here too, and plumbing per-click accounting out of a
				# function that returns one verdict buys nothing.
				short.append("%s %d/%d" % [
					movie.get_file(), int(seen.get("live", 0)), ticks])
		if str(seen.get("idle", "")) != "":
			idle_loops.append(movie.get_file())
		if clicking and str(seen["verdict"]) == "":
			var poked: Dictionary = await _poke(
				preview, audio, movie, clicks, ticks, window)
			if str(poked.get("verdict", "")) != "":
				seen = poked
		if str(seen["verdict"]) != "":
			findings.append(seen)
		if verbose or str(seen["verdict"]) != "":
			print(_line(seen))
		if scenes and str(seen["verdict"]) != "no-open":
			var walk: Dictionary = await _scenes(
				preview, audio, movie, scene_ticks, window, scene_only, verbose)
			walked += int(walk["walked"])
			reopened += int(walk["reopened"])
			missed += int(walk["missed"])
			for found in walk["findings"]:
				scene_findings.append(found)

	# Coverage is the sampler's own honesty check. A verdict is only read over
	# consecutive *observed* ticks, so a run that keeps aliasing produces no window
	# at all and reports every movie clean -- which is indistinguishable from a
	# healthy corpus unless the number is on the page and asserted.
	# The *mean* alone, and not "no movie was thin". A per-movie threshold makes
	# this entry flake on a loaded machine -- one expensive room sampled badly is
	# the machine, not the engine -- while the mean falling below half means the
	# run as a whole did not see the movies it judged, which is a result.
	var mean := 1.0 if visited == 0 else covered / float(visited)
	h.check("the sampler saw the movies it judged (mean coverage %d%%)"
			% int(round(mean * 100.0)),
		mean >= MIN_COVERAGE,
		"lower --ff; thinnest: %s" % ", ".join(thin.slice(0, 6))
			if not thin.is_empty() else "")

	# Coverage above answers "did the sampler see the ticks that happened". This
	# answers the other half -- "was the watch spent on ticks a rule can be read
	# over" -- and the two are different questions with different failure modes,
	# which is the whole of `bugs.md` 128: coverage was 100% for a sweep that
	# watched no gameplay, correctly, because a held tick is a sampled one.
	#
	# Only the budget's own arithmetic is asserted here, never a depth threshold.
	# How much of a corpus is cut scene is a property of the title, so a run over
	# an all-cut-scene root would go red for being honest; `depth`, `unjudged`,
	# `idle loops` and `skipped` are counted and named instead, the way this file
	# already treats every other number that is not higher-is-better.
	h.check("every watch ended on its unexcused ticks, the wall clock or a stopped clock",
		short.is_empty(),
		"%d watch(es) stopped for none of the three, with this many unexcused "
			% short.size()
			+ "tick(s) of the %d asked: %s%s" % [ticks, ", ".join(short.slice(0, 6)),
				", ..." if short.size() > 6 else ""])

	print("")
	print("visited   : %d of %d movie(s) in %.1f s" % [
		visited, movies.size(), (Time.get_ticks_msec() - started) / 1000.0])
	print("depth     : %d unexcused tick(s) watched, mean %.0f of the %d asked; "
			% [live, 0.0 if visited == 0 else float(live) / float(visited), ticks]
		+ "%d watch(es) hit the %.0fs ceiling first" % [
			capped.size(), WATCH_CAP_MS / 1000.0])
	if not stalled.is_empty():
		# Two thresholds, not one, and the line says so rather than naming the
		# larger: `QUIET_FRAMES` applies while the clock is legitimately stopped
		# (Director's `pause`, or a movie that halted) and `QUIET_STALL` to
		# anything else, which is why a paused save panel is on this line after a
		# fifth of a second and a genuine stall is not.
		print("stalled   : %d gave up on a clock that stopped counting (%d frame(s) "
				% [stalled.size(), QUIET_FRAMES]
			+ "under `pause`/`halt`, %d otherwise): %s%s" % [
				QUIET_STALL, ", ".join(stalled.slice(0, 6)),
				", ..." if stalled.size() > 6 else ""])
	# The coverage figure the container-level `visited` line was being read as, and
	# never was. A marker region is a room; `judged` is a region some window of
	# `--window` consecutive unexcused ticks fitted inside, which is the input a
	# verdict is read off, and `entered` is one the playhead merely stood in.
	# Neither is higher-is-better on its own -- a title is as coverable as its
	# rooms let a cold entry be -- but the *gap* is, and it is the number
	# `bugs.md` 128 asks a later session to compare against.
	#
	# **The denominator is the sweep's subject, not the run's reach**, and the
	# three flags that narrow things divide on exactly that line. `--only` and
	# `--start` choose a subject, so they shrink it and two `--start` halves sum to
	# the title. `--limit` is a budget that ran out, so it does not: the movies it
	# skipped are named on the `skipped` line and still counted here, because a
	# coverage total that shrinks with the budget is a total that always looks
	# good, which is the whole reason this figure is read off the containers before
	# the sweep starts.
	var declared := 0
	for key in _regions.keys():
		declared += (_regions[key] as PackedInt32Array).size()
	var by_window := 0
	for key in _scenes_judged.keys():
		if str(_scenes_judged[key]) == "window":
			by_window += 1
	print("scenes    : judged %d of %d marker region(s) the corpus declares "
			% [_scenes_judged.size(), declared]
		+ "(%d entered; %d by a full window, %d by the playhead leaving)%s" % [
			_touched.size(), by_window, _scenes_judged.size() - by_window,
			"" if not scenes else "; the walk jumped to %d marker(s) and reopened %d"
				% [walked, reopened]])
	if not unjudged.is_empty():
		print("unjudged  : %d never ran %d unexcused tick(s) together, so no window was "
				% [unjudged.size(), window]
			+ "read: %s%s" % [", ".join(unjudged.slice(0, 6)),
				", ..." if unjudged.size() > 6 else ""])
	if not idle_loops.is_empty():
		print("idle loops: %d cycled inside %d or fewer drawn state(s) with a hotspot "
			% [idle_loops.size(), CYCLE_MAX]
			+ "on the loop, so `trap` was withheld: %s%s" % [
				", ".join(idle_loops.slice(0, 8)),
				", ..." if idle_loops.size() > 8 else ""])
	if not skipped.is_empty():
		# Logged rather than silently truncated: a sweep that covered a third of
		# the corpus and said "all clear" is worse than one that did not run.
		print("skipped   : %d (--limit/--budget-ms): %s%s" % [
			skipped.size(), ", ".join(skipped.slice(0, 6)),
			", ..." if skipped.size() > 6 else ""])
	print("")

	var failing: Array[Dictionary] = []
	for finding in findings:
		var verdict := str(finding["verdict"])
		if FAILING.has(verdict) or (strict and verdict == "trap"):
			failing.append(finding)
	if not findings.is_empty():
		print("findings, worst first:")
		findings.sort_custom(func(a, b):
			return int(SEVERITY.get(a["verdict"], 0)) > int(SEVERITY.get(b["verdict"], 0)))
		for finding in findings:
			print("  %-11s %s" % [str(finding["verdict"]), str(finding["movie"])])
			print("      %s" % str(finding["detail"]))
			print("      godot --headless --path . --script tools/liveness_sweep.gd -- \\")
			print("          --root %s --only %s%s" % [
				paths.root.get_file(), str(finding["movie"]).get_file(),
				" --click" if bool(finding.get("clicked", false)) else ""])
		print("")

	# Two things about the coverage figure, and neither is a threshold on it. How
	# much of a title a cold entry can reach is a property of the title; what this
	# port controls is whether the number means what it says.
	h.check("every region counted as judged was one the sweep stood in",
		_judged_are_touched(), "a window was credited to a region no sample landed in")
	if scenes:
		# The one thing the scene walk asserts, and it is about the walk rather
		# than about the title: a marker counted as walked is one the playhead was
		# actually placed on. `6b42a128` reported eighteen scenes as covered
		# without ever entering them, and the shape of that failure is a counter
		# incremented beside a jump nobody checked.
		h.check("every marker the walk counted was one it put the playhead on",
			missed == 0,
			"%d of %d jump(s) did not land" % [missed, walked])
	h.check("every movie visited had its marker regions read",
		no_index.is_empty(),
		"%d container(s) contributed samples to no region: %s" % [
			no_index.size(), ", ".join(no_index.slice(0, 6))])

	if not scene_findings.is_empty():
		# Printed with the same shape as the container findings and deliberately
		# **not** added to `failing`: a marker entered by `go` is a cold entry
		# without the room chain that would normally set the globals it reads, so
		# these are leads for `qa_walk` rather than filed bugs. See `_scenes`.
		print("scene findings (cold marker entries -- reported, not asserted):")
		scene_findings.sort_custom(func(a, b):
			return int(SEVERITY.get(a["verdict"], 0)) > int(SEVERITY.get(b["verdict"], 0)))
		for found in scene_findings.slice(0, 20):
			print("  %-11s %s" % [str(found["verdict"]), str(found["movie"])])
			print("      %s" % str(found["detail"]))
		if scene_findings.size() > 20:
			print("  ... and %d more" % (scene_findings.size() - 20))
		print("")

	h.check("no movie is stuck, blank or trading places with another",
		failing.is_empty(),
		"%d finding(s) over %d movie(s)" % [failing.size(), visited])
	if not findings.is_empty() and failing.size() < findings.size():
		print("      (%d further low-confidence finding(s) above are reported and not"
			% (findings.size() - failing.size()))
		print("       asserted -- `trap` and `sound-park`; --strict fails on `trap`)")
	h.complete(case)
	return true


## Can a region be judged without having been stood in? Only if `_credit` has
## drifted, and the answer would be a coverage figure larger than the evidence for
## it -- which is the direction that flatters, so it is the direction to check.
func _judged_are_touched() -> bool:
	for key in _scenes_judged.keys():
		if not _touched.has(key):
			return false
	return true


## The rules, against windows built by hand, before a movie is opened.
##
## **A detector whose positive path is never exercised is a dark harness**, and
## this one is the shape most at risk of it: on a healthy corpus every assertion
## below the sweep is "nothing was found", which passes identically whether the
## rules work or whether `_read_window` returns `{}` for everything. `gate.sh`
## has a whole paragraph about harnesses that pass over the empty set; this is
## that paragraph applied to a rule instead of to a subject.
##
## So each verdict is made to fire once from a synthetic window, and — as
## important — the shapes that must *not* fire are checked too: a park with
## artwork on it (`go to the frame`, the most common state in the corpus), a bare
## stage under an open Movie-In-A-Window, a playhead moving through more states
## than `CYCLE_MAX`, a walk that parks, a cycle with a hold on every tick, and a
## cycle whose loop offers the player a click. Costs milliseconds and needs no
## movie.
##
## **Every excuse is paired with the shape it must not reach.** An excuse checked
## only in the direction that clears something is a rule nobody has tested; the
## clickable-cycle excuse is therefore asserted three times over -- once clearing
## a one-movie cycle, once *not* clearing two movies trading places, and once not
## clearing a cycle through an empty frame. The middle one is the founding bug of
## this whole file, which no longer exists to be reproduced live.
func _assert_rules(h: Harness) -> void:
	var name := "the rules fire on the shapes they are for, and on no others"
	h.begin(name)
	for expected in [
		["blank-park", _window_of([["a.dir", 1, 0]])],
		["", _window_of([["a.dir", 1, 7]])],
		["ping-pong", _window_of([["a.dir", 803, 4], ["b.dir", 27, 0]])],
		["ping-pong", _window_of([["a.dir", 803, 4], ["b.dir", 27, 9]])],
		["blank-cycle", _window_of([["a.dir", 5, 3], ["a.dir", 6, 0]])],
		["trap", _window_of([["a.dir", 5, 3], ["a.dir", 6, 4]])],
	]:
		var got := str(_read_window(expected[1]).get("verdict", ""))
		var ok := got == str(expected[0])
		h.check("a window of %s reads as `%s`" % [
				_shape(expected[1]),
				str(expected[0]) if str(expected[0]) != "" else "healthy"],
			ok, "" if ok else "got `%s`" % got)

	# The exemption, on its own, because it is the one place a finding can be
	# talked out of and the one most likely to be widened by accident.
	var under_window := _window_of([["a.dir", 1, 0]])
	for sample in under_window:
		(sample as Dictionary)["windowed"] = true
	h.check("a bare stage under an open window is not a blank park",
		_read_window(under_window).is_empty(),
		str(_read_window(under_window).get("verdict", "")))

	var roaming: Array = []
	for i in WINDOW:
		roaming.append({"movie": "a.dir", "frame": i, "drawn": 6, "hold": "",
			"stride": 1, "windowed": false})
	h.check("a playhead visiting more than %d state(s) is not a trap" % CYCLE_MAX,
		_read_window(roaming).is_empty(),
		str(_read_window(roaming).get("verdict", "")))

	# `SACHROOM.dir`'s reported trap, which was not one. A playhead that walks
	# through `CYCLE_MAX` frames and then parks on the last of them fills the one
	# window straddling the walk with four states, and a *set* of states cannot
	# tell that apart from a cycle -- so the movie was reported as "confined to 4
	# state(s) for 60 tick(s)" while it spent 57 of those 60 parked on one. What
	# makes a cycle a cycle is that a state is **returned to**, which is a fact
	# about the order of the samples and is lost the moment they become a set.
	var walked: Array = []
	for i in WINDOW:
		walked.append({"movie": "a.dir", "frame": mini(25 + i, 25 + CYCLE_MAX - 1),
			"drawn": 7, "hold": "", "stride": 1, "windowed": false})
	h.check("a playhead that walks through %d state(s) and parks is not a trap" % CYCLE_MAX,
		_read_window(walked).is_empty(),
		str(_read_window(walked).get("verdict", "")))

	# And the whole of the "do not cry wolf" property in one assertion: the same
	# two-frame ping-pong, with a hold on every tick, must produce no finding at
	# all -- because the window is cleared rather than annotated.
	var held: Array = []
	for i in WINDOW * 4:
		held.append({"movie": "a.dir" if i % 2 == 0 else "b.dir", "frame": 1,
			"drawn": 0, "hold": "wait for click", "stride": 1, "windowed": false})
	var excused := str(_judge("x.dir", {"errors": {}, "samples": held}, WINDOW)["verdict"])
	h.check("the same shape with a hold on every tick is not a finding",
		excused == "", excused)

	# The trap arm's own excuse, and the two shapes it must not reach. Every one of
	# these three windows carries a hotspot on every state; without that they would
	# pass for the wrong reason, by never asking the question under test.
	#
	# `piposh-dream/puzzle.dir` is the first of them in the corpus: four drawn
	# states, sixteen clickable tiles, and an authored `go("start")` on the last
	# frame. It read as a `trap` under `--strict` until this rule existed.
	var idling := _read_window(_window_of([["a.dir", 5, 3], ["a.dir", 6, 4]], true))
	h.check("a cycle of drawn states with a hotspot on the loop is not a trap",
		not idling.is_empty() and str(idling["verdict"]) == "",
		"got `%s`" % str(idling.get("verdict", "<no window read at all>")))

	# **The negative control this change exists to survive.** The bug this file was
	# written from -- `ques.dir` f803 and `Saves.dir` f27 trading places -- is two
	# containers alternating, and the excuse above must not reach it however
	# clickable either of them is. Read through `_judge` rather than
	# `_read_window`, so the run-building and window-sliding are exercised too:
	# the founding bug cannot be reproduced live any more, and this is what stands
	# in for it.
	var trading: Array = []
	for i in WINDOW * 2:
		trading.append({"movie": "ques.dir" if i % 2 == 0 else "Saves.dir",
			"frame": 803 if i % 2 == 0 else 27, "drawn": 4, "hold": "",
			"stride": 1, "windowed": false, "clickable": true})
	var still := str(_judge("ques.dir", {"errors": {}, "samples": trading},
		WINDOW)["verdict"])
	h.check("two movies trading places is a ping-pong with a hotspot on both",
		still == "ping-pong", "got `%s`" % still)

	# And a black stage in the cycle stays a finding too: a frame drawing nothing
	# is a frame drawing nothing, whoever can be clicked on the other one.
	var flashing := str(_read_window(
		_window_of([["a.dir", 5, 3], ["a.dir", 6, 0]], true)).get("verdict", ""))
	h.check("a cycle through an empty frame is a blank cycle with a hotspot on it",
		flashing == "blank-cycle", "got `%s`" % flashing)

	# The budgeting rule. `_judgeable` is what `_watch` charges the tick budget
	# for, what `_judge` builds a window out of and what `_longest_run` measures,
	# so it is asserted in both directions and then as an *equivalence* against
	# `_judge` -- three statements that agree are not the same thing as one rule.
	var live_tick := {"movie": "a.dir", "frame": 1, "drawn": 4, "hold": "",
		"stride": 1, "windowed": false}
	var held_tick := {"movie": "a.dir", "frame": 1, "drawn": 4,
		"hold": "wait for sound 1", "stride": 1, "windowed": false}
	var skipped_tick := {"movie": "a.dir", "frame": 1, "drawn": 4, "hold": "",
		"stride": 2, "windowed": false}
	h.check("an unexplained, fully-sampled tick is one the budget pays for",
		_judgeable(live_tick))
	h.check("a tick the engine can explain is not",
		not _judgeable(held_tick), str(held_tick["hold"]))
	h.check("a tick that skipped one is not either",
		not _judgeable(skipped_tick), "stride %d" % int(skipped_tick["stride"]))

	# The equivalence, over the founding shape and at the two lengths that
	# straddle the window: `_longest_run` must say exactly what `_judge` could
	# read, or `unjudged` is counting something the rules do not use.
	#
	# **A held stretch is prepended, and that is what makes this able to fail in
	# both directions.** Without it every sample in the trace is judgeable, so
	# `samples.size()` and the longest run are the same number and a
	# `_longest_run` that counted every sample -- which is the movie held on a
	# sound for its whole watch, reporting the full tick count and offering no
	# window, `bugs.md` 128's `unjudged` -- would pass. With it the trace is
	# `WINDOW` held ticks and `length` live ones, and the two answers differ.
	for length in [WINDOW - 1, WINDOW]:
		var pinging: Array = []
		for i in WINDOW:
			pinging.append({"movie": "ques.dir" if i % 2 == 0 else "Saves.dir",
				"frame": 803 if i % 2 == 0 else 27, "drawn": 4,
				"hold": "wait for sound 1", "stride": 1, "windowed": false,
				"clickable": false})
		for i in length:
			pinging.append({"movie": "ques.dir" if i % 2 == 0 else "Saves.dir",
				"frame": 803 if i % 2 == 0 else 27, "drawn": 4, "hold": "",
				"stride": 1, "windowed": false, "clickable": false})
		var reading := str(_judge("ques.dir", {"errors": {}, "samples": pinging},
			WINDOW)["verdict"])
		var wanted := "ping-pong" if length >= WINDOW else ""
		h.check("%d held tick(s) then %d judgeable ones of the founding ping-pong read as `%s`, over a run of %d"
				% [WINDOW, length, wanted if wanted != "" else "healthy", length],
			reading == wanted and _longest_run(pinging) == length,
			"got `%s` over a run of %d" % [reading, _longest_run(pinging)])

	# **The aliasing guarantee, pinned.** The same shape with every tick a skipped
	# one must produce nothing at all, because a skipped tick clears the window
	# exactly as a hold does. That is what makes aliasing able to cost a finding
	# and unable to invent one -- the property the header has claimed since this
	# file was written and nothing asserted until the budget started depending on
	# it.
	var aliased: Array = []
	for i in WINDOW * 4:
		aliased.append({"movie": "ques.dir" if i % 2 == 0 else "Saves.dir",
			"frame": 803 if i % 2 == 0 else 27, "drawn": 4, "hold": "",
			"stride": 2, "windowed": false, "clickable": false})
	var blind := str(_judge("ques.dir", {"errors": {}, "samples": aliased},
		WINDOW)["verdict"])
	h.check("the same shape sampled every other tick is not a finding", blind == "",
		blind)
	h.check("and it offers no run for a rule to be read over",
		_longest_run(aliased) == 0, "%d tick(s)" % _longest_run(aliased))

	# **The coverage figure's own rules, over synthetic traces, before a movie is
	# opened**, for the reason the whole of this function exists: `scenes` prints a
	# number on every run, and a number is exactly the kind of output that reads as
	# measured whether or not the code behind it works. `6b42a128` is a coverage
	# counter nobody exercised.
	#
	# The three dictionaries are instance state the real sweep fills, so they are
	# swapped out and back rather than written to -- a check that inflated the run's
	# own coverage would be the failure it is checking for.
	var saved_regions := _regions
	var saved_touched := _touched
	var saved_judged := _scenes_judged
	_regions = {"m.dir": PackedInt32Array([0, 100])}
	_touched = {}
	_scenes_judged = {}
	_credit({"samples": _ticks_at("m.dir", 5, WINDOW, "")}, WINDOW)
	h.check("a whole window inside one region credits that region by window",
		str(_scenes_judged.get("m.dir:0", "")) == "window",
		str(_scenes_judged.get("m.dir:0", "<none>")))
	_touched = {}
	_scenes_judged = {}
	# Half a window in region 0, then half in region 1: neither side can carry a
	# window, and the playhead visibly left the first one.
	var crossing: Array = _ticks_at("m.dir", 5, WINDOW / 2, "")
	crossing.append_array(_ticks_at("m.dir", 150, WINDOW / 2, ""))
	_credit({"samples": crossing}, WINDOW)
	h.check("a run that crosses a region boundary credits the one it left, by exit",
		str(_scenes_judged.get("m.dir:0", "")) == "left"
			and not _scenes_judged.has("m.dir:1"),
		"%s / %s" % [str(_scenes_judged.get("m.dir:0", "<none>")),
			str(_scenes_judged.get("m.dir:1", "<none>"))])
	h.check("and the region it ended in is entered without being judged",
		_touched.has("m.dir:1"), "not even entered")
	_touched = {}
	_scenes_judged = {}
	# Every tick excused. The playhead was there and left, and nobody looked.
	var muted: Array = _ticks_at("m.dir", 5, WINDOW, "wait for sound 1")
	muted.append_array(_ticks_at("m.dir", 150, 4, "wait for sound 1"))
	_credit({"samples": muted}, WINDOW)
	h.check("a region traversed entirely under a hold is entered and not judged",
		_touched.has("m.dir:0") and _scenes_judged.is_empty(),
		"%d entered, %d judged" % [_touched.size(), _scenes_judged.size()])
	h.check("and nothing is ever credited to a movie with no region index",
		_region_at("elsewhere.dir", 3) == -1, "%d" % _region_at("elsewhere.dir", 3))
	_regions = saved_regions
	_touched = saved_touched
	_scenes_judged = saved_judged
	h.complete(name)


## `count` samples standing on one frame, for the coverage checks above. A hold
## makes every one of them unjudgeable, which is the half of `_credit` that has to
## be checked in the direction that credits nothing.
static func _ticks_at(movie: String, frame: int, count: int, hold: String) -> Array:
	var out: Array = []
	for _i in count:
		out.append({"movie": movie, "frame": frame, "drawn": 4, "hold": hold,
			"stride": 1, "windowed": false, "clickable": false})
	return out


## `WINDOW` samples cycling through `states`, each `[movie, frame, drawn]`.
##
## `clickable` is a parameter and not a constant because the pair of runs -- the
## same window read once with a hotspot on it and once without -- is what pins
## the trap arm's excuse to the trap arm.
static func _window_of(states: Array, clickable: bool = false) -> Array:
	var out: Array = []
	for i in WINDOW:
		var state: Array = states[i % states.size()]
		out.append({"movie": str(state[0]), "frame": int(state[1]),
			"drawn": int(state[2]), "hold": "", "stride": 1, "windowed": false,
			"clickable": clickable})
	return out


## `a.dir:1(0) <-> b.dir:27(4)` for a synthetic window, for the check's name.
static func _shape(window: Array) -> String:
	var states: Dictionary = {}
	for sample_value in window:
		var sample: Dictionary = sample_value
		states["%s:%d" % [str(sample["movie"]), int(sample["frame"])]] = int(sample["drawn"])
	return _states(states)


## One line of the per-movie report.
static func _line(seen: Dictionary) -> String:
	var verdict := str(seen["verdict"])
	return "  %-11s %-26s %4.1fs+%4.1fs %3d%%  %s" % [
		"ok" if verdict == "" else verdict, str(seen["movie"]),
		int(seen.get("open_ms", 0)) / 1000.0, int(seen.get("watch_ms", 0)) / 1000.0,
		int(round(float(seen.get("coverage", 1.0)) * 100.0)), str(seen["detail"])]


## Open one container, let it settle, and watch it.
##
## `lingo_go_movie` is the engine's own `go to movie` and the F12 picker's call,
## so the container is entered the way the game enters one: `prepareMovie`,
## `startMovie`, the first frame's `prepareFrame` and `enterFrame`. Nothing here
## is a debug path.
func _visit(preview: Node, audio: Node, movie: String, settle: int, ticks: int,
		window: int) -> Dictionary:
	var opening := Time.get_ticks_msec()
	_reset_between(preview)
	preview.call("lingo_go_movie", movie, null)
	for _i in OPEN_FRAMES:
		await process_frame
	# Only the score is asserted, not the name. A movie that immediately hands off
	# to another has opened correctly -- the boot movie of every title does exactly
	# that -- so "did it stay?" is a question for the watch below, where the answer
	# is a state list rather than a boolean.
	if preview.get("_score") == null:
		var absent := _finding(movie, "no-open", "no score loaded after `go to movie`")
		absent["stride"] = 0
		# No watch ran, so it must not read as one that ended short of its budget.
		absent["ended"] = "no-open"
		return absent
	await _run_ticks(preview, settle, OPEN_CAP_MS)
	var watching := Time.get_ticks_msec()
	var trace: Dictionary = await _watch(preview, audio, ticks, WATCH_CAP_MS)
	_credit(trace, window)
	var seen := _judge(movie, trace, window)
	seen["stride"] = int(trace["stride"])
	seen["coverage"] = coverage(trace)
	seen["watched"] = (trace["samples"] as Array).size()
	# What the watch cost and what it bought, separately: `watched` above is every
	# tick it sampled, `judged` is the longest window a rule could have been read
	# over, and they are wildly different on a movie that opens with a speech.
	seen["judged"] = _longest_run(trace["samples"])
	seen["live"] = int(trace["live"])
	seen["ended"] = str(trace["ended"])
	seen["open_ms"] = watching - opening
	seen["watch_ms"] = Time.get_ticks_msec() - watching
	return seen


## Score ticks this sampler actually saw, over score ticks the movie ran.
##
## A sample taken two ticks after the last one covers one tick and skipped one:
## whatever the playhead did in between is unobserved, and the window it belongs
## to is discarded. So coverage is the fraction of the watch a verdict could
## legitimately have been read over, and a low one is a measurement problem
## rather than a clean movie.
static func coverage(trace: Dictionary) -> float:
	var ran := int(trace.get("ticks", 0))
	if ran <= 0:
		return 1.0
	var seen := 0
	for sample_value in trace["samples"]:
		if int((sample_value as Dictionary)["stride"]) <= 1:
			seen += 1
	return minf(float(seen) / float(ran), 1.0)


## Click what the frame offers and watch what each click leads to.
##
## Where the interesting states are behind a hotspot -- a save panel, a dialogue,
## an inventory -- nothing above ever reaches them, and the bug this file was
## written from was *behind a click*. Eligibility is the engine's own
## (`_responds_to_mouse`), and the point clicked is scanned rather than taken from
## the rect's centre for the reason `pause_holds.gd:_reachable_point` gives: a
## sprite with a transparent middle answers nowhere near its centre.
##
## Each click starts from the state the last watch ended in and is not undone,
## so this is one click deep and says so in the header.
func _poke(preview: Node, audio: Node, movie: String, budget: int, ticks: int,
		window: int) -> Dictionary:
	var tried := 0
	for sprite_value in preview.call("frame_sprites"):
		if tried >= budget:
			break
		var raw: Dictionary = sprite_value
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty() or not bool(preview.call("_responds_to_mouse", sprite)):
			continue
		var channel := int(sprite["channel"])
		var at: Variant = _reachable_point(preview, sprite, channel)
		if at == null:
			continue
		tried += 1
		preview.call("route_press", at)
		preview.call("route_release", at)
		# The same tick budget as the first watch -- a window has to be able to
		# form, and `window` ticks exactly would be destroyed by a single held one
		# -- but a third of the wall clock, which is what actually bounds it.
		var trace: Dictionary = await _watch(preview, audio, ticks, CLICK_CAP_MS)
		_credit(trace, window)
		var seen := _judge(movie, trace, window)
		seen["clicked"] = true
		seen["stride"] = int(trace["stride"])
		if str(seen["verdict"]) != "":
			seen["detail"] = "after clicking ch%d at (%d,%d): %s" % [
				channel, int((at as Vector2).x), int((at as Vector2).y),
				str(seen["detail"])]
			return seen
	return {"verdict": "", "movie": movie, "detail": "", "clicked": true, "stride": 0}


## The frame each marker region of a container starts at, from its own `VWLB`.
##
## Read with `DirectorFile`/`DirectorLabels` rather than through an opened preview
## because the denominator has to exist for movies this run never opens -- a
## coverage figure whose total shrinks when the sweep is cut short is a figure
## that always looks good.
##
## `[0]` when the container declares no marker: see `_regions`. A chunk that
## refuses to parse is treated the same way, because "this movie has one region
## the sweep will judge or fail to judge" is true either way and a refused chunk
## is `label_index`'s finding to report, not this file's.
static func _marker_frames(path: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var f := ContainerFile.new()
	if not f.open(path):
		return PackedInt32Array([0])
	for id in f.ids_of("VWLB"):
		var labels := Labels.new()
		if not labels.parse(f.read_chunk(id)):
			continue
		for marker in labels.markers:
			out.append(int(marker["frame"]))
	f.close()
	if out.is_empty():
		return PackedInt32Array([0])
	out.sort()
	# Two markers on one frame are two entries in `marker(n)`'s index space and one
	# region on the stage, and this array is the second thing rather than the
	# first: `label_index.gd` is where the index space is asserted, and keeping a
	# duplicate here would create a region `_region_at` can never return -- an
	# unreachable slot in the denominator that no run could ever cover.
	var unique := PackedInt32Array([out[0]])
	for i in range(1, out.size()):
		if int(out[i]) != int(out[i - 1]):
			unique.append(int(out[i]))
	return unique


## Which marker region a frame of a movie belongs to, or -1 for a movie the sweep
## has no index for -- a container it was never asked to visit, which a `go to
## movie` can still land it in.
func _region_at(movie_file: String, frame: int) -> int:
	var frames: Variant = _regions.get(movie_file.to_lower())
	if frames == null:
		return -1
	# Frames before the first marker belong to region 0. Director would answer
	# `marker(0)` with nothing there, but this array is regions of the stage and
	# not the index space, and a movie's head is part of whatever its first marker
	# names -- the alternative is a slice of every score that no run can cover and
	# that is not a room either.
	var out := 0
	for i in (frames as PackedInt32Array).size():
		if int(frames[i]) <= frame:
			out = i
		else:
			break
	return out


## Credit one watch's samples to the marker regions they landed in.
##
## Three different claims, kept apart on purpose.
##
##   **touched**  one sample landed in the region. The playhead was there, and
##                that is all it says.
##   **windowed** `window` consecutive judgeable samples, *all inside one region*
##                -- exactly the input `_read_window` reads a verdict off, so a
##                region credited this way is one some rule in this file could
##                have fired on and did not.
##   **left**     at least one judgeable sample in the region, and a later sample
##                somewhere else with no return inside this watch. The playhead
##                went in unexcused and came out, which is the sweep's own
##                question -- *am I stuck?* -- answered in the negative by the
##                movie itself.
##
## **A region needs `windowed` or `left`, and the second is the majority.** The
## first version of this counted only `windowed`, and over two movies of
## `piposh-dream` it credited **1** region of the 42 it had stood in: a movie
## walking through its rooms straddles every window across a region boundary, and
## a straddling window is credited to neither side. That is the conservative
## direction for a *finding* and the wrong one for a coverage figure, because the
## playhead visibly leaving a room is stronger evidence the room is not a trap
## than sixty ticks of sitting in it.
##
## The alternative -- crediting a region because the watch that mentioned it
## produced a window somewhere -- is `6b42a128` written again: that sweep played
## one scene per container and reported eighteen day-2 scenes as covered when they
## had never been entered. Every credit here is per region and per sample.
##
## A held or skipped tick carries no credit of any kind, which is the same
## predicate (`_judgeable`) the watch budget is charged against and `_judge` builds
## windows from. A room traversed entirely under a `soundBusy` wait is therefore
## *not* credited, even though the playhead did leave it: the excuse means nobody
## looked, and this file's whole design is that an excused tick is evidence of
## nothing.
func _credit(trace: Dictionary, window: int) -> void:
	var samples: Array = trace["samples"]
	# Region key per sample, "" for a movie with no index, plus where each region
	# was last seen and whether it ever carried a judgeable tick.
	var last_at: Dictionary = {}
	var live_in: Dictionary = {}
	var run: Array[String] = []
	for i in samples.size():
		var sample: Dictionary = samples[i]
		var file := str(sample["movie"]).get_file()
		var region := _region_at(file, int(sample["frame"]))
		var key := "" if region < 0 else "%s:%d" % [file.to_lower(), region]
		if key == "":
			run.clear()
			continue
		_touched[key] = true
		last_at[key] = i
		if not _judgeable(sample):
			run.clear()
			continue
		live_in[key] = true
		run.append(key)
		if run.size() < window:
			continue
		var first := run[run.size() - window]
		var uniform := true
		for j in range(run.size() - window, run.size()):
			if run[j] != first:
				uniform = false
				break
		if uniform:
			_scenes_judged[first] = "window"
		# Kept at exactly one window, the way `_judge` keeps its own: the run only
		# ever needs its last `window` entries, and a trace of 550 samples would
		# otherwise carry all of them for the whole scan.
		run.remove_at(0)
	# The exit rule, read after the fact because "and never came back" is a
	# statement about the whole watch.
	for key in live_in.keys():
		if int(last_at[key]) < samples.size() - 1 and not _scenes_judged.has(key):
			_scenes_judged[key] = "left"


## Enter every marker of the movie in turn and judge each one.
##
## ## Why a container is the wrong unit
##
## A room in these titles is a **marker**, and the frames under it are its
## animation (`director-qa-playthrough`). The sweep above opens a container and
## watches wherever its first frame parks, which is one room of the ten or twenty
## a container holds -- so `visited: 52 of 52` has always described 52 entries into
## a title that declares **2,732** marker regions, and no line said so.
## `6b42a128` is the same mistake with the number printed: a walk that played one
## scene per container reported eighteen day-2 scenes as covered when they had
## never been entered.
##
## ## Why the jump is `go`, and what it does not carry
##
## `lingo_go_frame` is the movie's own mechanism -- `go("shore2")` is how the title
## moves between rooms of one container -- so a marker entered this way is entered
## by the same path the game uses, with the same movie open, the same casts loaded
## and the same globals in scope. It is **not** the same as arriving through the
## room that jumps: whatever that room's handler set before it jumped is missing,
## exactly as the container-level sweep arrives without the globals a room chain
## would have set. So this widens the existing cold-entry caveat from one entry per
## container to one per marker; it does not remove it, and the skill's rule still
## holds -- a scene finding is a lead to re-reach with `qa_walk`, not a filed bug.
##
## That is why scene verdicts are **reported and counted and never asserted**. The
## container-level assertions above are unchanged, and a mode that could turn the
## suite red on a room reached out of its own order would be a mode whose reds
## nobody trusts.
##
## Returns `{walked, findings, reopened, missed}`, where `missed` is jumps that
## did not put the playhead on the marker -- the one thing this mode asserts.
## Coverage is credited through `_credit`, the same path the container watch uses,
## so a scene the walk entered and could not judge is counted the same way
## whichever watch reached it.
func _scenes(preview: Node, audio: Node, movie: String, ticks: int, window: int,
		only: String, verbose: bool) -> Dictionary:
	var findings: Array[Dictionary] = []
	var file := movie.get_file()
	var frames: PackedInt32Array = _regions.get(file.to_lower(), PackedInt32Array())
	var walked := 0
	var reopened := 0
	var missed := 0
	if frames.size() <= 1:
		# One region is the container watch's own subject; walking it again buys
		# nothing but the wall clock it costs.
		return {"walked": 0, "findings": findings, "reopened": 0, "missed": 0}
	for index in frames.size():
		var at := int(frames[index])
		var labels = preview.get("_labels")
		var named := ""
		if labels != null:
			for marker in labels.markers:
				if int(marker["frame"]) == at:
					named = str(marker["name"])
					break
		if only != "" and not named.to_lower().contains(only):
			continue
		# The movie under the playhead is what `lingo_go_frame` moves, so a scene
		# that left for another container -- or a click that did, before the walk
		# started -- has to be undone before the next marker or the walk drives
		# somebody else's score. Counted, because a movie that leaves on every
		# marker is a result and not an overhead.
		if str(preview.call("movie_name")).to_lower() != file.to_lower():
			_reset_between(preview)
			preview.call("lingo_go_movie", movie, null)
			for _i in OPEN_FRAMES:
				await process_frame
			reopened += 1
			if preview.get("_score") == null:
				break
		preview.call("lingo_go_frame", at)
		# The anti-`6b42a128` reading, and it is taken **before the first await**
		# on purpose. `lingo_go_frame` sets `_index` itself and queues the frame
		# entry, so this asks only "did the playhead go where the walk sent it" --
		# a question about this file and the call it makes, with no room for the
		# movie to answer it. One frame later is a different question with a
		# different answer, because a room whose `enterFrame` jumps away has
		# already moved by then and would read as a walk that never arrived.
		var landed := int(preview.call("current_frame")) == at \
			and str(preview.call("movie_name")).to_lower() == file.to_lower()
		if not landed:
			missed += 1
		await process_frame
		# Where the movie put the playhead once it had a frame to do it in. Printed
		# rather than counted: a room that jumps out of itself on entry is the
		# movie's business, and it is also the case the line above must not be
		# read as.
		var stayed := int(preview.call("current_frame")) == at \
			and str(preview.call("movie_name")).to_lower() == file.to_lower()
		walked += 1
		# The settle is **watched and credited**, not merely waited out, and the
		# difference is a whole class of region. `MAINMENU.dir` declares a marker on
		# frame 0 and another on frame 1; the playhead is past the first before
		# eight ticks are up, so a settle that only counted ticks left that region
		# with no sample at all and the walk credited 10 of 12 markers while
		# entering all 12. A one-frame room the playhead demonstrably passes
		# through and leaves is exactly what the exit rule in `_credit` is for.
		#
		# A quarter of the wall ceiling, because this is eight ticks and not
		# ninety, and because a settle that sat out its full budget on a sound
		# would spend the scene's whole clock before the watch began.
		var settling: Dictionary = await _watch(
			preview, audio, SCENE_SETTLE, SCENE_CAP_MS / 4)
		_credit(settling, window)
		var trace: Dictionary = await _watch(preview, audio, ticks, SCENE_CAP_MS)
		_credit(trace, window)
		var seen := _judge("%s@%s" % [movie, named if named != "" else "f%d" % at],
			trace, window)
		seen["scene"] = named
		if str(seen["verdict"]) != "":
			findings.append(seen)
		if verbose or str(seen["verdict"]) != "":
			print("    %-9s %-24s f%-5d %s%s" % [
				"ok" if str(seen["verdict"]) == "" else str(seen["verdict"]),
				named if named != "" else "<unnamed>", at,
				"" if stayed else "(left on entry) ", str(seen["detail"])])
	return {"walked": walked, "findings": findings, "reopened": reopened,
		"missed": missed}


## A point the mouse can actually reach this sprite at, or null. The same scan
## `pause_holds.gd` uses, and for the same reason.
static func _reachable_point(preview: Node, sprite: Dictionary, channel: int) -> Variant:
	var rect: Rect2 = preview.call("_sprite_rect", sprite)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	for iy in 5:
		for ix in 9:
			var at := rect.position + Vector2(
				rect.size.x * (ix + 0.5) / 9.0, rect.size.y * (iy + 0.5) / 5.0)
			if int(preview.call("_channel_at", at)) == channel:
				return at
	return null


## Hand the session back to a state the next container can be judged from.
##
## Three things survive a `go to movie` and would make the next verdict about the
## last movie: a `quit`/`halt` that stopped the process, a Director `pause` that
## nothing will lift because the frame that could be clicked is gone, and any
## Movie-In-A-Window left open. Globals are deliberately *not* reset -- see the
## header on what the sweep does and does not simulate.
func _reset_between(preview: Node) -> void:
	var host = preview.get("_host")
	if host != null:
		host.stopped = false
		host.playback_paused = false
	preview.set_process(true)
	var windows: Dictionary = preview.get("_windows")
	if windows != null:
		for key in windows.keys():
			preview.call("lingo_forget_window", str(key), true)


## The two states in which the score's own clock legitimately stops counting.
## Everything else that stops it is a stall this sweep wants to sit through and
## report, not one to give up on early.
static func _clock_stopped(preview: Node) -> bool:
	var host = preview.get("_host")
	return host != null and (bool(host.playback_paused) or bool(host.stopped))


## Let the movie run `count` of its *own* score ticks, up to `cap_ms` real ms, and
## give up early on a movie whose clock has stopped -- see `QUIET_FRAMES`.
func _run_ticks(preview: Node, count: int, cap_ms: int) -> void:
	var until := int(preview.get("_ticks")) + count
	var start := Time.get_ticks_msec()
	var last := int(preview.get("_ticks"))
	var quiet := 0
	while int(preview.get("_ticks")) < until and Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		var now := int(preview.get("_ticks"))
		quiet = 0 if now != last else quiet + 1
		last = now
		if quiet >= (QUIET_FRAMES if _clock_stopped(preview) else QUIET_STALL):
			return


## Sample the playhead once per score tick for `budget` ticks.
##
## Real frames are awaited rather than ticked synthetically. That is load-bearing
## and not tidiness: a synthetic loop advances the runtime's clock and not the
## audio server's, so every sound stays busy for ever, every `soundBusy` guard
## holds, and every excuse this file grants would be granted to every trap it was
## built to find (`bugs.md` 22).
##
## The rate is **adaptive**, which is the only thing that makes the sweep usable
## on an art-heavy movie. A frame that spends 200 ms decoding a 2 MB backdrop
## used to leave the clock owing three or four score steps and pay all of them in
## one process frame, so the sampler saw one state where four had happened; the
## clock drops them now, and what is left is the cost itself -- an `--ff` of 60
## against a movie painting at three frames a second still asks for a step the
## sampler will not see for twenty frames. Measured before this existed:
## `piposh-dream`'s three `hatul` rooms
## came back at 0% coverage and were reported clean over a movie nobody had
## looked at. So the requested `--ff` is a *ceiling*: it is halved on any sample
## that skipped a tick and crept back up while none does, down to `FF_FLOOR`,
## which is below the rate every movie in these corpora is authored at and
## therefore asks the clock for less than one step per process frame.
##
## `budget` is spent on **unexcused** ticks -- what `_judgeable` accepts -- so a
## hold or a skipped tick is sampled and reported without being charged, and the
## real bound on a watch is `cap_ms`. See the header for why, and `bugs.md` 128 for
## what it was before.
##
## Returns `{samples, stride, errors, movies, ticks, live, ended}`, where `live` is
## the unexcused ticks obtained and `ended` is which of the three bounds stopped
## it: `budget`, `capped` or `stalled`.
func _watch(preview: Node, audio: Node, budget: int, cap_ms: int) -> Dictionary:
	var samples: Array[Dictionary] = []
	var errors: Dictionary = {}
	var stride := 0
	var clock = preview.get("_clock")
	var host = preview.get("_host")
	var interpreter = preview.get("_interpreter")
	var start := Time.get_ticks_msec()
	var began := int(preview.get("_ticks"))
	var last := began
	var quiet := 0
	# How many times the movie has asked `soundBusy`. The delta between two
	# samples is what says "this movie is waiting for a sound" as against "this
	# movie has a soundtrack"; see the header.
	var polls := 0 if host == null \
		else int((host.reached as Dictionary).get("soundbusy", 0))
	var rate := _ff
	var clean := 0
	# `(movie, frame)` the playhead has stood on, and the eligibility answer for
	# the ones it has come *back* to. Two dictionaries rather than one because
	# "seen once" and "probed" are different states: the probe is what costs, and
	# it is spent only on a state that has recurred, which is the only kind any
	# cycle verdict is read over.
	var arrived: Dictionary = {}
	var eligible: Dictionary = {}
	# Unexcused ticks obtained, which is what `budget` buys.
	var live := 0
	var ended := ""
	preview.set("_fast_forward_fps", rate)
	while live < budget and Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		# Polled every process frame rather than every score tick: the interpreter
		# clears `errors` at the start of every dispatch, so a failure recorded
		# between two ticks is gone by the next one.
		if interpreter != null:
			for message in interpreter.errors:
				errors[str(message)] = int(errors.get(str(message), 0)) + 1
		var now := int(preview.get("_ticks"))
		if now == last:
			quiet += 1
			# A clock that has stopped is either Director's `pause` or the movie
			# having halted, and both are answers rather than hangs. One sample is
			# still taken, so the report says which of them it was instead of
			# reporting the empty set as "nothing observed".
			if quiet >= (QUIET_FRAMES if _clock_stopped(preview) else QUIET_STALL):
				samples.append(_sample(preview, audio, clock, host, 1, polls))
				ended = "stalled"
				break
			continue
		quiet = 0
		var step := now - last
		stride = maxi(stride, step)
		last = now
		var asked := 0 if host == null \
			else int((host.reached as Dictionary).get("soundbusy", 0))
		var sample := _sample(preview, audio, clock, host, step, asked - polls)
		# Asked here, in the same process frame the sample was taken in, so the
		# answer is about the stage that sample describes. The order matters and
		# is the header's third property: the probe fires on the second arrival at
		# a state, a cycle window necessarily contains a second arrival, so no
		# window that can be called a trap is built out of unprobed samples.
		var key := "%s:%d" % [str(sample["movie"]).get_file(), int(sample["frame"])]
		if not eligible.has(key) and arrived.has(key):
			eligible[key] = _any_clickable(preview)
		arrived[key] = true
		sample["clickable"] = bool(eligible.get(key, false))
		samples.append(sample)
		if _judgeable(sample):
			live += 1
		polls = asked
		# The control loop. Down hard on any skipped tick, up gently while none
		# is skipped, so a movie that is only briefly expensive -- one cold
		# backdrop -- is not left crawling for the rest of its watch.
		if step > 1:
			rate = maxf(rate * 0.5, FF_FLOOR)
			clean = 0
			preview.set("_fast_forward_fps", rate)
		elif rate < _ff:
			clean += 1
			if clean >= FF_RECOVER:
				clean = 0
				rate = minf(rate * 1.5, _ff)
				preview.set("_fast_forward_fps", rate)
	var movies: Dictionary = {}
	for sample in samples:
		movies[str(sample["movie"])] = true
	# Which of the three bounds stopped the watch, decided from the state rather
	# than from the exit path. **That distinction is the difference between a
	# control and a decoration**: the first version of this inferred "the ceiling"
	# from `live < budget`, so putting the budget back on raw score ticks -- the
	# defect this change removes -- relabelled every watch as capped and the
	# assertion below passed over it. `short` is the fourth answer, meaning the
	# loop stopped for a reason this function cannot name, and it is what a budget
	# charged for holds looks like from here.
	if ended != "stalled":
		if live >= budget:
			ended = "budget"
		elif Time.get_ticks_msec() - start >= cap_ms:
			ended = "capped"
		else:
			ended = "short"
	return {"samples": samples, "stride": stride, "errors": errors,
		"movies": movies.keys(), "ticks": int(preview.get("_ticks")) - began,
		"live": live, "ended": ended}


## What the player is looking at, and whether anything can say why.
##
## **Only the drawn count, deliberately.** Eligibility was in here and is the
## single most expensive question the engine can be asked -- `_responds_to_mouse`
## reaches the hit-pixel path, and asking it of every sprite of every sample cost
## a factor of nine: the sweep ran at 6.5 score ticks a second where the
## fast-forward had asked for 60, and, worse, the process loop then fell so far
## behind the clock that the accumulator of the day was taking four score steps
## between two samples. A period-2 ping-pong sampled every four steps reads as a
## *constant*, so the cost was not just slowness -- it blinded the detector to its
## own subject. The stride carried on every sample is what caught it, and that is
## why it is carried.
##
## Nothing is lost: no verdict reads eligibility. `--click` asks it once per
## container, where it belongs.
static func _sample(preview: Node, audio: Node, clock, host, stride: int,
		polls: int) -> Dictionary:
	var drawn := 0
	for raw in preview.call("frame_sprites"):
		# `{}` is a sprite a script has hidden: it is not on the stage, and counting
		# it would count a black screen as a populated one.
		if not (preview.call("_effective", raw) as Dictionary).is_empty():
			drawn += 1
	var reason := "" if clock == null else str(clock.hold_reason())
	if host != null and bool(host.playback_paused):
		reason = "pause"
	elif host != null and bool(host.stopped):
		reason = "halted"
	elif polls > 0:
		# The movie asked `soundBusy` since the last sample. It is only waiting if
		# something is in fact playing -- a poll that answers "no" is the tick the
		# room moves on, and excusing it would excuse the frame after the answer.
		for channel in range(1, SOUND_CHANNELS + 1):
			if bool(audio.call("sound_busy", channel)):
				reason = "wait for sound %d" % channel
				break
	var windows: Dictionary = preview.get("_windows")
	return {
		"movie": str(preview.call("movie_name")),
		"frame": int(preview.call("current_frame")),
		"drawn": drawn,
		"hold": reason,
		"stride": stride,
		"windowed": windows != null and not windows.is_empty(),
		# Filled in by `_watch` on the states it probes, and left false everywhere
		# else. False means "no eligible sprite was found here", which is the
		# reading that keeps a finding rather than the one that excuses it.
		"clickable": false,
	}


## Does anything on the stage right now answer the mouse?
##
## The engine's own §4.3 eligibility (`_responds_to_mouse`), asked of the drawn
## sprites in channel order and stopped at the first yes -- which in a room with a
## clickable backdrop is the first question. `_poke`'s extra `_reachable_point`
## scan is deliberately **not** done here: it costs up to 45 `_channel_at`
## descents a sprite, and the claim this answer supports is "the player has
## something to click", not "this exact pixel routes there".
##
## `{}` from `_effective` is a sprite a script has hidden, and a hidden sprite is
## not a hotspot -- the same reading `_sample` takes for the drawn count.
static func _any_clickable(preview: Node) -> bool:
	for raw in preview.call("frame_sprites"):
		var sprite: Dictionary = preview.call("_effective", raw)
		if sprite.is_empty():
			continue
		if bool(preview.call("_responds_to_mouse", sprite)):
			return true
	return false


## Is this tick one a verdict can be read over, and therefore one the watch pays
## for?
##
## **One predicate, three readers**, which is the point of it being a function: the
## budget in `_watch` charges for exactly the ticks `_judge` builds a window out of
## and `_longest_run` measures. The way this goes wrong is one of the three
## drifting from the other two, so `_assert_rules` asserts the equivalence rather
## than the three statements.
##
## A hold is an *answer* to "why is the playhead not moving" and a skipped tick is
## an *unknown* -- the playhead went somewhere this sampler never saw. Neither can
## carry a finding, so neither is charged and both clear the window.
static func _judgeable(sample: Dictionary) -> bool:
	return str(sample["hold"]) == "" and int(sample["stride"]) <= 1


## The longest stretch of consecutive judgeable ticks in a watch: the longest
## window any rule could have been read over. Below `--window` there was none, and
## that is what `unjudged` counts -- not how many ticks were sampled, which a movie
## held on a sound for its whole watch answers with the full number.
static func _longest_run(samples: Array) -> int:
	var best := 0
	var run := 0
	for sample_value in samples:
		if _judgeable(sample_value as Dictionary):
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return best


## Turn a watch into a verdict.
##
## The window is *cleared* by an excused tick rather than annotated, so what is
## looked for is `window` consecutive score ticks the engine cannot account for.
## The worst window in the run wins, because a movie that settles into a trap
## after eight healthy seconds is still a movie the player cannot leave.
static func _judge(movie: String, trace: Dictionary, window: int) -> Dictionary:
	var errors: Dictionary = trace["errors"]
	var samples: Array = trace["samples"]
	var run: Array = []
	var worst: Dictionary = {}
	# A cycle the trap arm declined because the player has something to click.
	# It is not a finding and it is not nothing either, so it is carried out
	# separately rather than through `worst`: routing it through there would let a
	# verdict-less window outrank -- and therefore hide -- a `lingo` finding.
	var idle := ""
	for sample_value in samples:
		var sample: Dictionary = sample_value
		# A hold is an answer, and a *skipped* tick is an unknown -- the playhead
		# moved somewhere this sampler never saw. Both break the run, because a
		# window is only evidence if it is `window` consecutive ticks that were
		# both watched and unexplained. `_judgeable` is the same predicate the
		# watch's tick budget is charged against, deliberately: the ticks paid for
		# are the ticks a verdict can be read over and no others.
		if not _judgeable(sample):
			run.clear()
			continue
		run.append(sample)
		if run.size() < window:
			continue
		var found := _read_window(run.slice(run.size() - window))
		if not found.is_empty():
			if str(found["verdict"]) == "":
				if idle == "":
					idle = str(found["detail"])
			elif worst.is_empty() or int(SEVERITY.get(found["verdict"], 0)) \
					> int(SEVERITY.get(worst["verdict"], 0)):
				worst = found
		run.remove_at(0)

	if not worst.is_empty():
		var seen := _finding(movie, str(worst["verdict"]), str(worst["detail"]))
		if not errors.is_empty():
			seen["detail"] = "%s; lingo: %s" % [seen["detail"], _errors(errors)]
		seen["idle"] = idle
		return seen
	# A Lingo error on a movie that is otherwise well behaved is still a finding:
	# "step budget exhausted" means a handler was cut off part-way, and what it
	# did not get to do is invisible until something else goes wrong.
	if not errors.is_empty():
		var faulty := _finding(movie, "lingo", _errors(errors))
		faulty["idle"] = idle
		return faulty
	var stuck := _sound_park(samples, window)
	if stuck != "":
		var parked := _finding(movie, "sound-park", stuck)
		parked["idle"] = idle
		return parked
	var told := _healthy(samples)
	var clean := _finding(movie, "",
		told if idle == "" else "%s; idle loop: %s" % [told, idle])
	clean["idle"] = idle
	return clean


## The `soundBusy` clause's own blind spot, reported rather than left silent.
##
## The excuse is granted whenever the movie polls `soundBusy` and *some* channel
## is playing, and `reached` cannot say which channel was asked about. So a loop
## waiting on a channel that will never finish -- one carrying a looped
## soundtrack, say -- is excused for ever and the trap it is sitting in is
## invisible to every rule above. What that case still cannot hide is its own
## shape: a movie that spends a whole watch inside `CYCLE_MAX` states with the
## sound excuse covering every one of them is either waiting on a very long clip
## or is not waiting at all, and a human can tell in one listen.
##
## Reported at the lowest severity and never asserted, because the legitimate
## reading is real: an uninterruptible cut scene looks exactly like this.
static func _sound_park(samples: Array, window: int) -> String:
	if samples.size() < window:
		return ""
	var states: Dictionary = {}
	for sample_value in samples:
		var sample: Dictionary = sample_value
		if not str(sample["hold"]).begins_with("wait for sound"):
			return ""
		states["%s:%d" % [str(sample["movie"]).get_file(), int(sample["frame"])]] = \
			int(sample["drawn"])
	if states.size() > CYCLE_MAX:
		return ""
	return "waiting on sound for all %d watched tick(s) inside %d state(s): %s" % [
		samples.size(), states.size(), _states(states)]


static func _errors(errors: Dictionary) -> String:
	var out: Array[String] = []
	for message in errors:
		out.append("%s x%d" % [str(message), int(errors[message])])
	out.sort()
	return ", ".join(out.slice(0, 4))


## What a clean container looked like, so a `--verbose` line says something.
static func _healthy(samples: Array) -> String:
	if samples.is_empty():
		return "no score ticks observed"
	var states: Dictionary = {}
	var holds: Dictionary = {}
	var last: Dictionary = samples[-1]
	for sample_value in samples:
		var sample: Dictionary = sample_value
		states["%s:%d" % [str(sample["movie"]), int(sample["frame"])]] = true
		var reason := str(sample["hold"])
		if reason != "":
			holds[reason] = int(holds.get(reason, 0)) + 1
	var named: Array[String] = []
	for reason in holds:
		named.append("%s x%d" % [str(reason), int(holds[reason])])
	named.sort()
	return "%d state(s) over %d tick(s), ends on %s f%d with %d drawn%s" % [
		states.size(), samples.size(), str(last["movie"]).get_file(),
		int(last["frame"]), int(last["drawn"]),
		"" if named.is_empty() else ", held: %s" % ", ".join(named)]


## The rules, over one window of unexplained score ticks. `{}` is "nothing wrong".
static func _read_window(w: Array) -> Dictionary:
	var states: Dictionary = {}
	var movies: Dictionary = {}
	var blank: Dictionary = {}
	var windowed := false
	# Whether any state in this window carries a sprite that answers the mouse.
	# Only the trap arm reads it; see the header for why not the others.
	var clickable := false
	# How many times the playhead *arrived* somewhere, counting a stay as one
	# arrival. Compared against the number of distinct states below, this is the
	# difference between a cycle and a walk; see the guard for why a set cannot
	# answer it.
	var arrivals := 0
	var previous := ""
	for sample_value in w:
		var sample: Dictionary = sample_value
		var key := "%s:%d" % [str(sample["movie"]).get_file(), int(sample["frame"])]
		states[key] = int(sample["drawn"])
		movies[str(sample["movie"]).get_file()] = true
		if int(sample["drawn"]) == 0:
			blank[key] = true
		if bool(sample["windowed"]):
			windowed = true
		if bool(sample.get("clickable", false)):
			clickable = true
		if key != previous:
			arrivals += 1
			previous = key
	var where := _states(states)
	# The one exemption. A Movie-In-A-Window has its own playhead and paints over
	# the stage, so a bare stage underneath one is not a black screen.
	if not blank.is_empty() and windowed:
		blank.clear()

	if states.size() == 1:
		if blank.is_empty():
			return {}
		return {"verdict": "blank-park",
			"detail": "parked on %s for %d tick(s) with nothing drawn and no hold"
				% [where, w.size()]}
	if states.size() > CYCLE_MAX:
		return {}
	# **A walk is not a cycle.** Every rule below is about a playhead that keeps
	# coming back, and the three of them used to be asked as a question about a
	# *set*: "are there two to four states here". A playhead that steps through
	# four frames and then parks on the fourth answers that identically, and one
	# window position out of the whole watch straddles the walk -- which `_judge`
	# then keeps, because it keeps the worst. That is the entire content of the
	# `SACHROOM.dir` finding: 24 -> 25 -> 26 -> 27 -> 28 and then 116 ticks
	# parked, reported as a confinement to four states.
	#
	# A state that is returned to produces a second arrival at the same key, so a
	# cycle has strictly more arrivals than states and a walk has exactly as many
	# as it has states. Nothing is lost by declining the walk: if the frame it
	# parks on is a genuine dead end, the windows *after* the walk hold that one
	# state alone and `blank-park` reads them, and if it is genuinely confined it
	# comes back round and there is a second arrival to see.
	#
	# The guard sits above `ping-pong` deliberately, so it covers that verdict as
	# well: one `play` into a second movie that then parks there is two states and
	# two arrivals, which is a walk across a movie boundary and not two containers
	# trading places. The bug this file was written from alternates for as long as
	# the screen is open, so it has sixty arrivals and still reads.
	#
	# `sound-park` is left alone on purpose. It runs off `_judge`'s own path and
	# never reaches here, and its claim is not about cycling at all -- it reports
	# that the `soundBusy` excuse covered *every* watched tick, which is true of a
	# walk-then-park too and is worth saying either way.
	if arrivals <= states.size():
		return {}
	if movies.size() >= 2:
		return {"verdict": "ping-pong",
			"detail": "%d movie(s) trading places for %d tick(s): %s"
				% [movies.size(), w.size(), where]}
	if not blank.is_empty():
		return {"verdict": "blank-cycle",
			"detail": "cycling for %d tick(s) through a frame with nothing drawn: %s"
				% [w.size(), where]}
	# **The one thing that separates an authored idle loop from a confinement**,
	# and it is not a fact about the playhead -- see the header. A room whose loop
	# offers a click is a room waiting for one; a room whose loop offers none is
	# one the player has no move in. Reported rather than dropped: the empty
	# verdict is what makes this a counted `idle loops` line instead of silence.
	if clickable:
		return {"verdict": "",
			"detail": "cycling through %d state(s) for %d tick(s) with a sprite that "
				% [states.size(), w.size()]
				+ "answers the mouse, so not a trap: %s" % where}
	return {"verdict": "trap",
		"detail": "confined to %d state(s) for %d tick(s) with no hold and nothing "
			% [states.size(), w.size()]
			+ "that answers the mouse: %s" % where}


## `movie:frame(drawn)` for each state, sorted, so two runs print the same line.
static func _states(states: Dictionary) -> String:
	var keys: Array = states.keys()
	keys.sort()
	var out: Array[String] = []
	for key in keys:
		out.append("%s(%d)" % [str(key), int(states[key])])
	return " <-> ".join(out)


static func _finding(movie: String, verdict: String, detail: String) -> Dictionary:
	return {"movie": movie, "verdict": verdict, "detail": detail}
