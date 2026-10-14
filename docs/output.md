# nf-core/evefinder: Output

## Introduction

This document describes the output produced by each `--step` of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Prepare inputs](#prepare-inputs) - Genomes, host baits, viral database and the screening samplesheet (`--step prepare_inputs`)
- [Screening](#screening) - Endogenous elements of each genome and their clusters (`--step screening`)
- [Phylogeny](#phylogeny) - Tree of the genomes (`--step analysis`)
- [Plots](#plots) - Elements per genome and taxon, Krona and swarm plots (`--step analysis`)
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Prepare inputs

<details markdown="1">
<summary>Output files</summary>

- `prepare_inputs/`
  - `samplesheet.csv`: the samplesheet for `--step screening`, pointing to the files below.
  - `genomes/`: each genome, as downloaded from NCBI (`<accession>/ncbi_dataset/data/<accession>/*.fna`, plus its GFF3) or ENA (`<accession>.fasta.gz`).
  - `host_baits/host_<taxid>.{fa,log,tracking.tsv,clstr}` and the search index of the FASTA: the host protein baits of each host taxon (`eefinder get-databases host`).
  - `host_baits/host_taxa.tsv`: the taxon each host's baits come from, and its rank (`requested` for the host itself).
  - `virus_db/`: with `--download_virus_db true`, the viral protein database (FASTA, metadata CSV, log, tracking table and search index) of each `virus_taxid` (`eefinder get-databases virus`).

</details>

### Screening

<details markdown="1">
<summary>Output files</summary>

- `screening/<sample>/`
  - `<sample>.EEs.fa`, `<sample>.EEs.tax.tsv`, `<sample>.EEs.gff3`, `<sample>.EEs.flanks.fa`: the elements found by EEfinder, their taxonomy, their annotation and their flanking regions.
  - `<sample>.EEs.faa`: the protein of each CDS of the elements. A CDS is the ORF (ATG to stop codon, standard code) of a viral protein hit's reading frame that overlaps the hit most; the CDSs are the `CDS` children of the elements in the GFF3 (`Name` = the protein's name, numbered `fragment 1, 2...` when an element has several, `hit` = the reference protein), flagged `pseudo=true` when the hit's aligned region has stop codons and `partial=true` when the ORF reaches the element's edge.
  - `<sample>.EEs.clusters.fa`: the representative of each cluster of elements (`--cluster_tool` cd-hit-est or vclust, unless `--skip_clustering`; the tool's own output goes to `tmp_files/`).
  - `<sample>.EEs.clusters.tsv`: every element with its cluster, its representative, and its identity and alignment coverage to it (columns in [usage](usage.md#--step-screening)).
  - `tmp_files/`: EEfinder intermediates, unless `--removetmp`.
- `screening/skipped_genomes.tsv`: genomes left with no element, and why.

</details>

### Phylogeny

<details markdown="1">
<summary>Output files</summary>

- `phylogeny/`
  - `genomes.nwk`: the mashtree tree of the genomes (Newick), one leaf per `sample`. Not written with fewer than 3 genomes.
  - `genomes.tsv`: the Mash distance between every pair of genomes.

</details>

### Plots

<details markdown="1">
<summary>Output files</summary>

- `plots/`
  - `phylogeny_heatmap.html`: the genome tree beside the number of elements of each genome per taxon, with taxonomic level, molecule type and NIRV filters and PNG/SVG export (details in [usage](usage.md#--step-analysis)).
  - `elements.tsv`: the table every plot is drawn from, one row per element: `sample`, `element_id`, `length`, `molecule_type`, `realm` to `species` (`Unk` when unknown), `protein` (the first of the element's proteins) and `nirv` (`true`/`false`).
  - `genomes.tsv`: every genome of the samplesheet and its number of elements, 0 included.
  - `<sample>/<sample>.krona.html`: Krona chart of a genome's elements, one dataset of all of them, one per molecule type and one of the NIRVs.
  - `<sample>/<sample>.swarm.{png,svg}`: swarm plot of a genome's elements, family against length, coloured by protein, one panel per molecule type and one of the NIRVs.

</details>

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

The report lists the software versions of every tool the run used, and a methods description citing them. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://docs.seqera.io/platform-cloud/reports/overview) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
