// Pretty-print with keys in reading order rather than whatever order the
// record happened to be built in. Keys not listed keep their place after
// the listed ones.
const order = [
  "link-anchor-vectors", "declaration", "generatedBy", "constants",
  "osc", "text", "beatAt", "fresh",
  "name", "why", "hex", "line", "expect", "reason", "anchor",
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
