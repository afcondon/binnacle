// Writes the generated tables into DIAPHUS-INBOUND.md and ES9-OSC.md from
// the descriptions in test/Reference/Daemons.purs (`write`), or fails if a
// document's table is not what the descriptions give (`check`).
//
// Run through `make vectors` and `make check-vectors`, after `spago build`.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
const generated = await import(here("../output/Test.Generate/index.js"));

const documents = [
  { file: "DIAPHUS-INBOUND.md", marker: "diaphus", table: generated.diaphusTable },
  { file: "ES9-OSC.md", marker: "es9", table: generated.es9Table },
];

let stale = 0;
for (const { file, marker, table } of documents) {
  const path = here(file);
  const before = readFileSync(path, "utf8");
  const open = `<!-- generated:${marker} -->`;
  const close = `<!-- /generated:${marker} -->`;
  const from = before.indexOf(open);
  const to = before.indexOf(close);
  if (from < 0 || to < from) throw new Error(`${file} has no ${marker} markers`);
  const after = before.slice(0, from + open.length) + "\n" + table + "\n" + before.slice(to);
  if (process.argv[2] === "write") writeFileSync(path, after);
  else if (before !== after) {
    console.log(`FAIL  conformance/${file}'s table is not what the descriptions give; run \`make vectors\``);
    stale++;
  }
}
if (process.argv[2] !== "write") {
  if (stale) process.exit(1);
  console.log("declarations: the tables are current");
}
