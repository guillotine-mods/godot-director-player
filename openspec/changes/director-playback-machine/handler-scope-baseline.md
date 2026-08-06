# Handler scope baseline

Task 4.2 of `director-playback-machine`. What the flat, first-loaded-wins movie-script handler table in
`lingo/lingo_interpreter.gd` actually resolves to today, measured before task 4.3 changes it.

Harness: `tools/lingo_handler_scope.gd`.

```
godot --headless --script tools/lingo_handler_scope.gd
```

`-- core` or `-- full` runs one scope only. The unelided transcript is `handler-scope-baseline.txt` beside
this file; the excerpts below come from it, with Godot's banner, its case-mismatch warnings and the shutdown
resource warning stripped.

Measured 2026-08-05, Godot 4.7.1, at HEAD `c35c48ee`. `lingo/` also carried uncommitted work in progress on
the diagnostics sink at the time; it adds reporting only and leaves `load_bundle`, `prepare_movie` and
`_movie_handlers` untouched. The run was repeated after that work was in the tree and every number was
identical.

## How it measures

Two passes, both driving the real `RenderModelLoader` and the real `LingoEngine`, so nothing in the harness
re-implements resolution.

Pass A builds a fresh `LingoEngine` per movie, which is what `tools/lingo_converge.gd` already does. That
engine's table covers the movie's own `data/lingo/<MOVIE>/` directory plus every non-internal cast library
the movie links. It is the table Decision 12 asks for.

Pass B carries one `LingoEngine` across every movie in turn, which is what `director/director_runtime.gd`
holds: `lingo` is built once in `boot()` and `prepare_movie` only ever adds to it.

A name whose winning owner differs between the passes is one the running game resolves outside the movie
asking for it, in one of two shapes:

- **shadowed**: the movie defines the name itself and loses to a movie loaded earlier.
- **leaked in**: the movie never defines the name and can call it anyway.

A cast library the movie links is not counted as a foreign owner. Only another movie's own directory counts.

Each definition also carries a hash of its handler body, so a resolution that crosses a directory can be
told from one that also changes what runs. This matters: `data/lingo/DAY1/wonder.json` and
`data/lingo/SEA1/wonder.json` hold byte-identical `walkonby` bodies under different member numbers, and
resolving one for the other is invisible. `whatodoeveryframe` in those same two files does not match.

Pass B's load order is DAY1 first, then the rest alphabetically. DAY1 is the game's start movie and the
save-file default (`director_runtime.gd` `_snapshot_return_into_state`). Order is what decides who wins
today, which is the defect; under Decision 12 the result does not depend on it.

## Scopes

Two scopes, because the number depends entirely on how many movies the session has entered.

- **core**: `DAY1 NIGHT1 HOTEL1 SEA1 AIR1`, the set `tools/lingo_converge.gd` sweeps, kept so the figures
  stay comparable with the prior analysis that produced the design's estimate.
- **full**: all 71 playable movies from the export index. The zero-frame exports that are really .CST cast
  libraries are excluded, because `goto_movie` refuses them and counting them would manufacture leaks.

## Headline numbers

| | core (5 movies) | full (71 movies) |
|---|---|---|
| handler names with more than one definition | 10 | 13 |
| of those, with more than one distinct body | 9 | 12 |
| distinct handler names resolving outside their movie | 14 | 53 |
| of those, resolving to DAY1 | 9 | 9 |
| shadowed resolutions | 26 | 63 |
| of those, landing on a different body | 21 | 58 |
| leaked-in resolutions | 22 | 1579 |
| movies resolving at least one handler outside themselves | 4 of 5 | 70 of 71 |
| owner winning the most foreign resolutions | DAY1 (36) | DAY1 (630) |

Design Decision 12 estimates "19 handler names with multiple definitions resolve to DAY1's copy". Nothing
measured here lands on 19. The closest real figures are 10 duplicated names over the core set and 13 over
the full set, of which 9 distinct names resolve to DAY1 in both scopes. The 19 is recorded as an estimate
this measurement does not reproduce. Task 4.7 should be checked against the numbers in this file.

The full-scope leaked-in total of 1579 is dominated by movies with no `data/lingo/` directory of their own:
they inherit whatever the sweep has accumulated. Per-movie counts are in the table below.

