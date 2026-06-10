/**
 * @schema 2.11
 * @input bars: boolean = true
 */
const W = pencil.width, H = pencil.height;
const r = Math.min(W, H);
const rad = r * 0.2237;
const nodes = [];

nodes.push({
  type: "rectangle", name: "Base", x: 0, y: 0, width: W, height: H, cornerRadius: rad,
  fill: { type: "gradient", gradientType: "linear", rotation: 118, colors: [
    { color: "#F7B267", position: 0 },
    { color: "#EF7B4E", position: 0.48 },
    { color: "#E5483A", position: 1 },
  ] },
});

nodes.push({
  type: "rectangle", name: "Sheen", x: 0, y: 0, width: W, height: H, cornerRadius: rad,
  fill: { type: "gradient", gradientType: "radial", center: { x: 0.28, y: -0.05 }, size: { width: 1.05, height: 0.85 }, colors: [
    { color: "#FFFFFF4D", position: 0 },
    { color: "#FFFFFF00", position: 1 },
  ] },
});

if (pencil.input.bars) {
  const heights = [0.28, 0.50, 0.74, 0.44, 0.24];
  const alphas = ["E6", "FF", "FF", "FF", "E6"];
  const bw = r * 0.082, gap = r * 0.05;
  const total = heights.length * bw + (heights.length - 1) * gap;
  let x = (W - total) / 2;
  heights.forEach((h, i) => {
    const bh = H * h;
    nodes.push({ type: "rectangle", name: "bar", x: x, y: (H - bh) / 2, width: bw, height: bh, cornerRadius: bw / 2, fill: "#FFFFFF" + alphas[i] });
    x += bw + gap;
  });
}

nodes.push({
  type: "rectangle", name: "Edge", x: 0, y: 0, width: W, height: H, cornerRadius: rad,
  fill: "#00000000", stroke: "#FFFFFF45", strokeWidth: Math.max(1, r * 0.008), strokeAlignment: "inner",
});

return nodes;
