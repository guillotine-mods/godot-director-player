# Shipping this on a phone

What Android and iOS impose on a port that reads the original Director files at
runtime. [`ANDROID.md`](ANDROID.md) is how to install a build; this is what has
to be true for one to work at all.

**The standing rule: rule on mobile before the refactor, not after.** These
limits are absolute rather than awkward — iOS forbids `fork`/`exec` and
unreviewed native code outright, and Android's W^X has blocked executing a
binary from the app's writable data dir since API 29. A design that shells out
to an external tool, ships a native executable, or wants Python at run time is
not "harder to port", it is unshippable, and the discovery arrives after the
work is done. ProjectorRays is the standing example: it produces
`reference/lingo/` as a developer tool and can never be a runtime dependency.

Everything below was measured on this game's own tree or reproduced on a
throwaway Godot 4.7.1 project. The section at the end lists what was *not*
verified, because some of the load-bearing claims are inferences.

## The blocker: the game data does not ship

`export_presets.cfg` carries `include_filter="data/*.json"`. `.dir`, `.cst` and
`.aif` are not Godot resource types, so **without a matching filter they are
silently dropped from the export.** No warning is emitted.

It works in the editor, where `FileAccess.open("res://games/...")` reaches the
real filesystem, and returns `ERR_FILE_NOT_FOUND` in an exported build. The whole
of `director/` fails at boot with nothing said at build time — the expensive
shape of bug, because the thing that catches it is a phone rather than a
compiler.

```
include_filter="games/*"
```

One pattern, recursive, extension-agnostic — and it keeps working if a title
ships `.dxr`/`.cxt`, which `director/director_paths.gd` already anticipates.

**Do not write `games/piposh2/**/*`.** Godot matches with `String.matchn()`,
where `*` already crosses `/` and `**` means nothing at all. The trailing `/`
requirement then excludes every top-level file — here `strtgame.dir` and
`MASTER.CST`, the boot movie and the shared cast that owns the globals. Measured:
that pattern ships 3,226 of 3,228 files and the two it drops are the two the game
cannot start without.

Matching is case-insensitive, so `*.dir` matches `MASTER.CST`. Given the mixed-case
tree, that is a mercy rather than a detail.

## What it weighs

Measured over `games/piposh2/`:

| | Files | Raw | Deflated |
|---|---|---|---|
| `.aif` | 3,142 | 432.2 MB | ~279 MB |
| `.dir` | 61 | 87.3 MB | ~28 MB |
| `.cst` | 25 | 61.6 MB | ~25 MB |
| **Total** | **3,228** | **581.2 MB** | **~332 MB** |

Transcoding the audio to Ogg Vorbis at 32 kbps takes 432 MB to ~77 MB, and the
whole payload to roughly **226 MB**. That is the difference between fitting and
fitting comfortably.

## Store limits

**Google Play.** The base module cap is **500 MB download**, not the 200 MB that
gets quoted — 200 MB is the threshold above which users on mobile data see a
non-blocking warning. Install-time asset packs raise the cumulative ceiling to
4 GB, on-demand to 30 GB. Legacy standalone APKs are capped at 100 MB, and
`export_presets.cfg` currently targets APK: **Play needs AAB.** APK expansion
(OBB) is not an escape hatch — it was removed in Godot 4.7 and app bundles never
supported it.

Godot's Play Asset Delivery support is minimal: an AAB export wraps assets in a
single *install-time* pack, and there is no engine API for on-demand or
fast-follow packs. Dynamic packs would need a custom Android plugin.

**Apple.** 4 GB uncompressed, 80 MB executable. 581 MB is legal untouched. The
200 MB cellular figure is a user-configurable prompt, not a cap. On-Demand
Resources is deprecated as of iOS 27 and Godot has no binding for it anyway —
which makes iOS the *easier* platform here: bundle everything and stop thinking
about it.

**Downloading data post-install is permitted** on both stores — Apple 2.5.2 and
Play's Device and Network Abuse policy both scope their bans to executable code,
not assets — but both require disclosing the size and prompting first, and Play
names silent CDN downloads as a violation. Note also that hosting the data makes
you its distributor, which is a different legal posture from shipping a copy the
player already owns. That is a decision to take deliberately, not a technique to
reach for because it is convenient.

## Android compresses what this reader seeks through

Godot's Android export does not put a `.pck` in the APK. It writes loose files
under `assets/` and deflates anything not on a hard-coded no-compress list.
`.dir`, `.cst` and `.aif` are all absent from that list; `.pck`, `.wav` and
`.ogg` are on it.

