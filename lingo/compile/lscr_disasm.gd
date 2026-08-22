extends RefCounted
## One handler's bytecode as a flat instruction list.
##
## The whole of the format is one rule and one table. The rule is that a single
## opcode byte encodes **both the operation and its operand width**
## (`Handler::readData` in ProjectorRays):
##
##     canonical = (op >= 0x40) ? (0x40 + (op % 0x40)) : op
##
## | raw byte | operand |
## | --- | --- |
## | `0x00`-`0x3F` | none, the instruction is one byte |
## | `0x40`-`0x7F` | 1 byte |
## | `0x80`-`0xBF` | 2 bytes, big-endian |
## | `0xC0`-`0xFF` | 4 bytes, big-endian |
##
## So `0x41`, `0x81` and `0xC1` are all `pushint` at three widths.
##
## **ScummVM encodes the same rule differently and cannot decode the `0xC0`+
## forms at all.** It carries a `proto` string per row (`"B"`, `"W"`, `"b"`,
## `"w"`) and falls through on an unknown opcode by treating `< 0x40` as 1 byte,
## `< 0x80` as 2 and anything else as 3 -- so a four-byte form is mis-sized as
## three and the stream desyncs from that instruction to the end of the handler.
## A desynced stream does not announce itself: it emits plausible small operands
## and keeps going. Follow ProjectorRays' arithmetic rule, which is what this
## does.
##
## Signedness is per opcode and it matters: the operand is read **signed** for
## `pushint` (0x41), `pushint16` (0x6e) and `pushint32` (0x6f), unsigned for
## everything else. ScummVM agrees through its `"B"`/`"W"` (signed) versus
## `"b"`/`"w"` (unsigned) protos. `endrepeat` (0x54) additionally **negates** its
## operand, giving the backward branch of a loop -- ScummVM's `n` proto, used by
## that opcode and no other.
##
## Nothing here interprets. An unknown opcode becomes a named `unknown`
## instruction of the width its own byte declares, so the stream stays in sync
## and the failure surfaces at one instruction rather than corrupting a handler.
## That is deliberate and `docs/LSCR_FORMAT.md` section 4 asks for it: the seven
## D6+ dot-syntax opcodes below are ProjectorRays-only and unexercised by this
## corpus, so a title that uses one should fail loudly at one node.

## Canonical opcode -> name. `docs/LSCR_FORMAT.md` section 4, which is
## `lingoV4[]` in `reference/scummvm/lingo/lingo-bytecode.cpp` joined with
## ProjectorRays' `enums.h` for the rows ScummVM has no handler for.
const NAMES := {
	0x01: "ret", 0x02: "retfactory", 0x03: "pushzero",
	0x04: "mul", 0x05: "add", 0x06: "sub", 0x07: "div", 0x08: "mod",
	0x09: "inv", 0x0a: "joinstr", 0x0b: "joinpadstr",
	0x0c: "lt", 0x0d: "lteq", 0x0e: "nteq", 0x0f: "eq", 0x10: "gt", 0x11: "gteq",
	0x12: "and", 0x13: "or", 0x14: "not",
	0x15: "containsstr", 0x16: "contains0str",
	0x17: "getchunk", 0x18: "hilitechunk", 0x19: "ontospr", 0x1a: "intospr",
	0x1b: "getfield", 0x1c: "starttell", 0x1d: "endtell",
	0x1e: "pushlist", 0x1f: "pushproplist",
	# ProjectorRays-only. ScummVM would decode it as an unimplemented one-byte
	# instruction and warn. Not observed in this corpus.
	0x21: "swap",

	0x41: "pushint", 0x42: "pusharglistnoret", 0x43: "pusharglist",
	0x44: "pushcons", 0x45: "pushsymb", 0x46: "pushvarref",
	0x48: "getglobal2", 0x49: "getglobal", 0x4a: "getprop",
	0x4b: "getparam", 0x4c: "getlocal",
	0x4e: "setglobal2", 0x4f: "setglobal", 0x50: "setprop",
	0x51: "setparam", 0x52: "setlocal",
	0x53: "jmp", 0x54: "endrepeat", 0x55: "jmpifz",
	0x56: "localcall", 0x57: "extcall", 0x58: "objcallv4",
	0x59: "put", 0x5a: "putchunk", 0x5b: "deletechunk",
	0x5c: "get", 0x5d: "set",
	0x5f: "getmovieprop", 0x60: "setmovieprop",
	0x61: "getobjprop", 0x62: "setobjprop", 0x63: "tellcall",
	0x64: "peek", 0x65: "pop", 0x66: "thebuiltin", 0x67: "objcall",
	# The last seven are ProjectorRays-only D6+ verbose/dot-syntax opcodes,
	# **unexercised by this corpus and with unverified operand semantics**. They
	# are named rather than omitted so the disassembly says which opcode it met,
	# and `lscr_lower.gd` still emits `unknown_opcode` for them rather than
	# guessing what they pop.
	0x6d: "pushchunkvarref", 0x6e: "pushint16", 0x6f: "pushint32",
	0x70: "getchainedprop", 0x71: "pushfloat32", 0x72: "gettoplevelprop",
	0x73: "newobj",
}

