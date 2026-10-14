# nf-core/evefinder: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [unreleased<!-- TODO nf-core: replace with date on release -->]

Initial release of nf-core/evefinder, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- `--step prepare_inputs`: downloads genomes (NCBI Datasets API via nf-core `wget` + `unzip`, or ENA browser API via `wget` + `seqkit/replace` to strip the `ENA|acc|` header prefix), host baits (`eefinder get-databases host`, one per host taxid) and the viral database (`eefinder get-databases virus`, one per `virus_taxid`, `--released-before` defaulting to today), and writes the `screening` samplesheet.
- Host baits for hosts with no annotated assembly come from their closest annotated relative (species, genus, family... up to `--host_max_rank`, default `order`), resolved by `RESOLVE_HOST_TAXON` with `datasets summary`; the choice is logged and written to `prepare_inputs/host_baits/host_taxa.tsv`.
- `--step screening`: one local module per `eefinder screening` stage, using `dezordi/eefinder:2.0.0-dev`; final outputs published as `PREFIX.EEs.*`, intermediates under `tmp_files/` (unless `--removetmp`).
- Every `eefinder get-databases` and `eefinder screening` option exposed as a parameter.
- `local` profile (`conf/local.config`) capping resources at one machine's (16 CPUs, 18 GB), and README instructions for running it with Docker or Singularity/Apptainer.
- Databases are indexed where they are built: `get-databases` gets `-md ${search_mode}` and publishes the index beside each FASTA. `EEFINDER_PREPARE` runs once per database/metadata/baits set (it used to run per genome, indexing both FASTAs every time), reuses the indexes found beside the FASTAs and builds the missing ones; a genome's `align` and `filter` use its set's indexes.
- Genomes left with no element (no viral hit, or every viral hit matching a host bait better) are warned about, listed with the reason in `screening/skipped_genomes.tsv` and left out of the rest of the screening; a failed BLAST/DIAMOND search stays an error.
- EEfinder modules use the Docker Hub image `dezordi/eefinder:2.0.0-dev`, pinned by its `linux/amd64` digest (the tag alone does not pull on arm64, and Singularity/Apptainer refuse a tag and a digest together).
- `docs/usage.md` "Analysis modes": BLAST and DIAMOND sensitivities, gene-prediction translation (`gv`/`rv`/`gv-rv`), viral vs bacterial elements, and the element filters.
- Software versions name every tool a step runs, not only EEfinder: BLAST or DIAMOND (by `--search_mode`), pyrodigal-gv/pyrodigal-rv/cd-hit (by `--translation_method`), bedtools (`align`, `merge`, `flanks`), and datasets/cd-hit for `get-databases`. Each is a `versions` topic tuple; a tool the options do not run gets an empty version, left out of the report.
- The screening clusters each genome's elements with cd-hit-est (nf-core `cdhit/cdhitest`, default) or vclust (`--cluster_tool vclust`, nf-core `vclust/prefilter`, `align` and `cluster`), at 80% identity and 80% coverage of both sequences by default, and writes `<sample>.EEs.clusters.fa` and a standard `<sample>.EEs.clusters.tsv` (cluster, representative, identity, coverage of the element and of the representative). `--skip_clustering`, `--cluster_tool`, `--cluster_identity`, `--cluster_coverage`. `nextflow.enable.moduleBinaries` puts the table script (`modules/local/ee_cluster_table/resources/usr/bin`) on its task's PATH.
- `--step analysis` reads a finished screening (`--screening_outdir`).
- `--step analysis` builds a phylogeny of the samplesheet's genomes, one leaf per sample, published as `phylogeny/genomes.nwk`: mashtree (nf-core `mashtree`). `--skip_phylogeny`. Skipped with a warning below 3 genomes. `RENAME_GENOME` links each genome as `<sample>.fa`, as mashtree names a leaf after its file. nf-core modules are used as they are, unpatched: the BUSCO + BUSCO_phylogenomics + FastTree option was dropped, as `busco/phylogenomics` and `fasttree` needed patches for it.
- `--step analysis` plots the elements in `plots/`: an offline HTML of the genome tree beside a heatmap of elements per genome and taxon, recounted in the browser by taxonomic level, molecule type and NIRV-only (non-retroviral RNA virus) filters, with PNG/SVG export (`EE_PHYLO_HEATMAP`); a Krona chart per genome with a dataset per molecule type and one of the NIRVs (nf-core `krona/ktimporttext`); and a swarm plot per genome, family against length coloured by protein (`EE_SWARMPLOT`). `EE_PLOT_DATA` writes the `elements.tsv` and `genomes.tsv` they are drawn from. `--skip_plots`, `--swarm_top_proteins`. The plot modules share a Seqera Containers image of python, pandas, plotly, seaborn, matplotlib and biopython.
- `test_analysis` profile: `--step analysis` on the results of `-profile test`, read from the same `--outdir`: a mashtree tree of the 3 genomes, and the plots.
- `test` profile running EEfinder's integration-test data, plus two small nf-core test genomes without elements (40 kb of human chr22, SARS-CoV-2) that end in `skipped_genomes.tsv`; the Aedes outputs are byte-identical to EEfinder's golden files.
- nf-test: the pipeline test (`-profile test`) has its snapshot, and the `PHYLOGENY` (mashtree with 3 genomes, skipped with 2) and `PLOTS` (with and without a tree, stub) subworkflows have their own tests. The swarm plot SVG no longer embeds a date or random ids, so its md5 is stable.
- The MultiQC methods description cites the tools the run's `--step` and options used (`CITATIONS.md` lists them all).
- The screening publishes `<sample>.EEs.faa` and the `CDS` children of each element in `<sample>.EEs.gff3` (EEfinder's new `postprocess` output, from the taxonomy stage's hit table): for each viral protein hit (the longest where hits overlap), the ORF of its reading frame (ATG to stop codon) that overlaps it most, named after the protein (`fragment 1, 2...` when an element has several) and flagged `pseudo=true` when the hit's aligned region has stop codons; the element lines no longer carry `product`, `protein_ids` and `host` (still in `<sample>.EEs.tax.tsv`).

### `Fixed`

- `RENAME_GENOME` no longer publishes its links to the genomes in `<outdir>/rename/`.
- The pipeline runs on its minimum Nextflow version again (25.10.4): the `EEFINDER_*` modules whose version commands depend on the options (`align`, `filter`, `prepare`, `getdatabases`) built them in `eval()` from a script variable, which only Nextflow 26 resolves after the script block.
- EEfinder image rebuilt with its fix for elements missing the first base of their first hit (a 1-based hit start used as a BED start): every element ID moves one base to the left; the `test` profile still matches EEfinder's (regenerated) golden files.
- `.nf-test/` is ignored by git.
- `docs/output.md` lists the `prepare_inputs` outputs.
- `EE_PLOT_DATA` writes an element's empty `molecule_type` (left empty by the database) as `Unk`, instead of a Krona dataset file named `.txt` and blank filter labels.

### `Dependencies`

- nf-core template 4.1.0 (from 4.0.2): MultiQC 1.35, `utils_nfschema_plugin` and CI workflows updated, `pr-comment.yml` replaces `linting_comment.yml`, pre-commit hook blocking committed pipeline outputs.

### `Deprecated`

- Removed the template's FastQC module.
