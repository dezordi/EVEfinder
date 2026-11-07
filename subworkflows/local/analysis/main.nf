//
// Genome phylogeny and plots of a finished screening
//

include { PHYLOGENY } from '../phylogeny'
include { PLOTS     } from '../plots'

workflow ANALYSIS {

    take:
    ch_samplesheet   // channel: [ meta, genome, baits, db_fasta, db_metadata ]; meta.species optional
    screening_outdir // string : the --outdir of the screening run
    skip_phylogeny   // boolean
    phylogeny_tree   // string : Newick tree used instead of mashtree, or null
    skip_plots       // boolean

    main:
    def screening = file("${screening_outdir}/screening", checkIfExists: true)
    def skipped_file = file("${screening}/skipped_genomes.tsv")
    def skipped = skipped_file.exists()
        ? skipped_file.readLines().drop(1).collect { line -> line.tokenize('\t')[0] }
        : []

    // [ meta, genome, EEs.fa, EEs.tax.tsv ], [] for a genome without elements;
    // meta.label names the genome in the tree and the plots: <Species_name>_<sample>
    def ch_genomes = ch_samplesheet.map { sample_meta, genome, _baits, _db, _mt ->
        def meta = sample_meta + [label: sample_meta.species ? "${sample_meta.species.replaceAll(/[^A-Za-z0-9.-]+/, '_')}_${sample_meta.id}" : sample_meta.id]
        def fasta = file("${screening}/${meta.id}/${meta.id}.EEs.fa")
        def taxonomy = file("${screening}/${meta.id}/${meta.id}.EEs.tax.tsv")
        if (fasta.exists() && taxonomy.exists()) {
            return [meta, genome, fasta, taxonomy]
        }
        if (meta.id in skipped) {
            return [meta, genome, [], []]
        }
        error("No screening results for '${meta.id}' in ${screening}: run --step screening on this samplesheet first, with --outdir ${screening_outdir}")
    }

    def ch_tree = channel.empty()
    if (!skip_phylogeny && phylogeny_tree) {
        ch_tree = channel.value(file(phylogeny_tree, checkIfExists: true))
    }
    else if (!skip_phylogeny) {
        PHYLOGENY(ch_genomes.map { meta, genome, _fasta, _taxonomy -> [meta, genome] })
        ch_tree = PHYLOGENY.out.tree
    }
    if (!skip_plots) {
        PLOTS(ch_genomes, ch_tree)
    }

    emit:
    genomes = ch_genomes // channel: [ meta, genome, EEs.fa or [], EEs.tax.tsv or [] ]
    tree    = ch_tree    // channel: path(Newick), empty when skipped
}
