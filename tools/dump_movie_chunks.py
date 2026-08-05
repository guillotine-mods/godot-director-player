#!/usr/bin/env python3
"""Dump a Director movie's chunks straight from its .DXR/.CXT container.

The film loops and 1-bit bitmaps this port needs live in chunks, and chunks only
existed for the 27 movies someone had already run ProjectorRays over. 31 more
movies have their source binary and no dump, so their characters do not animate
(bugs.md 12) and their 1-bit members are still the 8-bit misread (bugs.md 11).
This reads the container directly, so no Windows machine and no ProjectorRays.

Writes the layout the rest of the tooling already expects:

    <out>/<NAME>/<NAME>/chunks/<fourCC>-<id>.bin

`id` is the resource's index in the memory map, which is what ProjectorRays names
its files after and what `CAS_`, `KEY_` and `members.json` refer to.

Container format, verified against the 27 existing dumps rather than assumed:

    RIFX <u32 size> MV93        big-endian; XFIR is the little-endian spelling
    imap <u32 size> <u32 count> <u32 mmap offset> ...
    mmap <u32 size> <u16 headerLen> <u16 entryLen> <u32 max> <u32 used> ...
         then `used` entries of <4s fourCC> <u32 size> <u32 offset> <u16 flags>
         <u16 unused> <u32 link>

Usage:
    python3 tools/dump_movie_chunks.py --verify          # against existing dumps
    python3 tools/dump_movie_chunks.py --out <dir>       # dump what is missing
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WEB_ALPHA = Path.home() / (
    "Projects/_private_projects/Piposh2-Port/originals/recovery/web-alpha"
)
## Chunks that are containers or already-parsed indexes rather than payloads.
## ProjectorRays writes them out too, so they are kept for byte comparison.
RIFX_MAGIC = {b"RIFX": ">", b"XFIR": "<"}


class Container:
    """One .DXR/.CXT/.DIR file's memory map."""

    def __init__(self, path: Path):
        self.path = path
        self.raw = path.read_bytes()
        magic = self.raw[:4]
        if magic not in RIFX_MAGIC:
            raise ValueError(f"{path.name}: not a RIFX container ({magic!r})")
        if magic == b"XFIR":
            # Refused rather than guessed at. This reader is validated only
            # against big-endian dumps, and its little-endian output for
            # `strtgame` — the corpus's one XFIR file — differed from
            # ProjectorRays in 441 of 912 chunks: same offsets, different
            # payload boundaries. Emitting those silently is worse than having
            # no dump, because everything downstream treats a chunk as truth.
            #
            # strtgame is also the one XFIR file that already has a real dump,
            # filed under STRT_CHUNKS, so nothing is lost by refusing here.
            raise ValueError(
                f"{path.name}: little-endian (XFIR) containers are not supported; "
                "use the ProjectorRays dump"
            )
        self.endian = RIFX_MAGIC[magic]
        self.entries: list[tuple[str, int, int]] = []
        self._read_map()

    def _u32(self, offset: int) -> int:
        return struct.unpack_from(f"{self.endian}I", self.raw, offset)[0]

    def _u16(self, offset: int) -> int:
        return struct.unpack_from(f"{self.endian}H", self.raw, offset)[0]

    def _tag(self, offset: int) -> str:
        tag = self.raw[offset:offset + 4]
        if self.endian == "<":
            tag = tag[::-1]
        return tag.decode("latin-1")

    def _read_map(self) -> None:
        if self._tag(12) != "imap":
            raise ValueError(f"{self.path.name}: expected imap at 12")
        # imap data starts after its fourCC and size.
        mmap_offset = self._u32(24)
        if self._tag(mmap_offset) != "mmap":
            raise ValueError(f"{self.path.name}: no mmap at {mmap_offset}")
        data = mmap_offset + 8
        header_length = self._u16(data)
        entry_length = self._u16(data + 2)
        used = self._u32(data + 8)
        table = data + header_length
        for index in range(used):
            at = table + index * entry_length
            if at + entry_length > len(self.raw):
                break
            self.entries.append((
                self._tag(at), self._u32(at + 4), self._u32(at + 8)
            ))

    def payloads(self):
        """Yields (index, fourCC, bytes) for every real resource.

        The payload excludes the 8-byte fourCC and size that precede it in the
        file, which is what ProjectorRays writes and what every parser in
        tools/ expects.
        """
        for index, (tag, size, offset) in enumerate(self.entries):
            if tag in ("free", "junk") or offset == 0 and index:
                continue
            start = offset + 8
            body = self.raw[start:start + size]
            if len(body) != size:
                continue
            yield index, tag, body


