#!/usr/bin/env python3
"""Write an offline HTML of the genome tree beside a heatmap of elements per
genome and taxon. Right of the plot, a menu chooses the taxonomic level and
checkboxes the virus groups (molecule types and NIRVs) whose elements are
counted. Without a tree, the genomes are in alphabetical order.
"""

import argparse
import csv
import json
import sys
from html import escape

import plotly.graph_objects as go

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
    parser.add_argument("--tree", help="Newick tree of the genomes, one leaf per sample, named by its label")
    parser.add_argument("--output", default="phylogeny_heatmap.html")
    args = parser.parse_args()

    label = {row["sample"]: row.get("label") or row["sample"] for row in csv.DictReader(open(args.genomes), delimiter="\t")}
    sample_of = {name: sample for sample, name in label.items()}
    tree = None
    if args.tree:
        leaves, xs, ys = tree_layout(args.tree)
        samples = [sample_of.get(leaf, leaf) for leaf in leaves]
        missing = sorted(set(label) - set(samples))
        if missing:
            print(f"WARNING: genomes missing from the tree, listed below it: {', '.join(missing)}", file=sys.stderr)
        samples, tree = samples + missing, (xs, ys)
    else:
        samples = sorted(label, key=lambda sample: label[sample])

    index = {sample: i for i, sample in enumerate(samples)}
    genomes = [label.get(sample, sample) for sample in samples]
    elements = list(csv.DictReader(open(args.elements), delimiter="\t"))
    write_html(elements, index, genomes, tree, args.output)


def write_html(elements, index, genomes, tree, path):
    n = len(genomes)
    tree_width = 260 if tree else 0
    # without the tree on the left, the first rotated taxon label needs room
    # the bottom margin follows the longest taxon label, set in the browser
    # the right margin holds the genome names, the filters sit right of it
    margin = {"l": 40 if tree else 110, "r": 30 + 7 * max(map(len, genomes), default=0), "t": 130, "b": 220}
    # one heatmap, recounted in the browser from the chosen level and virus groups
    traces = [go.Heatmap(
        z=[[]], hoverinfo="text", xaxis="x2", yaxis="y", xgap=1, ygap=1, zmin=0,
        colorscale=[[0, "#ffffff"], [0.0001, "#fde0c5"], [0.5, "#eb7f54"], [1, "#7a0403"]],
        colorbar=dict(title=dict(text="EVEs", side="top"), orientation="h", x=1, xanchor="right", y=1.01, yanchor="bottom", thickness=12),
    )]
    if tree:
        traces.append(go.Scatter(x=tree[0], y=tree[1], mode="lines", xaxis="x", yaxis="y", line=dict(color="#444", width=1), hoverinfo="skip"))
    fig = go.Figure(traces)
    fig.update_layout(
        height=max(300, 24 * n + margin["t"] + margin["b"]), margin=margin, showlegend=False,
        plot_bgcolor="#fff", paper_bgcolor="#fff", title=dict(x=0, xanchor="left", pad=dict(l=40), font=dict(size=16)),
        yaxis=dict(range=[n - 0.5, -0.5], tickvals=list(range(n)), ticktext=genomes, side="right", anchor="x2", showgrid=False, zeroline=False),
        xaxis=dict(visible=False),
        xaxis2=dict(tickangle=-60, showgrid=False, zeroline=False, automargin=False),
    )
    plot = fig.to_html(
        full_html=False, include_plotlyjs=True, div_id="phylogeny_heatmap",
        config={"displaylogo": False, "modeBarButtonsToRemove": ["select2d", "lasso2d"], "toImageButtonOptions": {"filename": "phylogeny_heatmap", "scale": 2}},
    )

    # virus groups: each molecule type, then the NIRVs; an element is shown when any of its groups is ticked
    groups = sorted({e["molecule_type"] for e in elements})
    nirv = any(e["nirv"] == "true" for e in elements)
    levels = "".join(f'<option{" selected" if level == "family" else ""}>{level}</option>' for level in LEVELS)
    boxes = "".join(
        f'<label><input type="checkbox" value="{escape(group)}"{"" if is_nirv else " checked"}> {escape(group)}</label>'
        for group, is_nirv in [(g, False) for g in groups] + ([("NIRV", True)] if nirv else [])
    )
    data = {
        "levels": LEVELS, "genomes": genomes, "tree": bool(tree), "treeWidth": tree_width, "margin": margin,
        # [genome row, molecule type, NIRV, realm ... genus]
        "elements": [[index[e["sample"]], e["molecule_type"], e["nirv"] == "true"] + [e[level] for level in LEVELS] for e in elements],
    }
    with open(path, "w") as out:
        out.write(PAGE.format(plot=plot, levels=levels, boxes=boxes, data=json.dumps(data).replace("</", "<\\/")))