## What 4.7 should expect

Not zero everywhere. This harness treats "legitimate" as the movie's own directory plus the cast libraries
that movie's own `cast_libs` name. Decision 12's shared archive is a further, global lookup, and resolutions
into it are correct once 4.4 lands even for movies that do not list it.

MASTER is the presumed archive, which 4.4 should confirm. The evidence for it here: MASTER never appears as
a foreign owner in the core scope, because all five core movies link it, and it accounts for 130 of the
full-scope foreign resolutions, all in movies that do not.

So the 4.7 criterion is **zero foreign resolutions that are not through the shared archive**. In full scope
that means the 1579 + 63 total should fall to at most the 130 currently attributed to MASTER, and in core
scope to zero. Any resolution still owned by DAY1, AIR1, HOTEL1, SEA1, ARCADE1, ARCADE2, CHESS, HEZSAVE,
STRTGAME or TENNIS is a failure.

## Core scope output

```
================================================================
scope: core, 5 movies, load order DAY1, AIR1, HOTEL1, NIGHT1, SEA1
================================================================

movie           own  reachable   shadowed leaked in
DAY1             22         22          0         0
AIR1             21         24          6         3
HOTEL1           23         27          7         4
NIGHT1           22         27          9         5
SEA1             21         31          4        10
TOTAL                                  26        22
of the 26 shadowed resolutions, 21 land on a definition with a different body

handler names with more than one definition: 10 (9 with more than one body)
  dwarfscont               bodies:2  DAY1/wonder (MovieScript 246) | NIGHT1/night2 (MovieScript 246)
  dwarfscont2              bodies:2  DAY1/wonder (MovieScript 246) | NIGHT1/night2 (MovieScript 246)
  gamad                    bodies:2  DAY1/wonder (MovieScript 272 - gamad) | NIGHT1/night2 (MovieScript 272 - gamad)
  objecttalktime           bodies:3  DAY1/wonder (MovieScript 248) | AIR1/island2 (MovieScript 203) | HOTEL1/book (MovieScript 203) | NIGHT1/night2 (MovieScript 248) | SEA1/wonder (MovieScript 989)
  peoplecont               bodies:4  DAY1/wonder (MovieScript 246) | AIR1/island2 (MovieScript 202) | HOTEL1/book (MovieScript 202) | NIGHT1/night2 (MovieScript 246)
  peoplefunk               bodies:4  DAY1/wonder (MovieScript 246) | AIR1/island2 (MovieScript 202) | HOTEL1/book (MovieScript 202) | NIGHT1/night2 (MovieScript 246)
  peopleinroom             bodies:2  AIR1/island2 (MovieScript 202) | HOTEL1/book (MovieScript 202)
  talkproc                 bodies:5  DAY1/wonder (MovieScript 248) | AIR1/island2 (MovieScript 203) | HOTEL1/book (MovieScript 203) | NIGHT1/night2 (MovieScript 248) | SEA1/wonder (MovieScript 989)
  walkonby                 bodies:1  DAY1/wonder (MovieScript 27 - walkonby) | AIR1/island2 (MovieScript 23 - walkonby) | HOTEL1/book (MovieScript 23 - walkonby) | NIGHT1/night2 (MovieScript 27 - walkonby) | SEA1/wonder (MovieScript 25 - walkonby)
  whatodoeveryframe        bodies:5  DAY1/wonder (MovieScript 28 - whatodoeveryframe) | AIR1/island2 (MovieScript 24 - whatodoeveryframe) | HOTEL1/book (MovieScript 24 - whatodoeveryframe) | NIGHT1/night2 (MovieScript 28 - whatodoeveryframe) | SEA1/wonder (MovieScript 26 - whatodoeveryframe)

shadowed: the movie defines the name and does not get its own copy
(differs = the definition that wins is not byte-identical to the one it displaces)
  AIR1       objecttalktime           wants AIR1       gets DAY1       DIFFERS   (MovieScript 248)
  AIR1       peoplecont               wants AIR1       gets DAY1       DIFFERS   (MovieScript 246)
  AIR1       peoplefunk               wants AIR1       gets DAY1       DIFFERS   (MovieScript 246)
  AIR1       talkproc                 wants AIR1       gets DAY1       DIFFERS   (MovieScript 248)
  AIR1       walkonby                 wants AIR1       gets DAY1       same      (MovieScript 27 - walkonby)
  AIR1       whatodoeveryframe        wants AIR1       gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  HOTEL1     objecttalktime           wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 248)
  HOTEL1     peoplecont               wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 246)
  HOTEL1     peoplefunk               wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 246)
  HOTEL1     peopleinroom             wants HOTEL1     gets AIR1       DIFFERS   (MovieScript 202)
  HOTEL1     talkproc                 wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 248)
  HOTEL1     walkonby                 wants HOTEL1     gets DAY1       same      (MovieScript 27 - walkonby)
  HOTEL1     whatodoeveryframe        wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  NIGHT1     dwarfscont               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     dwarfscont2              wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     gamad                    wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 272 - gamad)
  NIGHT1     objecttalktime           wants NIGHT1     gets DAY1       same      (MovieScript 248)
  NIGHT1     peoplecont               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     peoplefunk               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     talkproc                 wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 248)
  NIGHT1     walkonby                 wants NIGHT1     gets DAY1       same      (MovieScript 27 - walkonby)
  NIGHT1     whatodoeveryframe        wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  SEA1       objecttalktime           wants SEA1       gets DAY1       DIFFERS   (MovieScript 248)
  SEA1       talkproc                 wants SEA1       gets DAY1       DIFFERS   (MovieScript 248)
  SEA1       walkonby                 wants SEA1       gets DAY1       same      (MovieScript 27 - walkonby)
  SEA1       whatodoeveryframe        wants SEA1       gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)

leaked in: reachable in the movie though none of its casts define it
  AIR1       3: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1>
  HOTEL1     4: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> planefunk<AIR1>
  NIGHT1     5: bk2peoplefunk<HOTEL1> finishday<HOTEL1> ishspec<HOTEL1> peopleinroom<AIR1> planefunk<AIR1>
  SEA1       10: bk2peoplefunk<HOTEL1> dwarfscont<DAY1> dwarfscont2<DAY1> finishday<HOTEL1> gamad<DAY1> ishspec<HOTEL1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1>

linked cast directories in this scope: BOOK BYAIR BYSEA HEZI HOTEL ISLAND ISLAND2 MASTER NIGHT NIGHT2 WONDER
of those, also a playable movie in this scope: (none)
distinct handler names resolving outside their movie: 14 (9 of them to DAY1)
  bk2peoplefunk dwarfscont dwarfscont2 finishday gamad ishspec objecttalktime peoplecont peoplefunk peopleinroom planefunk talkproc walkonby whatodoeveryframe

movies resolving at least one handler outside themselves: 4 of 5
owner winning the most foreign resolutions: DAY1 (36)
foreign resolutions by owner: AIR1=6 DAY1=36 HOTEL1=6
```

