#!/usr/bin/env python3
"""Swarm plot of one genome's elements: family against length, coloured by protein.

One panel per molecule type, plus one with the NIRVs, sharing the length axis.
The --top most frequent proteins of the genome get a colour each, the others
are grey (`Other`), so the legend stays readable.
"""

import argparse

import matplotlib

matplotlib.use("Agg")
# reproducible SVG (no date either, in savefig)
matplotlib.rcParams["svg.hashsalt"] = "evefinder"
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
import seaborn as sns  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402

OTHER = "Other"


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
    parser.add_argument("--prefix", required=True, help="writes <prefix>.png and <prefix>.svg")
    args = parser.parse_args()

    elements = pd.read_csv(args.elements, sep="\t", keep_default_na=False, dtype={"nirv": str})
    elements = elements[elements["sample"] == args.sample].copy()
    elements["nirv"] = elements["nirv"] == "true"
    top = elements["protein"].value_counts().head(args.top).index.tolist()
    elements["protein"] = elements["protein"].where(elements["protein"].isin(top), OTHER)
    hue_order = top + ([OTHER] if (elements["protein"] == OTHER).any() else [])
    colours = sns.color_palette("tab20" if len(top) <= 20 else "husl", len(top))
    palette = dict(zip(top, colours), **{OTHER: (0.6, 0.6, 0.6)})

    sections = panels(elements)
    heights = [s["family"].nunique() + 0.5 for _, s in sections]
    fig, axes = plt.subplots(
        len(sections), 1, sharex=True, squeeze=False,
        figsize=(10, 1 + 0.4 * sum(heights) + 0.5 * len(sections)),
        gridspec_kw={"height_ratios": heights},
    )
    for ax, (title, subset) in zip(axes[:, 0], sections):
        families = subset["family"].value_counts().index.tolist()
        sns.swarmplot(
            data=subset, x="length", y="family", order=families, hue="protein",
            hue_order=hue_order, palette=palette, size=4, legend=False, ax=ax,
        )
        ax.set_title(f"{title} ({len(subset)})", loc="left", fontsize=10, fontweight="bold")
        ax.set_ylabel("")
        ax.set_xlabel("")
        ax.grid(axis="x", color="0.9")
        ax.set_axisbelow(True)
    axes[-1, 0].set_xlabel("Length (nt)")
    handles = [Line2D([], [], marker="o", linestyle="", color=palette[p], label=p) for p in hue_order]
    fig.legend(handles=handles, title="Protein", loc="upper left", bbox_to_anchor=(1, 1), frameon=False, fontsize=8)
    fig.suptitle(f"{args.sample}: {len(elements)} element{'' if len(elements) == 1 else 's'}", x=0.01, ha="left", fontsize=12)
    fig.tight_layout()
    fig.savefig(f"{args.prefix}.png", dpi=200, bbox_inches="tight")
    fig.savefig(f"{args.prefix}.svg", bbox_inches="tight", metadata={"Date": None})


if __name__ == "__main__":
    main()