That matters because of how the container reader works. `director_file.gd` seeks
once per memory-map entry while indexing and again per chunk read, and the corpus
holds 90,385 entries across 86 containers — 3,158 in `strtgame.dir` alone, before
a single chunk is read. Godot opens Android assets with `AASSET_MODE_STREAMING`,
where a deflated entry is backed by a streaming inflater and a backward seek
plausibly re-inflates from the start of the entry.

**The mitigation sidesteps the question: pack the containers into one `.pck`.**
`.pck` is on the no-compress list, so it is stored rather than deflated, and
`FileAccessPack::seek` is a pass-through offset add. Load it with
`ProjectSettings.load_resource_pack()` from an autoload. Measured on desktop:
20,000 random seek+reads through a mounted pack, 78.4 ms total, no per-read
decompression — PCK has no compression flag in its format at all.

Two things to avoid: `encrypt_pck`, which wraps entries in `FileAccessEncrypted`
and buffers the whole file in memory; and `.zip` packs, whose `seek` rewinds and
re-inflates on backward seek, which is precisely this access pattern's worst case.

The cost is download size — stored containers are ~149 MB against ~53 MB
deflated. Against a 500 MB ceiling that is affordable, and it buys the seek
behaviour the reader depends on.

## Audio: Godot cannot load AIFF

Not at import, not at runtime. `ResourceImporterWAV` recognises `wav` only, and
`AudioStreamWAV.load_from_buffer` requires WAV data. AIFF support is an open
proposal with an unmerged PR; do not plan around it.

This game's AIFF files are unusually tractable, though — surveyed across all
3,142:

- every one is plain `AIFF`, not AIFF-C, with an 18-byte `COMM` — so uncompressed
  PCM only, no codec field
- 3,140 mono, 3,099 of them 8-bit
- 5.34 hours total
- one genuinely empty file, `SOUNDS/S_NIGHT3/HEZ61.AIF`, 0 bytes in the original

None of the usual AIFF horrors apply: no `sowt`, no float, no 24-bit. A decoder
needs a big-endian IFF walk with even-byte padding, the 80-bit extended sample
rate, and `SSND`'s 8-byte header. And there is a lucky alignment — **8-bit AIFF
samples are signed, and so is `AudioStreamWAV.FORMAT_8_BITS`** — so for 3,099 of
3,142 files the bytes transfer verbatim. Only the 41 16-bit files need a swap.

Two routes:

1. **Transcode to Ogg ahead of time.** 432 MB → ~77 MB at 32 kbps, and `.ogg` is
   on the Android no-compress list. The source is 8-bit 22 kHz, so 32 kbps is not
   the quality bottleneck.
2. **Decode AIFF in GDScript**, ~60 lines closely parallel to the existing
   `_load_wav_runtime`. Keeps the tree byte-original, costs 432 MB of payload and
   leaves the deflate problem in place.

Either way **no call site changes**: `AudioDirector.resolve_path` matches on stem
and discards the extension, which is why `play_file(1, "pi%s.aif" % item)` already
resolves to a `.wav` today. Only the index roots, the accepted-extension list and
one loader branch move.

Noted in passing: `autoload/audio_director.gd` sets `FORMAT_8_BITS` and assigns
raw WAV bytes without the unsigned→signed conversion 8-bit WAV needs. Latent —
nothing currently ships an 8-bit WAV — and exactly the conversion AIFF does not
require.

## Before shipping

- [ ] `include_filter="games/*"` in `export_presets.cfg`
- [ ] `export_format` switched to AAB for Play
- [ ] Audio transcoded, or the AIFF loader landed
- [ ] Containers packed into a stored `.pck`, if the device test says deflate hurts
- [ ] **A CI assertion that the exported pack contains `strtgame.dir` and
      `MASTER.CST`.** The `**/*` result above is how quietly this breaks, and an
      export that silently drops the boot movie looks like a code bug for as long
      as it takes to think of checking the pack.

## Not verified

Stated as inference, and worth a device test before anything depends on it:

- **AOSP re-inflating on backward seek.** Reasoned from `AASSET_MODE_STREAMING`,
  not read from AOSP source or profiled on hardware. It is the argument for the
  `.pck` route and the weakest link in it.
- Whether AGP/AAPT2 compresses assets the same way on the Gradle path, which an
  AAB export requires. Check with `unzip -v` on the output.
- Whether assets inside an install-time asset pack are stored compressed.
- Google's own pages disagree on base-module size — 500 MB in the Console table,
  4 GB in the AAB guide. 500 MB is treated here as the enforced gate.
- Godot's lack of iOS ODR support is "no evidence found", not proven absent.
- `DirAccess` enumerating a runtime-loaded pack works on desktop 4.7.1 and
  contradicts the official documentation, which says it does not. Both
  `director_paths.gd` and `audio_director.gd` scan directories, so confirm on a
  device before relying on it.
- The 78.4 ms seek benchmark is desktop with the OS page cache, not Android
  storage.