## Full scope output

The leaked-in section is elided after the first ten movies: it runs to 70 lines and 28 KB. The unelided
version is in `handler-scope-baseline.txt`.

```

================================================================
scope: full, 71 movies, load order DAY1, AIR1, ALLIN, ARCADE1, ARCADE2, BIGEL, BLACK, CHESS…
================================================================

movie           own  reachable   shadowed leaked in
DAY1             22         22          0         0
AIR1             21         24          6         3
ALLIN            14         24          1        10
ARCADE1          14         25          0        11
ARCADE2          15         27          0        12
BIGEL            14         27          1        13
BLACK             0         27          0        27
CHESS            15         29          0        14
DAGI             14         29          1        15
DETECTIV          0         29          0        29
DIVEFIGT         13         29          0        16
DTCDAY2          14         29          1        15
ENDMOVI1         14         29          1        15
ENDMOVI2         13         29          0        16
ENDMOVI3         13         29          0        16
ENDMOVI4         13         29          0        16
ENDMOVI5         13         29          0        16
EXODUS           13         29          0        16
FIGTAIR          13         29          0        16
FIGTBRJ          13         29          0        16
FIGTNIGT         14         29          1        15
FUGEL            14         29          1        15
GARDUG           14         29          1        15
GOLDDEAD         14         29          1        15
HATDAY1          14         29          1        15
HATDAY2          14         29          1        15
HATDAY3          14         29          1        15
HATSIKUM         14         29          1        15
HATULI            0         29          0        29
HEZI              0         29          0        29
HEZNIGT           0         29          0        29
HEZSAVE          19         35          0        16
HOTEL1           23         38          7        15
IGUL             14         38          1        24
INVESTIG         14         38          1        24
ISHDAY1          14         38          1        24
ISHURUN           0         38          0        38
JO               14         38          1        24
JOKE             13         38          0        25
JOKERS            0         38          0        38
KAROZ            14         38          1        24
MAP              13         38          0        25
MASTER           13         38          0        25
MENADAY2         14         38          1        24
MIROLO           14         38          1        24
MORN2            14         38          1        24
MORN3            14         38          1        24
MRFDAY1          14         38          1        24
MURDER1          14         38          1        24
NIGHT1           22         38          9        16
NITE1            14         38          1        24
PANTER           14         38          1        24
PATDAY1          14         38          1        24
PPTSHOW          13         38          0        25
PSIK             14         38          1        24
RECEPT           13         38          0        25
RUNAWAY          13         38          0        25
SABMON            0         38          0        38
SABMON1          14         38          1        24
SABMON2          14         38          1        24
SAMNIGHT         14         38          1        24
SAVELOAD         13         38          0        25
SEA1             21         42          4        21
SHUFFLE          13         42          0        29
SLEEP1           14         42          1        28
SLEEP2           14         42          1        28
STRTGAME          8         48          2        40
TENNIS           18         53          0        35
TOFIRCPT         14         53          1        39
WONDER            0         53          0        53
ZARA             14         53          1        39
TOTAL                                  63      1579
of the 63 shadowed resolutions, 58 land on a definition with a different body

handler names with more than one definition: 13 (12 with more than one body)
  cursorfunk               bodies:2  MASTER/External (MovieScript 13 - cursor funk) | ALLIN/master (MovieScript 120) | BIGEL/Internal (MovieScript 95) | DAGI/master (MovieScript 27) | DTCDAY2/master (MovieScript 83) | ENDMOVI1/Internal (MovieScript 84) | FIGTNIGT/master (MovieScript 133) | FUGEL/Internal (MovieScript 110) | GARDUG/Internal (MovieScript 91) | GOLDDEAD/Internal (MovieScript 38) | HATDAY1/master (MovieScript 58) | HATDAY2/master (MovieScript 163) | HATDAY3/master (MovieScript 163) | HATSIKUM/master (MovieScript 56) | IGUL/master (MovieScript 31) | INVESTIG/master (MovieScript 121) | ISHDAY1/Internal (MovieScript 50) | JO/master (MovieScript 41) | KAROZ/Internal (MovieScript 112) | MENADAY2/MASTER (MovieScript 54) | MIROLO/master (MovieScript 227) | MORN2/Internal (MovieScript 81) | MORN3/master (MovieScript 39) | MRFDAY1/Internal (MovieScript 37) | MURDER1/MASTER (MovieScript 47) | NITE1/master (MovieScript 88) | PANTER/Internal (MovieScript 64) | PATDAY1/master (MovieScript 29) | PSIK/Internal (MovieScript 71) | SABMON1/master (MovieScript 110) | SABMON2/MASTER (MovieScript 125) | SAMNIGHT/Internal (MovieScript 57) | SLEEP1/Internal (MovieScript 168) | SLEEP2/Internal (MovieScript 7) | TOFIRCPT/Internal (MovieScript 39) | ZARA/master (MovieScript 84)
  dwarfscont               bodies:2  DAY1/wonder (MovieScript 246) | NIGHT1/night2 (MovieScript 246)
  dwarfscont2              bodies:2  DAY1/wonder (MovieScript 246) | NIGHT1/night2 (MovieScript 246)
  fromnow                  bodies:2  MASTER/External (MovieScript 137 - cut snd) | STRTGAME/Internal (MovieScript 306)
  gamad                    bodies:2  DAY1/wonder (MovieScript 272 - gamad) | NIGHT1/night2 (MovieScript 272 - gamad)
  objecttalktime           bodies:3  DAY1/wonder (MovieScript 248) | AIR1/island2 (MovieScript 203) | HOTEL1/book (MovieScript 203) | NIGHT1/night2 (MovieScript 248) | SEA1/wonder (MovieScript 989)
  peoplecont               bodies:4  DAY1/wonder (MovieScript 246) | AIR1/island2 (MovieScript 202) | HOTEL1/book (MovieScript 202) | NIGHT1/night2 (MovieScript 246)
  peoplefunk               bodies:5  DAY1/wonder (MovieScript 246) | AIR1/island2 (MovieScript 202) | ALLIN/master (MovieScript 120) | BIGEL/Internal (MovieScript 95) | DAGI/master (MovieScript 27) | DTCDAY2/master (MovieScript 83) | ENDMOVI1/Internal (MovieScript 84) | FIGTNIGT/master (MovieScript 133) | FUGEL/Internal (MovieScript 110) | GARDUG/Internal (MovieScript 91) | GOLDDEAD/Internal (MovieScript 38) | HATDAY1/master (MovieScript 58) | HATDAY2/master (MovieScript 163) | HATDAY3/master (MovieScript 163) | HATSIKUM/master (MovieScript 56) | HOTEL1/book (MovieScript 202) | IGUL/master (MovieScript 31) | INVESTIG/master (MovieScript 121) | ISHDAY1/Internal (MovieScript 50) | JO/master (MovieScript 41) | KAROZ/Internal (MovieScript 112) | MENADAY2/MASTER (MovieScript 54) | MIROLO/master (MovieScript 227) | MORN2/Internal (MovieScript 81) | MORN3/master (MovieScript 39) | MRFDAY1/Internal (MovieScript 37) | MURDER1/MASTER (MovieScript 47) | NIGHT1/night2 (MovieScript 246) | NITE1/master (MovieScript 88) | PANTER/Internal (MovieScript 64) | PATDAY1/master (MovieScript 29) | PSIK/Internal (MovieScript 71) | SABMON1/master (MovieScript 110) | SABMON2/MASTER (MovieScript 125) | SAMNIGHT/Internal (MovieScript 57) | SLEEP1/Internal (MovieScript 168) | SLEEP2/Internal (MovieScript 7) | TOFIRCPT/Internal (MovieScript 39) | ZARA/master (MovieScript 84)
  peopleinroom             bodies:2  AIR1/island2 (MovieScript 202) | HOTEL1/book (MovieScript 202)
  talkproc                 bodies:5  DAY1/wonder (MovieScript 248) | AIR1/island2 (MovieScript 203) | HOTEL1/book (MovieScript 203) | NIGHT1/night2 (MovieScript 248) | SEA1/wonder (MovieScript 989)
  tlkpath                  bodies:2  MASTER/External (MovieScript 130) | STRTGAME/Internal (MovieScript 260)
  walkonby                 bodies:1  DAY1/wonder (MovieScript 27 - walkonby) | AIR1/island2 (MovieScript 23 - walkonby) | HOTEL1/book (MovieScript 23 - walkonby) | NIGHT1/night2 (MovieScript 27 - walkonby) | SEA1/wonder (MovieScript 25 - walkonby)
  whatodoeveryframe        bodies:5  DAY1/wonder (MovieScript 28 - whatodoeveryframe) | AIR1/island2 (MovieScript 24 - whatodoeveryframe) | HOTEL1/book (MovieScript 24 - whatodoeveryframe) | NIGHT1/night2 (MovieScript 28 - whatodoeveryframe) | SEA1/wonder (MovieScript 26 - whatodoeveryframe)

shadowed: the movie defines the name and does not get its own copy
(differs = the definition that wins is not byte-identical to the one it displaces)
  AIR1       objecttalktime           wants AIR1       gets DAY1       DIFFERS   (MovieScript 248)
  AIR1       peoplecont               wants AIR1       gets DAY1       DIFFERS   (MovieScript 246)
  AIR1       peoplefunk               wants AIR1       gets DAY1       DIFFERS   (MovieScript 246)
  AIR1       talkproc                 wants AIR1       gets DAY1       DIFFERS   (MovieScript 248)
  AIR1       walkonby                 wants AIR1       gets DAY1       same      (MovieScript 27 - walkonby)
  AIR1       whatodoeveryframe        wants AIR1       gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  ALLIN      peoplefunk               wants ALLIN      gets DAY1       DIFFERS   (MovieScript 246)
  BIGEL      peoplefunk               wants BIGEL      gets DAY1       DIFFERS   (MovieScript 246)
  DAGI       peoplefunk               wants DAGI       gets DAY1       DIFFERS   (MovieScript 246)
  DTCDAY2    peoplefunk               wants DTCDAY2    gets DAY1       DIFFERS   (MovieScript 246)
  ENDMOVI1   peoplefunk               wants ENDMOVI1   gets DAY1       DIFFERS   (MovieScript 246)
  FIGTNIGT   peoplefunk               wants FIGTNIGT   gets DAY1       DIFFERS   (MovieScript 246)
  FUGEL      peoplefunk               wants FUGEL      gets DAY1       DIFFERS   (MovieScript 246)
  GARDUG     peoplefunk               wants GARDUG     gets DAY1       DIFFERS   (MovieScript 246)
  GOLDDEAD   peoplefunk               wants GOLDDEAD   gets DAY1       DIFFERS   (MovieScript 246)
  HATDAY1    peoplefunk               wants HATDAY1    gets DAY1       DIFFERS   (MovieScript 246)
  HATDAY2    peoplefunk               wants HATDAY2    gets DAY1       DIFFERS   (MovieScript 246)
  HATDAY3    peoplefunk               wants HATDAY3    gets DAY1       DIFFERS   (MovieScript 246)
  HATSIKUM   peoplefunk               wants HATSIKUM   gets DAY1       DIFFERS   (MovieScript 246)
  HOTEL1     objecttalktime           wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 248)
  HOTEL1     peoplecont               wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 246)
  HOTEL1     peoplefunk               wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 246)
  HOTEL1     peopleinroom             wants HOTEL1     gets AIR1       DIFFERS   (MovieScript 202)
  HOTEL1     talkproc                 wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 248)
  HOTEL1     walkonby                 wants HOTEL1     gets DAY1       same      (MovieScript 27 - walkonby)
  HOTEL1     whatodoeveryframe        wants HOTEL1     gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  IGUL       peoplefunk               wants IGUL       gets DAY1       DIFFERS   (MovieScript 246)
  INVESTIG   peoplefunk               wants INVESTIG   gets DAY1       DIFFERS   (MovieScript 246)
  ISHDAY1    peoplefunk               wants ISHDAY1    gets DAY1       DIFFERS   (MovieScript 246)
  JO         peoplefunk               wants JO         gets DAY1       DIFFERS   (MovieScript 246)
  KAROZ      peoplefunk               wants KAROZ      gets DAY1       DIFFERS   (MovieScript 246)
  MENADAY2   peoplefunk               wants MENADAY2   gets DAY1       DIFFERS   (MovieScript 246)
  MIROLO     peoplefunk               wants MIROLO     gets DAY1       DIFFERS   (MovieScript 246)
  MORN2      peoplefunk               wants MORN2      gets DAY1       DIFFERS   (MovieScript 246)
  MORN3      peoplefunk               wants MORN3      gets DAY1       DIFFERS   (MovieScript 246)
  MRFDAY1    peoplefunk               wants MRFDAY1    gets DAY1       DIFFERS   (MovieScript 246)
  MURDER1    peoplefunk               wants MURDER1    gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     dwarfscont               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     dwarfscont2              wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     gamad                    wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 272 - gamad)
  NIGHT1     objecttalktime           wants NIGHT1     gets DAY1       same      (MovieScript 248)
  NIGHT1     peoplecont               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     peoplefunk               wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 246)
  NIGHT1     talkproc                 wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 248)
  NIGHT1     walkonby                 wants NIGHT1     gets DAY1       same      (MovieScript 27 - walkonby)
  NIGHT1     whatodoeveryframe        wants NIGHT1     gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  NITE1      peoplefunk               wants NITE1      gets DAY1       DIFFERS   (MovieScript 246)
  PANTER     peoplefunk               wants PANTER     gets DAY1       DIFFERS   (MovieScript 246)
  PATDAY1    peoplefunk               wants PATDAY1    gets DAY1       DIFFERS   (MovieScript 246)
  PSIK       peoplefunk               wants PSIK       gets DAY1       DIFFERS   (MovieScript 246)
  SABMON1    peoplefunk               wants SABMON1    gets DAY1       DIFFERS   (MovieScript 246)
  SABMON2    peoplefunk               wants SABMON2    gets DAY1       DIFFERS   (MovieScript 246)
  SAMNIGHT   peoplefunk               wants SAMNIGHT   gets DAY1       DIFFERS   (MovieScript 246)
  SEA1       objecttalktime           wants SEA1       gets DAY1       DIFFERS   (MovieScript 248)
  SEA1       talkproc                 wants SEA1       gets DAY1       DIFFERS   (MovieScript 248)
  SEA1       walkonby                 wants SEA1       gets DAY1       same      (MovieScript 27 - walkonby)
  SEA1       whatodoeveryframe        wants SEA1       gets DAY1       DIFFERS   (MovieScript 28 - whatodoeveryframe)
  SLEEP1     peoplefunk               wants SLEEP1     gets DAY1       DIFFERS   (MovieScript 246)
  SLEEP2     peoplefunk               wants SLEEP2     gets DAY1       DIFFERS   (MovieScript 246)
  STRTGAME   fromnow                  wants STRTGAME   gets MASTER     DIFFERS   (MovieScript 137 - cut snd)
  STRTGAME   tlkpath                  wants STRTGAME   gets MASTER     DIFFERS   (MovieScript 130)
  TOFIRCPT   peoplefunk               wants TOFIRCPT   gets DAY1       DIFFERS   (MovieScript 246)
  ZARA       peoplefunk               wants ZARA       gets DAY1       DIFFERS   (MovieScript 246)

leaked in: reachable in the movie though none of its casts define it
  AIR1       3: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1>
  ALLIN      10: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> objecttalktime<DAY1> peoplecont<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1>
  ARCADE1    11: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1>
  ARCADE2    12: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> keyys<ARCADE1> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1>
  BIGEL      13: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> gun<ARCADE2> keyys<ARCADE1> objecttalktime<DAY1> peoplecont<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  BLACK      27: cardsfunk<MASTER> cursorfunk<MASTER> displayobject<MASTER> dwarfscont<DAY1> dwarfscont2<DAY1> fromnow<MASTER> gamad<DAY1> gun<ARCADE2> jokesfunk<MASTER> keyys<ARCADE1> mainkey<MASTER> missionfunk<MASTER> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> runcards<MASTER> runjokes<MASTER> searchfunk<MASTER> soundspath<MASTER> startmovie<MASTER> talkproc<DAY1> tlkpath<MASTER> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  CHESS      14: dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> gun<ARCADE2> keyys<ARCADE1> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  DAGI       15: badmov<CHESS> dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> gun<ARCADE2> keyys<ARCADE1> movinbad<CHESS> objecttalktime<DAY1> peoplecont<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  DETECTIV   29: badmov<CHESS> cardsfunk<MASTER> cursorfunk<MASTER> displayobject<MASTER> dwarfscont<DAY1> dwarfscont2<DAY1> fromnow<MASTER> gamad<DAY1> gun<ARCADE2> jokesfunk<MASTER> keyys<ARCADE1> mainkey<MASTER> missionfunk<MASTER> movinbad<CHESS> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> runcards<MASTER> runjokes<MASTER> searchfunk<MASTER> soundspath<MASTER> startmovie<MASTER> talkproc<DAY1> tlkpath<MASTER> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  DIVEFIGT   16: badmov<CHESS> dwarfscont<DAY1> dwarfscont2<DAY1> gamad<DAY1> gun<ARCADE2> keyys<ARCADE1> movinbad<CHESS> objecttalktime<DAY1> peoplecont<DAY1> peoplefunk<DAY1> peopleinroom<AIR1> planefunk<AIR1> talkproc<DAY1> walkonby<DAY1> whatodoeveryframe<DAY1> zigiscript<ARCADE2>
  ... 60 further movies elided, see handler-scope-baseline.txt ...

linked cast directories in this scope: BLACK BOOK BYAIR BYSEA DETECTIV FAT GOLDOLIN HATULI HEZI HEZI1 HEZNIGT HOTEL ISHURUN ISLAND ISLAND2 JOKERS MANAGER MASTER MOGUL NIGHT NIGHT2 RINATI SABMON TOFI WONDER
of those, also a playable movie in this scope: BLACK DETECTIV HATULI HEZI HEZNIGT ISHURUN JOKERS MASTER SABMON WONDER
distinct handler names resolving outside their movie: 53 (9 of them to DAY1)
  badmov bk2peoplefunk cardsfunk cleanup cursorfunk displayobject doload dosave dwarfscont dwarfscont2 fillnames fillnames2 finishday fromnow gamad getmacdiscinfo getwininfo gomenu gomenu2 gulu gun hathitball hathitball2 hitback hitballlong hitballshrt idle ishspec jokesfunk keyys mainkey missionfunk movinbad objecttalktime peoplecont peoplefunk peopleinroom planefunk runcards runjokes searchfunk soundspath startmovie stonecold talkproc tlkpath walkonby walkonby2 walkonby3 whatodoeveryframe whatodoeveryframe2 whatodoeveryframe3 zigiscript

movies resolving at least one handler outside themselves: 70 of 71
owner winning the most foreign resolutions: DAY1 (630)
foreign resolutions by owner: AIR1=138 ARCADE1=67 ARCADE2=132 CHESS=126 DAY1=630 HEZSAVE=234 HOTEL1=114 MASTER=130 SEA1=32 STRTGAME=24 TENNIS=15
```

