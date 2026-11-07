#!/usr/bin/env python3
"""Offline HTML swarm plot of one genome's elements: family against length,
coloured by protein, with a menu right of it choosing the elements shown (all,
one molecule type or the NIRVs). The --top most frequent proteins of the genome
get a colour each, the others are grey (`Other`), so the legend stays readable.
"""

import argparse
import colorsys
import json
import random
from html import escape

import pandas as pd
import plotly.graph_objects as go

OTHER = "Other"
# matplotlib's tab20
TAB20 = [
    "#1f77b4", "#aec7e8", "#ff7f0e", "#ffbb78", "#2ca02c", "#98df8a", "#d62728", "#ff9896", "#9467bd", "#c5b0d5",
    "#8c564b", "#c49c94", "#e377c2", "#f7b6d2", "#7f7f7f", "#c7c7c7", "#bcbd22", "#dbdb8d", "#17becf", "#9edae5",
]


def colours(n):
    """tab20, or n hues evenly spaced past 20."""
    if n <= len(TAB20):
        return TAB20[:n]
    return ["#%02x%02x%02x" % tuple(round(c * 255) for c in colorsys.hls_to_rgb(i / n, 0.6, 0.65)) for i in range(n)]


def panels(elements):
    """(title, elements) for each molecule type, then the NIRVs."""
    result = [(t, elements[elements["molecule_type"] == t]) for t in sorted(elements["molecule_type"].unique())]
    nirvs = elements[elements["nirv"]]
    if len(nirvs):
        result.append(("NIRV", nirvs))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--elements", required=True, help="elements.tsv from ee_plot_data.py")
    parser.add_argument("--sample", required=True)
    parser.add_argument("--top", type=int, default=12, help="proteins coloured, the others are Other")
    parser.add_argument("--prefix", required=True, help="writes <prefix>.html")
    args = parser.parse_args()

    elements = pd.read_csv(args.elements, sep="\t", keep_default_na=False, dtype={"nirv": str})
    elements = elements[elements["sample"] == args.sample].copy()
    elements["nirv"] = elements["nirv"] == "true"
    top = elements["protein"].value_counts().head(args.top).index.tolist()
    elements["group"] = elements["protein"].where(elements["protein"].isin(top), OTHER)
    hue_order = top + ([OTHER] if (elements["group"] == OTHER).any() else [])
    palette = dict(zip(top, colours(len(top))), **{OTHER: "#999999"})
    write_html(elements, args.sample, hue_order, palette, f"{args.prefix}.html")


def write_html(elements, sample, hue_order, palette, path):
    # same jitter on every run, and for an element in every view
    jitter = random.Random(0)
    elements = elements.assign(jitter=[round(jitter.uniform(-0.3, 0.3), 3) for _ in range(len(elements))])
    views = [("All", elements)] + panels(elements)
    traces, layouts, owner = [], [], []
    for v, (title, subset) in enumerate(views):
        counts = subset["family"].value_counts()
        families = sorted(counts.index, key=lambda family: (-counts[family], family))
        row = {family: i for i, family in enumerate(families)}
        for protein in hue_order:
            es = subset[subset["group"] == protein]
            if not len(es):
                continue
            traces.append(go.Scatter(
                x=es["length"], y=[row[f] + j for f, j in zip(es["family"], es["jitter"])],
                mode="markers", name=f"{protein} ({len(es)})", visible=v == 0, hoverinfo="text",
                hovertext=[
                    f"{e.element_id} | {e.protein}, {e.length} nt | {e.family} / {e.genus} / {e.species} | {e.molecule_type}"
                    for e in es.itertuples()
                ],
                marker=dict(color=palette[protein], size=7, opacity=0.85, line=dict(width=0.5, color="#fff")),
            ))
            owner.append(v)
        n = len(families)
        layouts.append({
            "height": max(300, 50 * n + 160),
            "yaxis.tickvals": list(range(n)),
            "yaxis.ticktext": families,
            "yaxis.range": [n - 0.5, -0.5],
            "shapes": [
                dict(type="line", xref="paper", x0=0, x1=1, y0=i + 0.5, y1=i + 0.5, line=dict(color="#eee", width=1))
                for i in range(n - 1)
            ],
            "title.text": f"{sample}: {len(subset)} of {len(elements)} elements in {n} families",
        })

    fig = go.Figure(traces)
    fig.update_layout(
        margin=dict(l=160, r=20, t=110, b=60), plot_bgcolor="#fff", paper_bgcolor="#fff", hovermode="closest",
        title=dict(x=0, xanchor="left", font=dict(size=14)), legend_title_text="Protein",
        showlegend=True,  # plotly hides the legend of a single trace otherwise
        xaxis=dict(title_text="Length (nt)", gridcolor="#e6e6e6", zeroline=False),
        yaxis=dict(showgrid=False, zeroline=False),
    )
    fig.update_layout(layouts[0])
    plot = fig.to_html(
        full_html=False, include_plotlyjs=True, div_id="swarm",
        config={"displaylogo": False, "modeBarButtonsToRemove": ["select2d", "lasso2d"], "toImageButtonOptions": {"filename": f"{sample}.swarm", "scale": 2}},
    )
    options = "".join(f'<option value="{v}">{escape(title)} ({len(subset)})</option>' for v, (title, subset) in enumerate(views))
    data = {"owner": owner, "layouts": layouts, "filename": f"{sample}.swarm"}
    with open(path, "w") as out:
        out.write(PAGE.format(title=escape(sample), plot=plot, options=options, data=json.dumps(data).replace("</", "<\\/")))


PAGE = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{title}: elements by family and length</title>
<style>
body {{ margin: 0; background: #fff; color: #444; font: 13px "Open Sans", verdana, arial, sans-serif; }}
.page {{ display: flex; align-items: flex-start; }}
.plot {{ flex: 1; min-width: 0; }}
.controls {{ flex: none; padding: 110px 20px 20px 0; }}
fieldset {{ border: 1px solid #ddd; border-radius: 4px; padding: 6px 12px 8px; margin: 0; }}
legend {{ font-weight: 600; padding: 0 4px; }}
select {{ font: inherit; }}
</style>
</head>
<body>
<div class="page">
<div class="plot">{plot}</div>
<div class="controls"><fieldset><legend>Elements</legend><select id="view">{options}</select></fieldset></div>
</div>
<script>
const D = {data};
const gd = document.getElementById("swarm");
const view = document.getElementById("view");
// PNG from the camera button, SVG from this one
Plotly.react(gd, gd.data, gd.layout, Object.assign({{}}, gd._context, {{
  modeBarButtonsToAdd: [{{
    name: "Download plot as an SVG", icon: Plotly.Icons.disk,
    click: g => Plotly.downloadImage(g, {{format: "svg", filename: D.filename}}),
  }}],
}}));
view.addEventListener("change", () => {{
  const v = Number(view.value);
  gd.style.height = D.layouts[v].height + "px"; // the div keeps the first layout's height otherwise
  Plotly.update(gd, {{visible: D.owner.map(o => o === v)}}, D.layouts[v]);
}});
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
