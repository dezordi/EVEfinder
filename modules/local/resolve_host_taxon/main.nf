// Closest taxon to `taxid` with an annotated assembly, up to `max_rank`
process RESOLVE_HOST_TAXON {
    tag "${taxid}"
    label 'process_single'

    // Local EEfinder 2.0.0 build (DIAMOND exit-status fix), not on Docker Hub yet
    container "docker.io/dezordi/eefinder@sha256:75366bb63e4672daa6839ba4caa8224dd5472e69b9d1b29d8f65a14aa15e5916"

    input:
    tuple val(taxid), val(refseq), val(max_rank)

    output:
    tuple val(taxid), env('BAITS_TAXID'), env('BAITS_RANK'), emit: taxon
    tuple val("${task.process}"), val('datasets'), eval("datasets --version | sed 's/.*: //'"), topic: versions, emit: versions_datasets

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    python3 <<'EOF'
    import json, subprocess, sys

    taxid, refseq, max_rank = "${taxid}", ${refseq ? 'True' : 'False'}, "${max_rank}"
    ranks = ["species", "genus", "family", "order", "class", "phylum", "kingdom"]

    def datasets(*args):
        run = subprocess.run(["datasets", *args, "--as-json-lines"], capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(f"datasets {' '.join(args)} failed: {run.stderr.strip()}")
        return [line for line in run.stdout.splitlines() if line.startswith("{")]

    def annotated(tax):
        query = ["summary", "genome", "taxon", str(tax), "--annotated", "--limit", "1"]
        if refseq:
            query += ["--assembly-source", "RefSeq"]
        # no match is an exit 0 with no records
        return bool(datasets(*query))

    lineage = json.loads(datasets("summary", "taxonomy", "taxon", taxid)[0])["taxonomy"]["classification"]
    candidates = [(taxid, "requested")]
    for rank in ranks[: ranks.index(max_rank) + 1]:
        if rank in lineage and str(lineage[rank]["id"]) not in (c[0] for c in candidates):
            candidates.append((str(lineage[rank]["id"]), rank))

    for tax, rank in candidates:
        if annotated(tax):
            with open("baits_taxon.tsv", "w") as out:
                out.write(f"{tax}\\t{rank}\\n")
            break
    else:
        kind = "RefSeq annotated" if refseq else "annotated"
        sys.exit(f"No {kind} assembly for taxon {taxid} or its lineage up to the {max_rank}")
    EOF

    BAITS_TAXID=\$(cut -f1 baits_taxon.tsv)
    BAITS_RANK=\$(cut -f2 baits_taxon.tsv)
    """

    stub:
    """
    BAITS_TAXID=${taxid}
    BAITS_RANK=requested
    """
}
