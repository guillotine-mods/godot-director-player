#!/usr/bin/env node
/**
 * Decompile a tree of Director movies with ProjectorRays, preserving layout.
 *
 * ProjectorRays turns protected containers into editable ones with the Lingo
 * inside, but it only takes a directory and it writes every output as `.dir` —
 * so a `.CXT` cast library comes back named `.dir`, which Director will not
 * open as a cast. This walks the tree, runs the decompiler per directory, and
 * puts the `.cst` extension back on anything that went in as `.cxt`.
 *
 *   node tools/decompile_director_tree.mjs --in PIP2DATA --out Ext
 *   node tools/decompile_director_tree.mjs --in PIP2DATA --out Ext --copy-other-folders
 *
 * The output directory may not live inside the input: ProjectorRays would read
 * its own output on a second run, and the copy phase would recurse.
 */

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));

/** Containers ProjectorRays decompiles. */
const PROTECTED = new Set([".dxr", ".cxt"]);
/** Already-editable containers, copied through untouched. */
const EDITABLE = new Set([".dir", ".cst"]);

// ------------------------------------------------------------------ helpers

/** Case-insensitive on win32, because the tree names are shouted (PIP2DATA). */
function samePath(a, b) {
  const norm = (p) =>
    process.platform === "win32"
      ? path.resolve(p).toLowerCase()
      : path.resolve(p);
  return norm(a) === norm(b);
}

/** True when `child` is `parent` or sits underneath it. */
export function isInside(child, parent) {
  if (samePath(child, parent)) return true;
  let rel = path.relative(path.resolve(parent), path.resolve(child));
  if (process.platform === "win32") rel = rel.toLowerCase();
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

/** Every file under `root`, as paths relative to it. Directories come too. */
function walk(root) {
  const files = [];
  const dirs = [];
  const stack = [""];
  while (stack.length) {
    const rel = stack.pop();
    for (const entry of fs.readdirSync(path.join(root, rel), {
      withFileTypes: true,
    })) {
      const childRel = path.join(rel, entry.name);
      if (entry.isDirectory()) {
        dirs.push(childRel);
        stack.push(childRel);
      } else if (entry.isFile()) {
        files.push(childRel);
      }
    }
  }
  return { files, dirs };
}

/**
 * ProjectorRays names every output `<base>.dir`. Anything that went in as
 * `.cxt` is a cast library, so its output is renamed to `<base>.cst` using the
 * source's own spelling of the base name.
 *
 * Returns one record per input `.cxt`, so a missing or colliding output is
 * reported rather than passed over in silence.
 */
export function restoreCastExtensions(outDir, cxtBaseNames, { dryRun } = {}) {
  const results = [];
  const produced = fs.existsSync(outDir) ? fs.readdirSync(outDir) : [];
  for (const base of cxtBaseNames) {
    const match = produced.find(
      (name) =>
        path.extname(name).toLowerCase() === ".dir" &&
        path.basename(name, path.extname(name)).toLowerCase() ===
          base.toLowerCase(),
    );
    if (!match) {
      // On a dry run the decompiler never produced anything, so an absent
      // output is expected rather than a fault.
      results.push({
        base,
        status: dryRun ? "planned" : "missing",
        to: path.join(outDir, `${base}.cst`),
      });
      continue;
    }
    const from = path.join(outDir, match);
    const to = path.join(outDir, `${base}.cst`);
    if (fs.existsSync(to) && !samePath(from, to)) {
      results.push({ base, status: "collision", to });
      continue;
    }
    if (!dryRun) fs.renameSync(from, to);
    results.push({ base, status: "renamed", from, to });
  }
  return results;
}

// --------------------------------------------------------------------- cli

function parseArgs(argv) {
  const opts = {
    in: null,
    out: null,
    projectorrays: null,
    copyOtherFolders: false,
    dryRun: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) fail(`${arg} needs a value`);
      return value;
    };
    switch (arg) {
      case "--in":
      case "-i":
        opts.in = next();
        break;
      case "--out":
      case "-o":
        opts.out = next();
        break;
      case "--projectorrays":
      case "-p":
        opts.projectorrays = next();
        break;
      case "--copy-other-folders":
        opts.copyOtherFolders = true;
        break;
      case "--dry-run":
      case "-n":
        opts.dryRun = true;
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
        break;
      default:
        fail(`unknown argument: ${arg}`);
    }
  }
  return opts;
}

