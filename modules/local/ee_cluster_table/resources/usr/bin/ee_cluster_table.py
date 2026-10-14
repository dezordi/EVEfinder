#!/usr/bin/env python3
"""Write a genome's element clusters as the standard cluster table, plus a FASTA
of the representatives.

Inputs: a cd-hit-est `.clstr` (run with `-p 1`, for the alignment coordinates),
or a `vclust cluster --out-repr` table with its `vclust align` table, or nothing
(each element its own cluster).
"""

import argparse
import csv
import re

COLUMNS = [
    "sample",
    "sequence_id",
    "length",
    "cluster_id",
    "is_representative",
    "representative_id",
    "identity",
    "member_coverage",
    "representative_coverage",
]

MEMBER = re.compile(
    r"^\d+\s+(?P<length>\d+)nt, >(?P<id>.+?)\.\.\. "
    r"(?:(?P<rep>\*)|at (?P<q1>\d+):(?P<q2>\d+):(?P<r1>\d+):(?P<r2>\d+)/[+-]/(?P<identity>[\d.]+)%)$"
)


def row(sample, number, sequence_id, length, rep_id, identity, member_coverage, rep_coverage):
    return {
        "sample": sample,
        "sequence_id": sequence_id,
        "length": length,
        "cluster_id": f"{sample}_cl{number}",
        "is_representative": "true" if sequence_id == rep_id else "false",
        "representative_id": rep_id,
        "identity": f"{identity:.2f}",
        "member_coverage": f"{member_coverage:.2f}",
        "representative_coverage": f"{rep_coverage:.2f}",
    }


def parse_clstr(lines, sample):
    """Rows of a cd-hit-est `.clstr` (run with -p 1), in cd-hit's cluster order."""
    clusters = []
    for line in lines:
        line = line.rstrip("\n")
        if line.startswith(">Cluster"):
            clusters.append([])
        elif line:
            match = MEMBER.match(line)
            if match is None:
                raise ValueError(
                    f"unexpected .clstr line (was cd-hit-est run with -p 1?): {line}"
                )
            clusters[-1].append(match)

    rows = []
    for number, members in enumerate(clusters, start=1):
        rep = next(m for m in members if m["rep"])
        rep_length = int(rep["length"])
        for member in members:
            length = int(member["length"])
            if member["rep"]:
                values = (100.0, 100.0, 100.0)
            else:
                q1, q2, r1, r2 = (int(member[key]) for key in ("q1", "q2", "r1", "r2"))
                values = (
                    float(member["identity"]),
                    (abs(q2 - q1) + 1) / length * 100,
                    (abs(r2 - r1) + 1) / rep_length * 100,
                )
            rows.append(row(sample, number, member["id"], length, rep["id"], *values))
    return rows


def parse_vclust(cluster_lines, align_lines, lengths, sample):
    """Rows of a `vclust cluster --out-repr` table, with ANI and coverages from
    `vclust align`, numbered from the longest representative as cd-hit-est does."""
    pairs = {}
    for pair in csv.DictReader(align_lines, delimiter="\t"):
        pairs[(pair["query"], pair["reference"])] = pair

    members = {}
    for entry in csv.DictReader(cluster_lines, delimiter="\t"):
        members.setdefault(entry["cluster"], []).append(entry["object"])

    rows = []
    reps = sorted(members, key=lambda rep: (-lengths[rep], rep))
    for number, rep in enumerate(reps, start=1):
        ordered = [rep] + sorted((m for m in members[rep] if m != rep), key=lambda m: (-lengths[m], m))
        for member in ordered:
            if member == rep:
                values = (100.0, 100.0, 100.0)
            elif (member, rep) in pairs:
                pair = pairs[(member, rep)]
                values = (float(pair["ani"]) * 100, float(pair["qcov"]) * 100, float(pair["rcov"]) * 100)
            elif (rep, member) in pairs:
                # only the other direction was aligned: its query is the representative
                pair = pairs[(rep, member)]
                values = (float(pair["ani"]) * 100, float(pair["rcov"]) * 100, float(pair["qcov"]) * 100)
            else:
                raise ValueError(f"vclust clustered {member} with {rep} but aligned neither way")
            rows.append(row(sample, number, member, lengths[member], rep, *values))
    return rows


def singletons(lengths, sample):
    """Rows making each element its own cluster, numbered from the longest."""
    ordered = sorted(lengths, key=lambda name: (-lengths[name], name))
    return [row(sample, n, name, lengths[name], name, 100.0, 100.0, 100.0) for n, name in enumerate(ordered, start=1)]


def read_fasta(lines):
    """{id: sequence}, the id being the header up to the first space."""
    sequences, name = {}, None
    for line in lines:
        line = line.strip()
        if line.startswith(">"):
            name = line[1:].split()[0]
            sequences[name] = []
        elif name is not None:
            sequences[name].append(line)
    return {name: "".join(parts) for name, parts in sequences.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--elements", required=True, help="the clustered elements (FASTA)")
    parser.add_argument("--clusters", help="cd-hit-est .clstr, or vclust cluster --out-repr TSV; none: every element its own cluster")
    parser.add_argument("--align", help="vclust align TSV (vclust only)")
    parser.add_argument("--sample", required=True, help="sample the elements come from")
    parser.add_argument("--prefix", required=True, help="writes PREFIX.tsv and PREFIX.fa")
    args = parser.parse_args()

    with open(args.elements) as handle:
        sequences = read_fasta(handle)
    lengths = {name: len(seq) for name, seq in sequences.items()}
    if not args.clusters:
        rows = singletons(lengths, args.sample)
    elif args.align:
        with open(args.clusters) as clusters, open(args.align) as align:
            rows = parse_vclust(clusters, align, lengths, args.sample)
    else:
        with open(args.clusters) as clusters:
            rows = parse_clstr(clusters, args.sample)

    with open(f"{args.prefix}.tsv", "w") as out:
        out.write("\t".join(COLUMNS) + "\n")
        for entry in rows:
            out.write("\t".join(str(entry[column]) for column in COLUMNS) + "\n")
    with open(f"{args.prefix}.fa", "w") as out:
        for entry in rows:
            if entry["is_representative"] == "true":
                out.write(f">{entry['sequence_id']}\n{sequences[entry['sequence_id']]}\n")


if __name__ == "__main__":
    main()
