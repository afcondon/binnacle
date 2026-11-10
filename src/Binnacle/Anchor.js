// IEEE 754 binary64 to and from eight big-endian bytes. The layout is the
// platform's; nothing here knows what an anchor is.

export const float64Bytes = (value) => {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value, false);
  return Array.from(new Uint8Array(view.buffer));
};

export const float64FromBytes = (bytes) => {
  const view = new DataView(new ArrayBuffer(8));
  bytes.forEach((byte, index) => view.setUint8(index, byte));
  return view.getFloat64(0, false);
};

// A Number already known to be a whole value in 0..255, as an Int.
export const numberToByte = (value) => value | 0;