## What this measures against

The spec this baseline is the "before" reading for is
`openspec/changes/director-playback-machine/specs/script-resolution/spec.md`.

> ### Requirement: Handler tables are scoped to the movie that owns them
>
> The runtime SHALL maintain movie-script handler tables per loaded movie, built from that movie's own cast
> libraries. Resolution of a handler SHALL consider only the current movie's table, then a single shared
> archive. A handler defined in another movie MUST NOT be reachable.

Every row in the shadowed and leaked-in sections violates that sentence. The shadowed rows violate the
first two clauses, the movie's own definition not being the one resolved; the leaked-in rows violate the
third, a handler defined in another movie being reachable.

> #### Scenario: A duplicated handler name resolves within its own movie
>
> - **WHEN** two movies each define a movie-script handler with the same name and the second movie is
>   current
> - **THEN** the second movie's definition is invoked

Fails for all 63 shadowed rows in the full scope, 58 of them onto a different body.
`whatodoeveryframe` is the sharpest case: DAY1, NIGHT1, HOTEL1, AIR1 and SEA1 each define one, all five
bodies differ, and four of the five movies run DAY1's.

> #### Scenario: The shared archive is consulted after the movie's own casts
>
> - **WHEN** a handler name exists in both the current movie's casts and the shared archive
> - **THEN** the current movie's definition is invoked