function usage() {
  console.log(`
Decompile a Director tree with ProjectorRays, keeping relative paths.

  --in, -i <dir>          tree of .DXR/.CXT/.DIR/.CST to read        (required)
  --out, -o <dir>         where to write; may not be inside --in     (required)
  --projectorrays, -p     path to projectorrays-*.exe
                          (default: newest one beside this script)
  --copy-other-folders    also copy non-Director files from SUBfolders
                          (loose files in the input root are skipped)
  --dry-run, -n           report what would happen, touch nothing
`);
}

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

/** Newest `projectorrays-*.exe` beside this script, or an explicit path. */
function findProjectorRays(explicit) {
  if (explicit) {
    if (!fs.existsSync(explicit)) fail(`ProjectorRays not found: ${explicit}`);
    return path.resolve(explicit);
  }
  const candidates = fs
    .readdirSync(HERE)
    .filter((name) => /^projectorrays-.*\.exe$/i.test(name))
    .sort();
  if (!candidates.length) {
    fail(
      `no projectorrays-*.exe beside ${path.relative(process.cwd(), HERE) || "."}; ` +
        `pass --projectorrays <path>`,
    );
  }
  return path.join(HERE, candidates[candidates.length - 1]);
}

// -------------------------------------------------------------------- main

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.in || !opts.out) {
    usage();
    fail("--in and --out are both required");
  }

  const inRoot = path.resolve(opts.in);
  const outRoot = path.resolve(opts.out);
  if (!fs.existsSync(inRoot) || !fs.statSync(inRoot).isDirectory()) {
    fail(`--in is not a directory: ${inRoot}`);
  }
  // Rule 2. Nested output would be re-read on the next run and re-copied by
  // the copy phase, so this is refused rather than worked around.
  if (isInside(outRoot, inRoot)) {
    fail(`--out may not be inside --in\n  in:  ${inRoot}\n  out: ${outRoot}`);
  }

  const exe = findProjectorRays(opts.projectorrays);
  const { files, dirs } = walk(inRoot);

  // Group the protected containers by the directory holding them: ProjectorRays
  // takes a directory, so one invocation covers each folder.
  const byDir = new Map();
  const copyAsIs = [];
  const otherFiles = [];
  for (const rel of files) {
    const ext = path.extname(rel).toLowerCase();
    const dir = path.dirname(rel);
    if (PROTECTED.has(ext)) {
      if (!byDir.has(dir)) byDir.set(dir, []);
      byDir.get(dir).push(rel);
    } else if (EDITABLE.has(ext)) {
      copyAsIs.push(rel); // rule 6, at any depth including the root
    } else if (dir !== ".") {
      otherFiles.push(rel); // rule 3, subfolders only
    }
  }

  console.log(`ProjectorRays : ${exe}`);
  console.log(`in            : ${inRoot}`);
  console.log(`out           : ${outRoot}`);
  console.log(
    `found         : ${[...byDir.values()].flat().length} protected in ` +
      `${byDir.size} folder(s), ${copyAsIs.length} already editable` +
      (opts.copyOtherFolders ? `, ${otherFiles.length} other` : ""),
  );
  if (opts.dryRun) console.log("mode          : dry run, nothing is written");
  console.log("");

  const mkdir = (p) => {
    if (!opts.dryRun) fs.mkdirSync(p, { recursive: true });
  };

  // Recreate every subdirectory so empty ones survive the copy too.
  if (opts.copyOtherFolders) {
    for (const rel of dirs) mkdir(path.join(outRoot, rel));
  }

  let decompiled = 0;
  let renamed = 0;
  const problems = [];

  for (const [dir, members] of [...byDir].sort()) {
    const srcDir = path.join(inRoot, dir);
    const dstDir = path.join(outRoot, dir);
    mkdir(dstDir);

    const label = dir === "." ? "(root)" : dir;
    console.log(`decompile ${label}  (${members.length} file(s))`);

    // **One invocation per file, not per directory, and the output is checked
    // rather than the exit code.** Handing ProjectorRays a directory looks
    // tidier and loses files: it walks the folder, and the first entry it cannot
    // read stops the whole scan -- `Codec unsupported: ER D` on this tree's
    // `DATA.Z` -- after which nothing later in the folder is attempted. It then
    // **exits 0**, so a status check sees success.
    //
    // Measured on `Itamar-Park`, whose root holds three casts beside the DOS
    // engine's archives: the directory run decompiled `bonus.cxt`, hit the
    // archives, and stopped. `global.cxt` and `utils.cxt` were never reached,
    // nothing was reported, and because the folder's rename pass was tied to the
    // same invocation, even `bonus` kept a `.dir` extension it should not have.
    // Per file, all three decompile cleanly.
    //
    // So the exit code is not consulted for success -- the output file is. A
    // decompiler that half-works is the failure this whole script exists to
    // catch, and it announces itself by producing nothing.
    for (const rel of members) {
      const base = path.basename(rel, path.extname(rel));
      const isCast = path.extname(rel).toLowerCase() === ".cxt";
      const wanted = path.join(dstDir, `${base}.dir`);
      const final = path.join(dstDir, isCast ? `${base}.cst` : `${base}.dir`);

      if (opts.dryRun) {
        decompiled++;
        if (isCast) {
          renamed++;
          console.log(`  ${base}.dir -> ${path.basename(final)} (planned)`);
        }
        continue;
      }

      const run = spawnSync(exe, ["decompile", path.join(inRoot, rel), "-o", dstDir], {
        stdio: "inherit",
      });
      if (run.error) {
        problems.push(`${rel}: could not run ProjectorRays: ${run.error.message}`);
        continue;
      }
      if (!fs.existsSync(wanted)) {
        problems.push(
          `${rel}: ProjectorRays wrote no ${base}.dir (exited ${run.status})`,
        );
        continue;
      }
      decompiled++;

      // Rule 5. Only a `.cxt` becomes a `.cst`; a `.dxr` is already a movie and
      // its output name is right.
      if (!isCast) continue;
      if (fs.existsSync(final) && !samePath(wanted, final)) {
        problems.push(`${rel}: ${base}.cst already exists, left the .dir in place`);
        continue;
      }
      fs.renameSync(wanted, final);
      renamed++;
      console.log(`  ${base}.dir -> ${path.basename(final)}`);
    }
  }

  let copied = 0;
  const overwritten = [];
  const copyFile = (rel) => {
    const from = path.join(inRoot, rel);
    const to = path.join(outRoot, rel);
    mkdir(path.dirname(to));
    if (opts.dryRun) {
      copied++;
      return;
    }
    try {
      // Originals off the game media carry the ReadOnly attribute, and Windows
      // refuses copyFileSync onto a read-only destination — so a second run
      // fails on everything the first run copied. Drop the existing file
      // rather than inheriting the problem, and leave the copy writable.
      if (fs.existsSync(to)) {
        overwritten.push(rel);
        try {
          fs.chmodSync(to, 0o666);
        } catch {}
        fs.rmSync(to, { force: true });
      }
      fs.copyFileSync(from, to);
      try {
        fs.chmodSync(to, 0o666);
      } catch {}
      copied++;
    } catch (err) {
      // One unreadable file must not abandon a run over thousands.
      problems.push(`copy ${rel}: ${err.code || err.message}`);
    }
  };
  for (const rel of copyAsIs) copyFile(rel);
  if (opts.copyOtherFolders) for (const rel of otherFiles) copyFile(rel);

  if (overwritten.length) {
    console.log("");
    console.log(
      `note: ${overwritten.length} copied file(s) replaced something already in ` +
        `the output — ProjectorRays writes its own .dir/.cst for unprotected ` +
        `inputs too, and rule 6 copies the original over it:`,
    );
    for (const rel of overwritten.slice(0, 10)) console.log(`  ${rel}`);
    if (overwritten.length > 10) {
      console.log(`  ... and ${overwritten.length - 10} more`);
    }
  }

  console.log("");
  console.log(
    `decompiled ${decompiled}, renamed ${renamed} to .cst, copied ${copied} of ` +
      `${copyAsIs.length + (opts.copyOtherFolders ? otherFiles.length : 0)}`,
  );
  if (problems.length) {
    console.log("");
    console.log(`${problems.length} problem(s):`);
    for (const p of problems) console.log(`  ${p}`);
    process.exit(1);
  }
}

if (process.argv[1] && samePath(process.argv[1], fileURLToPath(import.meta.url))) {
  main();
}
