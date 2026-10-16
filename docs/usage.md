# nf-core/evefinder: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/evefinder/usage](https://nf-co.re/evefinder/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

The pipeline runs in three steps, chosen with `--step`:
- `prepare_inputs` downloads the genomes, the host baits and the viral database
- `screening` finds the endogenous viral elements (EVEs) of each genome with EEfinder and clusters them
- `analysis` builds the genome phylogeny and plots the EVEs of every genome. Each step reads the output of the one before it.

## Samplesheet input

`--input` takes a different samplesheet for each `--step`.

### `--step prepare_inputs`

```csv title="genomes.csv"
accession,virus_taxid
GCA_021653915.1,11050
GCF_000146045.2,
```

| Column        | Description                                                                                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `accession`   | Assembly accession (`GCA_`/`GCF_`). Downloaded from NCBI (FASTA + GFF3) or, with `--genome_source ena`, from ENA (FASTA; `GCA_` only).                                         |
| `virus_taxid` | Optional. With `--download_virus_db true`, one viral database is downloaded per distinct value; empty cells (or no such column) use EEfinder's default taxon (10239, Viruses). |

The host baits are downloaded once per host taxon, read from the genome's NCBI/ENA record. A host with no annotated assembly (RefSeq, unless `host_refseq: false`) gets the proteins of its closest annotated relative: its species, then genus, family and so on up to `--host_max_rank` (default `order`). The choice is logged as a warning and recorded in `prepare_inputs/host_baits/host_taxa.tsv`. The viral database is either downloaded (`--download_virus_db true`, filtered with `--virus_db_release_date`, which defaults to today) or given with `--virus_db_fasta` + `--virus_db_metadata`.

Outputs go to `<OUTDIR>/prepare_inputs/{genomes,host_baits,virus_db}/`, plus `<OUTDIR>/prepare_inputs/samplesheet.csv` for the next step. The paths in it assume the default publishing configuration.

### `--step screening`

```csv title="samplesheet.csv"
sample,taxid,genome,baits,db_fasta,db_metadata
GCA_021653915.1,7159,/path/genome.fna,/path/host_7159.fa,/path/virus_11050.fa,/path/virus_11050.csv
```

| Column        | Description                                                    |
| ------------- | -------------------------------------------------------------- |
| `sample`      | Sample name, also the EEfinder prefix (`PREFIX.EEs.*`).        |
| `taxid`       | Host taxon id.                                                 |
| `genome`      | Genome FASTA.                                                  |
| `baits`       | Host protein baits FASTA (`eefinder get-databases host`).      |
| `db_fasta`    | Viral protein database FASTA (`eefinder get-databases virus`). |
| `db_metadata` | Its metadata CSV.                                              |

Results go to `<OUTDIR>/screening/<sample>/`: `<sample>.EEs.{fa,tax.tsv,gff3,flanks.fa}` (+ `.cleaned.*` with `--clean_masked true`, and `tmp_outputs/` with `--overlap longest|targets`), and the intermediates under `tmp_files/` unless `--removetmp true`.

Each genome's elements are then clustered (`--skip_clustering true` to skip it), with `--cluster_tool cdhit` (default; cd-hit-est) or `vclust` (vclust prefilter, align and cluster with `--algorithm cd-hit`). An element joins a cluster when it has at least `--cluster_identity` identity (default `0.8`; the lowest cd-hit-est allows, vclust takes lower) to the representative, and the alignment covers at least `--cluster_coverage` (default `0.8`) of both sequences. The representative is the longest element of its cluster. The identity is cd-hit-est's alignment identity, or vclust's ANI, which counts the aligned regions only, so the two tools can group the same elements differently. A genome with a single element is one cluster (vclust is not run on it, as it cannot align a single sequence). Either tool writes `<sample>.EEs.clusters.fa` (the representatives) and `<sample>.EEs.clusters.tsv`, and its own output goes to `tmp_files/`:

| Column                    | Description                                                    |
| ------------------------- | -------------------------------------------------------------- |
| `sample`                  | Sample the element comes from.                                 |
| `sequence_id`             | Element name, as in `<sample>.EEs.fa`.                         |
| `length`                  | Element length (nt).                                           |
| `cluster_id`              | `<sample>_cl<N>`, numbered from the longest representative.    |
| `is_representative`       | `true` for the cluster's representative.                       |
| `representative_id`       | The representative's `sequence_id`.                            |
| `identity`                | % identity to the representative (100 for the representative). |
| `member_coverage`         | % of the element covered by the alignment.                     |
| `representative_coverage` | % of the representative covered by the alignment.              |

A genome left with no element is not an error: when its search finds no viral hit, or every viral hit matches a host bait better (all removed by `filter`), the run warns (`<sample>: no viral hits, left out of the rest of the screening`), lists it with the reason in `<OUTDIR>/screening/skipped_genomes.tsv` and screens the other genomes. A search that fails (a crash, or DIAMOND or BLAST killed for lack of memory) still stops the run, with the failing command and its exit status in the task's error.

### `--step analysis`

Takes the samplesheet of a `--step screening` run and that run's `--outdir` as `--screening_outdir`, and reads `<screening_outdir>/screening/<sample>/<sample>.EEs.{fa,tax.tsv}` for every sample. A sample without them must be in `screening/skipped_genomes.tsv`, and counts as a genome without elements; otherwise the run stops, as the screening of that sample has not run.

