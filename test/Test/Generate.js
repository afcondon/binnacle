// Pretty-print with keys in reading order rather than whatever order the
// record happened to be built in. Keys not listed keep their place after
// the listed ones.
const order = [
  "link-anchor-vectors", "link-peers-vectors", "clock-origin-vectors", "declaration", "generatedBy", "constants",
  "osc", "text", "beatAt", "fresh",
  "name", "why", "hex", "line", "expect", "reason", "anchor", "peers",
  "atUnixMicros", "ageMicros",
  "unixMicros", "beat", "tempo", "quantum",
];

const rank = (key) => {
  const index = order.indexOf(key);
  return index < 0 ? order.length : index;
};

const ordered = (value) => {
  if (Array.isArray(value)) return value.map(ordered);
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
      .map((key) => [key, ordered(value[key])])
  );
};

export const pretty = (value) => JSON.stringify(ordered(value), null, 2);

// One case to a line, so that a diff of a vector file reads as a list of
// changed cases.
export const prettyText = (text) => {
  const value = JSON.parse(text);
  const keys = Object.keys(value);
  const out = ["{"];
  keys.forEach((key, index) => {
    const comma = index < keys.length - 1 ? "," : "";
    const v = value[key];
    if (Array.isArray(v) && v.length && typeof v[0] === "object") {
      out.push(`  ${JSON.stringify(key)}: [`);
      v.forEach((item, i) => out.push(`    ${JSON.stringify(item)}${i < v.length - 1 ? "," : ""}`));
      out.push(`  ]${comma}`);
    } else out.push(`  ${JSON.stringify(key)}: ${JSON.stringify(v)}${comma}`);
  });
  out.push("}");
  return out.join("\n");
};