STRTGAME is the measured instance: it defines `fromnow` and `tlkpath` in its own Internal cast and resolves
both to the MASTER directory's copies instead. STRTGAME does not list MASTER among its cast libraries, so
strictly the harness scores this as another directory winning on load order rather than the archive winning.
Either reading, STRTGAME's own definition must be the one invoked, and today it is not.

4.1 and 4.2 do not satisfy these requirements. They measure the distance to them. 4.3 through 4.6 close it
and 4.7 re-runs this harness against the criterion above.

## Not measured

- Whether a cross-movie resolution changes observable behaviour. The body hash narrows this: 58 of the 63
  full-scope shadowed rows land on a definition that is not byte-identical, so those can change what runs.
  Whether they do is task 4.8's oracle diff.
- Behaviour and cast scripts. Only `MovieScript*` handlers go into `_movie_handlers`; everything else is
  reached through its owning sprite or member and is already movie-scoped by construction.
- The real play order. Pass B uses DAY1-then-alphabetical, a stand-in for the many orders a real session
  can take. A different order moves which movie wins, not whether the defect exists.
- Reproducibility on a case-sensitive filesystem. `_playable_movies` upper-cases the names the export index
  gives it, and some directories are lowercase on disk (`data/lingo/strtgame/`). macOS opens them anyway,
  with a warning. On Linux those movies would fail to load and drop out of the counts.
