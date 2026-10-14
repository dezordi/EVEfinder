#!/usr/bin/env python3
"""Gather the `<sample>.EEs.{fa,tax.tsv}` of every sample into the tables the plots read:

- `elements.tsv`: one row per element (length, molecule type, taxonomy, protein,
  NIRV: molecule type with RNA, not ending in -RT);
- `genomes.tsv`: the number of elements of every sample, 0 included;
- `krona/<sample>/<dataset>.txt`: Krona inputs, one dataset with every element,
  one per molecule type and one with the NIRVs.
"""

import argparse
import csv
from collections import Counter
from pathlib import Path

RANKS = ["realm", "kingdom", "phylum", "class", "order", "family", "genus", "species"]
PREFIXES = dict(zip("rkpcofgs", RANKS))
UNKNOWN = "Unk"
COLUMNS = ["sample", "element_id", "length", "molecule_type", *RANKS, "protein", "nirv"]


def is_nirv(molecule_type):
    return "RNA" in molecule_type and not molecule_type.endswith("-RT")


def parse_taxonomy(taxonomy):
    """`r__Riboviria;k__...;f__Flaviviridae` -> one name per rank, Unk when missing."""
    names = dict.fromkeys(RANKS, UNKNOWN)
    for field in taxonomy.split(";"):
        prefix, _, name = field.partition("__")
        if prefix in PREFIXES and name:
            names[PREFIXES[prefix]] = name
    return names


def fasta_lengths(path):
    """Element id (`contig:start-end`, the header minus `<sample>/`) -> length."""
    lengths, name = {}, None
    with open(path) as handle:
        for line in handle:
            line = line.strip()
            if line.startswith(">"):
                name = line[1:].split()[0].split("/", 1)[-1]
                lengths[name] = 0
            elif name:
                lengths[name] += len(line)
    return lengths


def read_elements(sample, fasta, taxonomy):
    lengths = fasta_lengths(fasta)
    with open(taxonomy) as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            # can be empty in the database
            molecule_type = row["molecule_type"] or UNKNOWN
            yield {
                "sample": sample,
                "element_id": row["element_id"],
                "length": lengths[row["element_id"]],
                "molecule_type": molecule_type,
                **parse_taxonomy(row["taxonomy"]),
                # an element hitting several proteins lists them joined by AND
                "protein": row["protein_products"].split(" AND ")[0],
                "nirv": "true" if is_nirv(molecule_type) else "false",
            }


def safe_name(name):
    """A dataset name the shell takes unquoted: `ssRNA(+/-)` -> `ssRNA+-`."""
    return name.replace("(", "").replace(")", "").replace("/", "").replace(";", "_")


def krona_lines(elements):
    """Count of each taxonomic path, ending at its last known rank."""
    paths = Counter()
    for element in elements:
        path = [element[rank] for rank in RANKS]
        while path and path[-1] == UNKNOWN:
            path.pop()
        paths[tuple(path)] += 1
    return ["\t".join([str(count), *path]) + "\n" for path, count in sorted(paths.items())]


def write_krona(sample, elements, outdir):
    datasets = {"all": elements}
    for molecule_type in sorted({e["molecule_type"] for e in elements}):
        datasets[safe_name(molecule_type)] = [e for e in elements if e["molecule_type"] == molecule_type]
    nirvs = [e for e in elements if e["nirv"] == "true"]
    if nirvs:
        datasets["NIRV"] = nirvs
    directory = Path(outdir) / sample
    directory.mkdir(parents=True, exist_ok=True)
    for name, subset in datasets.items():
        (directory / f"{name}.txt").write_text("".join(krona_lines(subset)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--samples", nargs="+", required=True, help="every sample of the samplesheet")
    parser.add_argument("--dir", default=".", help="directory holding the <sample>.EEs.{fa,tax.tsv} files")
    args = parser.parse_args()

    all_elements, counts = [], {}
    for sample in args.samples:
        fasta = Path(args.dir) / f"{sample}.EEs.fa"
        taxonomy = Path(args.dir) / f"{sample}.EEs.tax.tsv"
        elements = list(read_elements(sample, fasta, taxonomy)) if taxonomy.exists() else []
        counts[sample] = len(elements)
        all_elements += elements
        if elements:
            write_krona(sample, elements, "krona")

    with open("elements.tsv", "w", newline="") as handle:
        writer = csv.DictWriter(handle, COLUMNS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(all_elements)
    with open("genomes.tsv", "w") as handle:
        handle.write("sample\telements\n")
        handle.writelines(f"{sample}\t{count}\n" for sample, count in counts.items())


if __name__ == "__main__":
    main()