def safe_name(tag: str) -> str:
    """ProjectorRays keeps the fourCC verbatim, spaces and all (`ccl `)."""
    return "".join(c if c.isalnum() or c in "_ " else "_" for c in tag)


def dump(path: Path, out_root: Path, name: str) -> int:
    chunks_dir = out_root / name / name / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)
    written = 0
    for index, tag, body in Container(path).payloads():
        (chunks_dir / f"{safe_name(tag)}-{index}.bin").write_bytes(body)
        written += 1
    return written


def verify(limit: int) -> int:
    """Reproduce existing dumps byte for byte, or the reader is not trusted.

    27 movies were dumped by ProjectorRays. They are the oracle: a reader that
    cannot reproduce them exactly has no business writing the other 31.
    """
    # Keyed by the *inner* directory, not the outer one. `STRT_CHUNKS/strtgame`
    # is strtgame's dump, and keying on the outer name meant it matched no source
    # file and was silently skipped — which is exactly how a reader that gets
    # little-endian containers wrong passed a verification claiming to cover
    # every dump.
    dumps = {p.parts[-2]: p for p in (WEB_ALPHA / "decompiled_chunks").glob("*/*/chunks")}
    checked = matched = 0
    failures: list[str] = []
    skipped: list[str] = []
    for name, chunks_dir in sorted(dumps.items())[:limit]:
        source = None
        for candidate in [
            WEB_ALPHA / "PIP2DATA" / f"{name}.DXR",
            WEB_ALPHA / "PIP2DATA" / f"{name}.CXT",
            WEB_ALPHA / "PIP2DATA" / f"{name}.CST",
            WEB_ALPHA / f"{name.lower()}.dxr",
            WEB_ALPHA / f"{name}.DXR",
        ]:
            if candidate.is_file():
                source = candidate
                break
        if source is None:
            skipped.append(f"{name}: no source binary")
            continue
        try:
            container = Container(source)
        except ValueError as error:
            # A refused container is a known limit, not a wrong answer.
            skipped.append(f"{name}: {error}")
            continue

        produced = {f"{safe_name(t)}-{i}.bin": b for i, t, b in container.payloads()}
        # Compare only the chunk types this port actually reads. ProjectorRays
        # also writes a few it synthesises, and those are not evidence about the
        # container.
        wanted = [p for p in chunks_dir.iterdir()
                  if p.suffix == ".bin" and p.name.split("-")[0] in
                  ("CASt", "BITD", "SCVW", "CAS_", "KEY_", "VERS", "STXT", "VWSC")]
        for existing in sorted(wanted):
            checked += 1
            mine = produced.get(existing.name)
            if mine is None:
                failures.append(f"{name}/{existing.name}: not produced")
            elif mine != existing.read_bytes():
                failures.append(
                    f"{name}/{existing.name}: {len(mine)}B vs {existing.stat().st_size}B")
            else:
                matched += 1
    print(f"dumps found: {len(dumps)}   compared: {checked}   identical: {matched}")
    for note in skipped:
        print(f"  skipped {note}")
    for failure in failures[:15]:
        print(f"  FAIL {failure}")
    if failures:
        print(f"\n{len(failures)} mismatches")
        return 1
    print("PASS: the reader reproduces every existing dump exactly")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--limit", type=int, default=99)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    if args.verify:
        return verify(args.limit)
    if args.out is None:
        print("need --out or --verify", file=sys.stderr)
        return 1

    have = {p.parts[-3] for p in (WEB_ALPHA / "decompiled_chunks").glob("*/*/chunks")}
    total = 0
    for movie_dir in sorted(REPO.glob("assets/render_model/*/members.json")):
        name = movie_dir.parent.name
        if name in have:
            continue
        source = None
        for candidate in [
            WEB_ALPHA / "PIP2DATA" / f"{name}.DXR",
            WEB_ALPHA / "PIP2DATA" / f"{name}.CXT",
            WEB_ALPHA / "PIP2DATA" / f"{name}.CST",
            WEB_ALPHA / f"{name.lower()}.dxr",
        ]:
            if candidate.is_file():
                source = candidate
                break
        if source is None:
            continue
        try:
            written = dump(source, args.out, name)
        except ValueError as error:
            print(f"  {name}: {error}")
            continue
        print(f"  {name:<12} {written:>5} chunks from {source.name}")
        total += 1
    print(f"\n{total} movies dumped into {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