The step builds a phylogeny of every genome of the samplesheet with [mashtree](https://github.com/lskatz/mashtree), including those without elements (`--skip_phylogeny true` to skip it; with fewer than 3 genomes it is skipped with a warning). Each leaf is named after its `sample`. It is neighbour joining on Mash distances.

The step then plots the elements (`--skip_plots true` to skip it). A NIRV is an element of a non-retroviral RNA virus: its molecule type has `RNA` and does not end in `-RT`, so `ssRNA-RT` and every DNA virus are left out.

- `plots/phylogeny_heatmap.html`: the tree beside a heatmap of the number of elements of each genome (rows, in the tree's order, or alphabetical without a tree) per taxon (columns).
- `plots/<sample>/<sample>.krona.html`, per genome with elements: a Krona chart of the elements' taxonomy, with one dataset of every element, one per molecule type and one of the NIRVs.
- `plots/<sample>/<sample>.swarm.{png,svg}`, per genome with elements: family against length, coloured by protein (the first protein of an element hitting several), one panel per molecule type and one of the NIRVs. The `--swarm_top_proteins` (default `12`) most frequent proteins of the genome get a colour each, the others are grey (`Other`).

Check the setup with `-profile test_analysis` on the `--outdir` of a `-profile test` run: it reads that run's results (three genomes, one of them with elements: a mashtree tree, and the plots of the genome with elements).

## Analysis modes

Everything below is a `--step screening` parameter, so the same `prepare_inputs` samplesheet can be screened in several ways. Write each run to its own `--outdir`. Changing a search option makes `-resume` rerun everything after `clean`.

### Similarity search (`--search_mode`)

Sets the index type (BLAST or DIAMOND) and the search of `align` and `filter` (EEfinder `-md`). `prepare_inputs` indexes the databases it downloads for this search, beside each FASTA; `screening` reuses an index found beside a FASTA and builds a missing one once per database/baits set, so a local database is best indexed beforehand (`eefinder get-databases -md`, or a first `eefinder screening prepare`).

| Value                                                                                       | Search                                                                          |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `blastx` (default)                                                                          | BLAST. The reference path: its outputs match EEfinder's golden files.           |
| `fast`, `mid-sensitive`, `sensitive`, `more-sensitive`, `very-sensitive`, `ultra-sensitive` | DIAMOND at that sensitivity, from fastest to most sensitive. Faster than BLAST. |

```bash
nextflow run nf-core/evefinder -profile local,docker \
   --step screening \
   --input results/prepare_inputs/samplesheet.csv \
   --outdir results_diamond_fast \
   --search_mode fast
```

### Translation (`--translation_method`)

How the proteins compared against the databases are obtained, for both the viral and the host-bait searches (EEfinder `-tm`). Combine with any `--search_mode`.

| Value               | Proteins                                                                   |
| ------------------- | -------------------------------------------------------------------------- |
| `default` (default) | Six-frame translation: `blastx` or `diamond blastx`.                       |
| `gv`                | Genes predicted with pyrodigal-gv, aligned with `blastp`/`diamond blastp`. |
| `rv`                | Genes predicted with pyrodigal-rv.                                         |
| `gv-rv`             | Both predictions, merged with cd-hit (100% identity/coverage).             |

The prediction modes map the protein coordinates back to the genome, so the outputs keep the same format.

```yaml title="diamond_gv.yml"
step: screening
input: results/prepare_inputs/samplesheet.csv
outdir: results_diamond_gv
search_mode: sensitive
translation_method: gv-rv
```

### Candidate and element filters

| Parameter                                     | Default        | Effect                                                                                                                               |
| --------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `--min_length`                                | `10000`        | Contigs shorter than this are left out of the search (`clean`, `-ln`).                                                               |
| `--range_junction`                            | `100`          | Distance in bases for joining redundant hits (`align`/`filter`, `-rj`).                                                              |
| `--merge_limit`                               | `1`            | Distance in bases for merging neighbouring elements (`merge`, `-lm`).                                                                |
| `--merge_level`                               | `family`       | Merge only elements with the same `family` or `genus` (`-ml`).                                                                       |
| `--clean_masked` / `--mask_per`               | `false` / `50` | Also write `.EEs.cleaned.*` without elements whose sequence is more than `mask_per`% lowercase (soft-masked repeats).                |
| `--overlap`                                   | `keep`         | Overlapping elements: `keep` all, keep the `longest` of each overlap, or keep only `targets`. Dropped elements go to `tmp_outputs/`. |
| `--target_families` / `--non_target_families` | none           | With `--overlap targets`: comma-separated families to keep, or to drop (`Retroviridae,Metaviridae`). Only one of the two.            |
| `--flank`                                     | `10000`        | Length of the flanking regions written to `.EEs.flanks.fa` (`-fl`).                                                                  |
| `--removetmp`                                 | `false`        | Do not publish `tmp_files/`.                                                                                                         |
| `--eefinder_debug`                            | `false`        | Pass `--debug` to every EEfinder command.                                                                                            |

```yaml title="targets.yml"
step: screening
input: results/prepare_inputs/samplesheet.csv
outdir: results_flavi
overlap: targets
target_families: "Flaviviridae,Rhabdoviridae"
clean_masked: true
```

## Running the pipeline

The pipeline runs in two steps:

```bash
nextflow run nf-core/evefinder -profile docker -params-file prepare.yml
nextflow run nf-core/evefinder -profile docker --step screening --input ./results/prepare_inputs/samplesheet.csv --outdir ./results
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/running/run-pipelines#configuring-pipelines), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/evefinder -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
step: screening
input: './results/prepare_inputs/samplesheet.csv'
outdir: './results/'
search_mode: fast
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/evefinder
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/evefinder releases page](https://github.com/nf-core/evefinder/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow `24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) and [customise process resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