## Operands read as signed. Everything else is unsigned.
const SIGNED := {0x41: true, 0x6e: true, 0x6f: true}

## `findVarV4`'s `varType` nibble, used by `objcallv4`, `put`, `putchunk` and
## `deletechunk`. 1 and 2 are both global; 6 pops a cast-lib id first at D5+.
const VAR_TYPES := {
	1: "global", 2: "global", 3: "property", 4: "argument", 5: "local", 6: "field",
}


## `{instructions, error}`. `instructions` is every instruction in order, each
## `{pos, size, raw, op, name, operand}`:
##
## - `pos` is the byte position **within the handler**, which is the space jump
##   targets are expressed in (`target = pos + operand`).
## - `raw` is the byte as stored, `op` the canonical opcode.
## - `operand` is already signed, already negated for `endrepeat`, and is `0` for
##   the one-byte forms.
##
## A truncated stream is reported in `error` and everything decoded before it is
## still returned, because a handler that runs out of bytes mid-instruction has
## still told you what its first fifty statements were.
static func decode(code: PackedByteArray) -> Dictionary:
	var out: Array = []
	var i := 0
	var error := ""
	while i < code.size():
		var raw: int = code[i]
		var width := 0
		if raw >= 0xC0:
			width = 4
		elif raw >= 0x80:
			width = 2
		elif raw >= 0x40:
			width = 1
		if i + 1 + width > code.size():
			error = "instruction at %d wants %d operand byte(s), %d left" % [
				i, width, code.size() - i - 1]
			break
		var op := (0x40 + (raw % 0x40)) if raw >= 0x40 else raw
		var operand := 0
		for b in width:
			operand = (operand << 8) | code[i + 1 + b]
		if SIGNED.has(op) and width > 0:
			var sign_bit := 1 << (width * 8 - 1)
			if (operand & sign_bit) != 0:
				operand -= sign_bit << 1
		# `endrepeat` is the same jump rule with the operand negated, which is
		# what makes it the backward branch of a loop. ScummVM's `n` proto, and
		# it is used by this opcode alone.
		if op == 0x54:
			operand = -operand
		out.append({
			"pos": i,
			"size": 1 + width,
			"raw": raw,
			"op": op,
			"name": str(NAMES.get(op, "unknown")),
			"operand": operand,
		})
		i += 1 + width
	return {"instructions": out, "error": error}


## Every instruction position in a decoded stream, as a set. A jump whose target
## is not one of these landed mid-instruction, which is the cheapest evidence
## that the handler was read at the wrong stride or from the wrong offset.
static func positions(instructions: Array) -> Dictionary:
	var out := {}
	for ins in instructions:
		out[int(ins["pos"])] = true
	return out


## One instruction as text, for a disassembly listing. Names only; resolving a
## name index or a literal needs the script, which this file deliberately has no
## access to.
static func text(ins: Dictionary) -> String:
	if int(ins["size"]) == 1:
		return "%4d: %-18s" % [int(ins["pos"]), str(ins["name"])]
	return "%4d: %-18s %d" % [int(ins["pos"]), str(ins["name"]), int(ins["operand"])]