PAGE = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Elements per genome and taxon</title>
<style>
body {{ margin: 0; background: #fff; color: #444; font: 13px "Open Sans", verdana, arial, sans-serif; }}
.page {{ display: flex; align-items: flex-start; }}
.controls {{ display: flex; flex-direction: column; gap: 12px; padding: 130px 20px 20px 0; flex: none; }}
fieldset {{ border: 1px solid #ddd; border-radius: 4px; padding: 6px 12px 8px; margin: 0; }}
legend {{ font-weight: 600; padding: 0 4px; }}
select {{ font: inherit; }}
#groups label {{ display: block; margin: 2px 0; white-space: nowrap; cursor: pointer; }}
</style>
</head>
<body>
<div class="page">
{plot}
<div class="controls">
<fieldset><legend>Taxonomic level</legend><select id="level">{levels}</select></fieldset>
<fieldset id="groups"><legend>Virus groups</legend>{boxes}</fieldset>
</div>
</div>
<script>
const D = {data};
const gd = document.getElementById("phylogeny_heatmap");
const level = document.getElementById("level");
const boxes = Array.from(document.querySelectorAll("#groups input"));
function draw() {{
  const col = 3 + D.levels.indexOf(level.value);
  const on = new Set(boxes.filter(b => b.checked).map(b => b.value));
  const shown = D.elements.filter(e => on.has(e[1]) || (e[2] && on.has("NIRV")));
  const counts = new Map();
  for (const e of shown) {{
    if (!counts.has(e[col])) counts.set(e[col], new Array(D.genomes.length).fill(0));
    counts.get(e[col])[e[0]]++;
  }}
  const total = new Map(Array.from(counts, ([t, c]) => [t, c.reduce((a, b) => a + b, 0)]));
  const taxa = Array.from(counts.keys()).sort((a, b) => total.get(b) - total.get(a) || (a < b ? -1 : a > b ? 1 : 0));
  const z = D.genomes.map((_, g) => taxa.map(t => counts.get(t)[g]));
  const text = D.genomes.map((name, g) => taxa.map(t => name + " | " + t + ": " + counts.get(t)[g]));
  const width = D.treeWidth + Math.max(taxa.length, 1) * 26;
  const ticks = taxa.map((_, i) => i);
  // room for the longest label, rotated 60 degrees
  const bottom = 30 + Math.ceil(6.2 * Math.max(0, ...taxa.map(t => t.length)));
  const height = 24 * D.genomes.length + D.margin.t + bottom;
  // the div keeps the first layout's size otherwise
  gd.style.height = height + "px";
  // at least as wide as the title; the extra width goes to the right margin
  const full = Math.max(width + D.margin.l + D.margin.r, 520);
  gd.style.width = full + "px";
  Plotly.update(gd, {{
    x: [ticks], y: [D.genomes.map((_, g) => g)], z: [z], text: [text],
    zmax: [Math.max(1, ...z.map(row => Math.max(0, ...row)))], "colorbar.len": [Math.min(1, 200 / width)],
  }}, {{
    width: full, "margin.r": full - width - D.margin.l,
    height: height, "margin.b": bottom,
    "xaxis2.domain": [D.tree ? (D.treeWidth - 10) / width : 0, 1],
    "xaxis2.tickvals": ticks, "xaxis2.ticktext": taxa, "xaxis2.range": [-0.5, taxa.length - 0.5],
    "xaxis.domain": D.tree ? [0, (D.treeWidth - 30) / width] : [0, 0],
    "title.text": "<b>Endogenous viral elements per genome and taxon</b><br><span style='font-size:13px'>" + shown.length + " elements in " + taxa.length + " " + level.value + " taxa, " + D.genomes.length + " genomes" + (D.tree ? "" : " (no tree: alphabetical order)") + "</span>",
  }}, [0]);
}}
// PNG from the camera button, SVG from this one
Plotly.react(gd, gd.data, gd.layout, Object.assign({{}}, gd._context, {{
  modeBarButtonsToAdd: [{{
    name: "Download plot as an SVG", icon: Plotly.Icons.disk,
    click: g => Plotly.downloadImage(g, {{format: "svg", filename: "phylogeny_heatmap"}}),
  }}],
}}));
level.addEventListener("change", draw);
boxes.forEach(b => b.addEventListener("change", draw));
draw();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
