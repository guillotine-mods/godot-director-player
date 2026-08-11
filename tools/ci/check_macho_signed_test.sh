#!/usr/bin/env bash
# Checks what check_macho_signed.py accepts and refuses, against synthetic
# Mach-O fixtures.
#
#   bash tools/ci/check_macho_signed_test.sh
#
# Synthetic rather than real binaries, deliberately. A real signed fixture can
# only be produced by `codesign` on a Mac, and this suite has to run on the Linux
# release runner, which is the whole reason the checker parses bytes instead of
# shelling out to codesign. Hand-built headers also let the failure cases exist at
# all: there is no way to ask codesign for a binary whose signature blob is
# present but zero-length.
#
# The fixtures are minimal: a header, load commands, and nothing else. The
# checker only ever reads load commands, so a fixture carrying no code is
# sufficient and stays legible.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp=$(mktemp -d)

# One EXIT trap, cleanup and abort guard together, matching
# stamp_version_test.sh. A probe that dies under `set -e` before `check` runs
# would otherwise take the suite with it and print nothing, which must not read
# as a pass.
verdict=""
finish() {
	st=$?
	rm -rf "$tmp"
	if [ -z "$verdict" ]; then
		echo ""
		echo "FAIL  check_macho_signed: the suite aborted (exit $st) before reaching its verdict"
	fi
	exit "$st"
}
trap finish EXIT

fail=0
check() { # check <name> <exit-code>
	if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}

python3 - "$tmp" <<'PY'
import struct
import sys

out = sys.argv[1]

MH_MAGIC_64 = 0xFEEDFACF
LC_CODE_SIGNATURE = 0x1D
LC_SEGMENT_64 = 0x19
ARM64, X86_64 = 0x0100000C, 0x01000007


def thin(cputype, *, signed, datasize=4096):
    """A mach_header_64 plus load commands. Little-endian, 64-bit."""
    cmds = b""
    # A non-signature command first, so a parser that simply looked at the first
    # load command rather than walking them all would get the wrong answer.
    cmds += struct.pack("<II", LC_SEGMENT_64, 16) + b"\x00" * 8
    if signed:
        cmds += struct.pack("<IIII", LC_CODE_SIGNATURE, 16, 0xC000, datasize)
    ncmds = 2 if signed else 1
    header = struct.pack(
        "<IiiIIII I", MH_MAGIC_64, cputype, 0, 2, ncmds, len(cmds), 0, 0
    )
    return header + cmds


def fat(slices):
    """A big-endian fat header wrapping the given thin images."""
    count = len(slices)
    head = struct.pack(">II", 0xCAFEBABE, count)
    entries, bodies = b"", b""
    # Offsets are absolute from the start of the file, so they have to account
    # for the header and the whole entry table before any body lands.
    base = 8 + count * 20
    for cputype, image in slices:
        entries += struct.pack(">iiIII", cputype, 0, base + len(bodies), len(image), 12)
        bodies += image
    return head + entries + bodies


def write(name, blob):
    with open(f"{out}/{name}", "wb") as fh:
        fh.write(blob)


write("thin_signed", thin(ARM64, signed=True))
write("thin_unsigned", thin(ARM64, signed=False))
write("thin_zerolen", thin(ARM64, signed=True, datasize=0))
write("fat_both_signed", fat([(X86_64, thin(X86_64, signed=True)),
                              (ARM64, thin(ARM64, signed=True))]))
# The case that matters most for a universal binary: one slice signed, one not.
write("fat_arm_unsigned", fat([(X86_64, thin(X86_64, signed=True)),
                                (ARM64, thin(ARM64, signed=False))]))
write("not_macho", b"MZ\x90\x00" + b"\x00" * 64)
write("too_short", b"\xcf\xfa")
PY

probe() { # probe <name> <fixture> <expected-exit>
	rc=0
	python3 tools/ci/check_macho_signed.py "$tmp/$2" >/dev/null 2>&1 || rc=$?
	if [ "$rc" -eq "$3" ]; then check "$1" 0; else check "$1 (exit $rc, wanted $3)" 1; fi
}

probe "a signed thin binary passes" thin_signed 0
probe "an unsigned thin binary is refused" thin_unsigned 1
probe "a zero-length signature blob is refused" thin_zerolen 1
probe "a fat binary with every slice signed passes" fat_both_signed 0
probe "a fat binary with one unsigned slice is refused" fat_arm_unsigned 1
probe "a non-Mach-O file is refused" not_macho 1
probe "a truncated file is refused" too_short 1

