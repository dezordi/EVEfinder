#!/usr/bin/env python3
"""Write an offline HTML of the genome tree beside a heatmap of elements per
genome and taxon, filtered in the browser by taxonomic level, molecule type and
NIRV-only. Without a tree, the genomes are in alphabetical order.
"""

import argparse
import csv
import json
import sys

LEVELS = ["realm", "kingdom", "phylum", "class", "order", "family", "genus"]


def tree_layout(path):
    """Leaves top to bottom, and the tree's lines as x/y lists split by None."""
    from Bio import Phylo

    tree = Phylo.read(path, "newick")
    leaves = tree.get_terminals()
    # without branch lengths, drawn as a cladogram
    has_lengths = any(clade.branch_length for clade in tree.find_clades())
    x, y = {}, {leaf: i for i, leaf in enumerate(leaves)}

    def place(clade, depth):
        x[clade] = depth
        for child in clade.clades:
            place(child, depth + ((child.branch_length or 0) if has_lengths else 1))
        if clade.clades:
            y[clade] = (y[clade.clades[0]] + y[clade.clades[-1]]) / 2

    place(tree.root, 0)
    xs, ys = [], []
    for clade in tree.find_clades():
        if clade.clades:
            xs += [x[clade], x[clade], None]
            ys += [y[clade.clades[0]], y[clade.clades[-1]], None]
            for child in clade.clades:
                xs += [x[clade], x[child], None]
                ys += [y[child], y[child], None]
    return [leaf.name for leaf in leaves], xs, ys


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--elements", required=True, help="elements.tsv from ee_plot_data.py")
    parser.add_argument("--genomes", required=True, help="genomes.tsv from ee_plot_data.py")
    parser.add_argument("--tree", help="Newick tree of the genomes, one leaf per sample")
    parser.add_argument("--output", default="phylogeny_heatmap.html")
    args = parser.parse_args()

    from plotly.offline import get_plotlyjs

    samples = [row["sample"] for row in csv.DictReader(open(args.genomes), delimiter="\t")]
    tree = None
    if args.tree:
        leaves, xs, ys = tree_layout(args.tree)
        missing = sorted(set(samples) - set(leaves))
        if missing:
            print(f"WARNING: genomes missing from the tree, listed below it: {', '.join(missing)}", file=sys.stderr)
        genomes, tree = leaves + missing, {"x": xs, "y": ys}
    else:
        genomes = sorted(samples)

    index = {genome: i for i, genome in enumerate(genomes)}
    elements = [
        [index[row["sample"]], row["molecule_type"], row["nirv"] == "true", *(row[level] for level in LEVELS)]
        for row in csv.DictReader(open(args.elements), delimiter="\t")
    ]
    data = {"genomes": genomes, "levels": LEVELS, "elements": elements, "tree": tree}
    html = (
        TEMPLATE.replace("__PLOTLYJS__", get_plotlyjs())
        .replace("__DATA__", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"))
    )
    with open(args.output, "w") as handle:
        handle.write(html)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EVEs per genome</title>
<style>
  body { margin: 16px; font: 14px/1.4 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; color: #222; background: #fff; }
  h1 { font-size: 18px; margin: 0 0 12px; }
  .controls { display: flex; flex-wrap: wrap; gap: 8px 24px; align-items: flex-start; margin-bottom: 8px; }
  fieldset { border: 1px solid #ccc; border-radius: 4px; padding: 6px 10px; margin: 0; }
  legend { font-weight: 600; padding: 0 4px; }
  label { margin-right: 10px; white-space: nowrap; }
  button { font: inherit; font-size: 12px; margin-left: 6px; }
  #summary { color: #555; margin: 4px 0 0; }
  #plot { overflow-x: auto; }
</style>
<script>__PLOTLYJS__</script>
</head>
<body>
<h1>EVEs per genome</h1>
<div class="controls">
  <fieldset><legend>Taxonomic level</legend><select id="level"></select></fieldset>
  <fieldset><legend>Molecule type <button id="all">all</button><button id="none">none</button></legend><div id="types"></div></fieldset>
  <fieldset><legend>Filter</legend><label><input type="checkbox" id="nirv"> NIRVs only (non-retroviral RNA viruses)</label></fieldset>
</div>
<p id="summary"></p>
<div id="plot"></div>
<script>
const D = __DATA__;
const plot = document.getElementById("plot");
const levelSelect = document.getElementById("level");
const typesBox = document.getElementById("types");
const nirvBox = document.getElementById("nirv");

for (const level of D.levels) {
  levelSelect.add(new Option(level, level, false, level === "family"));
}
const typeCounts = {};
for (const e of D.elements) typeCounts[e[1]] = (typeCounts[e[1]] || 0) + 1;
for (const type of Object.keys(typeCounts).sort()) {
  const label = document.createElement("label");
  label.innerHTML = '<input type="checkbox" checked> ';
  label.firstChild.value = type;
  label.append(`${type} (${typeCounts[type]})`);
  typesBox.append(label);
}
const typeInputs = () => [...typesBox.querySelectorAll("input")];

function counts() {
  const li = D.levels.indexOf(levelSelect.value);
  const types = new Set(typeInputs().filter(i => i.checked).map(i => i.value));
  const byTaxon = new Map();
  let total = 0;
  for (const e of D.elements) {
    if (!types.has(e[1]) || (nirvBox.checked && !e[2])) continue;
    const taxon = e[3 + li];
    if (!byTaxon.has(taxon)) byTaxon.set(taxon, new Array(D.genomes.length).fill(0));
    byTaxon.get(taxon)[e[0]] += 1;
    total += 1;
  }
  const sum = a => a.reduce((s, v) => s + v, 0);
  const taxa = [...byTaxon.keys()].sort((a, b) => sum(byTaxon.get(b)) - sum(byTaxon.get(a)) || a.localeCompare(b));
  const z = D.genomes.map((_, g) => taxa.map(t => byTaxon.get(t)[g]));
  return { taxa, z, total };
}

function render() {
  const { taxa, z, total } = counts();
  const n = D.genomes.length;
  const treeWidth = D.tree ? 260 : 0;
  const width = treeWidth + Math.max(taxa.length, 1) * 26;
  // without the tree on the left, the first rotated taxon label needs room
  const margin = { l: D.tree ? 20 : 110, r: 240, t: 90, b: 220 };
  const yaxis = {
    range: [n - 0.5, -0.5], tickvals: D.genomes.map((_, i) => i), ticktext: D.genomes,
    side: "right", anchor: "x2", showgrid: false, zeroline: false, ticks: "",
  };
  const traces = [{
    type: "heatmap", x: taxa, y: D.genomes.map((_, i) => i), z, xaxis: "x2", yaxis: "y",
    customdata: D.genomes.map(g => taxa.map(() => g)), xgap: 1, ygap: 1, zmin: 0,
    colorscale: [[0, "#ffffff"], [0.0001, "#fde0c5"], [0.5, "#eb7f54"], [1, "#7a0403"]],
    hovertemplate: "%{customdata}<br>%{x}: %{z}<extra></extra>",
    colorbar: { title: { text: "EVEs", side: "top" }, orientation: "h", x: 1, xanchor: "right", y: 1.01, yanchor: "bottom", len: Math.min(1, 200 / width), thickness: 12 },
  }];
  const layout = {
    width: width + margin.l + margin.r, height: Math.max(300, 24 * n + margin.t + margin.b), margin,
    plot_bgcolor: "#fff", paper_bgcolor: "#fff", showlegend: false, yaxis,
    xaxis2: { domain: [treeWidth ? (treeWidth - 10) / width : 0, 1], tickangle: -60, showgrid: false, zeroline: false, automargin: false },
    annotations: total ? [] : [{ text: "No elements with these filters", xref: "paper", yref: "paper", x: 0.5, y: 0.5, showarrow: false }],
  };
  if (D.tree) {
    traces.push({ type: "scatter", mode: "lines", x: D.tree.x, y: D.tree.y, xaxis: "x", yaxis: "y", line: { color: "#444", width: 1 }, hoverinfo: "skip" });
    layout.xaxis = { domain: [0, (treeWidth - 30) / width], visible: false };
  }
  const name = `eves_${levelSelect.value}${nirvBox.checked ? "_nirv" : ""}`;
  const download = format => gd => Plotly.downloadImage(gd, { format, filename: name, width: layout.width, height: layout.height, scale: format === "png" ? 2 : 1 });
  const drawn = Plotly.react(plot, traces, layout, {
    displaylogo: false, responsive: false,
    modeBarButtonsToRemove: ["toImage", "select2d", "lasso2d"],
    modeBarButtonsToAdd: [
      { name: "Download PNG", icon: Plotly.Icons.camera, click: download("png") },
      { name: "Download SVG", icon: Plotly.Icons.disk, click: download("svg") },
    ],
  });
  document.getElementById("summary").textContent =
    `${total} elements in ${taxa.length} ${levelSelect.value} taxa, ${n} genomes` + (D.tree ? "" : " (no tree: alphabetical order)");
  return drawn;
}

// Plotly.react is asynchronous: a redraw started before the last one ends leaves the plot empty
let drawing = Promise.resolve();
const draw = () => (drawing = drawing.then(render));

levelSelect.addEventListener("change", draw);
nirvBox.addEventListener("change", draw);
typesBox.addEventListener("change", draw);
document.getElementById("all").onclick = () => { typeInputs().forEach(i => (i.checked = true)); draw(); };
document.getElementById("none").onclick = () => { typeInputs().forEach(i => (i.checked = false)); draw(); };
draw();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