# The output is captured before it is matched, rather than piped straight into
# grep. `pipefail` is on, so `checker | grep -q` yields the CHECKER's exit status
# whenever it is nonzero -- and for a refusal case that status is 1 by design.
# Piping made this assertion fail while grep was matching perfectly well: a check
# that goes red for a reason unrelated to what it is checking, which is worse than
# no check. `|| true` because the nonzero exit is the expected outcome here.
#
# Naming the offending arch is the point of walking every slice: "not signed" on
# a universal binary does not tell you which half of your audience is stuck.
out=$(python3 tools/ci/check_macho_signed.py "$tmp/fat_arm_unsigned" 2>&1 || true)
if printf '%s\n' "$out" | grep -q arm64; then
	check "the refusal names the unsigned arch" 0
else
	check "the refusal names the unsigned arch" 1
fi

# The passing case has to report both slices, or "ok" could mean it found and
# checked exactly one and stopped. Captured the same way for consistency, even
# though this one exits 0 and would survive the pipe.
out=$(python3 tools/ci/check_macho_signed.py "$tmp/fat_both_signed" 2>&1 || true)
if printf '%s\n' "$out" | grep -q '2 signed slice'; then
	check "the pass reports how many slices were checked" 0
else
	check "the pass reports how many slices were checked" 1
fi

rc=0
python3 tools/ci/check_macho_signed.py >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "no arguments exits 2" 0
else
	check "no arguments exits 2" 1
fi

# --require is what keeps the build universal. Without it, flipping
# binary_format/architecture away from "universal" ships a binary that runs on
# half the Macs and passes every other check here, because the slice that IS
# present is correctly signed.
require() { # require <name> <fixture> <arches> <expected-exit>
	rc=0
	python3 tools/ci/check_macho_signed.py "$tmp/$2" --require "$3" >/dev/null 2>&1 || rc=$?
	if [ "$rc" -eq "$4" ]; then check "$1" 0; else check "$1 (exit $rc, wanted $4)" 1; fi
}

require "a universal binary satisfies --require" fat_both_signed "arm64,x86_64" 0
require "an arm64-only binary is refused when Intel is required" thin_signed "arm64,x86_64" 1
require "an arm64-only binary passes when only arm64 is required" thin_signed "arm64" 0
# Order must not matter; a set is being compared, not a string.
require "the required order is irrelevant" fat_both_signed "x86_64,arm64" 0
# An empty list would require nothing while looking like it required something.
require "an empty --require list is refused" fat_both_signed "," 2
# The flag needs a value; consuming the path as its argument would leave no path.
rc=0
python3 tools/ci/check_macho_signed.py "$tmp/fat_both_signed" --require >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
	check "--require with no value exits 2" 0
else
	check "--require with no value exits 2" 1
fi

# A missing arch and a missing signature are different problems. Reporting only
# the signature when both are true sends the reader to fix the wrong one.
out=$(python3 tools/ci/check_macho_signed.py "$tmp/thin_unsigned" --require "arm64,x86_64" 2>&1 || true)
if printf '%s\n' "$out" | grep -q 'missing architecture'; then
	check "a missing arch is reported ahead of the signature" 0
else
	check "a missing arch is reported ahead of the signature" 1
fi

probe "a missing file is refused" nope_does_not_exist 1

# On a developer's Mac, cross-check the parser against Apple's own verdict on a
# real bundle if one has been exported. Skipped rather than failed when absent:
# the export is 1.9 GB and this suite is meant to be cheap. This is the only case
# here that exercises a binary neither this file nor Godot's exporter invented.
app="build/mac/Godot Director Player.app/Contents/MacOS/Godot Director Player"
if [ -r "$app" ] && command -v codesign >/dev/null 2>&1; then
	ours=0
	python3 tools/ci/check_macho_signed.py "$app" >/dev/null 2>&1 || ours=$?
	theirs=0
	codesign --verify --strict "$app" >/dev/null 2>&1 || theirs=$?
	# Compared as booleans: codesign's nonzero codes are not ours, and only
	# agreement on signed-vs-not is being asserted.
	if [ "$((ours != 0))" -eq "$((theirs != 0))" ]; then
		check "agrees with codesign on the real export" 0
	else
		check "agrees with codesign on the real export (ours=$ours codesign=$theirs)" 1
	fi
else
	echo "skip  agrees with codesign on the real export (no local export, or not a Mac)"
fi

echo ""
verdict=printed
if [ "$fail" -eq 0 ]; then echo "PASS  check_macho_signed"; else echo "FAIL  check_macho_signed"; fi
exit "$fail"
