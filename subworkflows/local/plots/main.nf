//
// Tree + heatmap of all genomes, Krona and swarm plot per genome with elements
//

include { EE_PLOT_DATA       } from '../../../modules/local/ee_plot_data/main'
include { EE_PHYLO_HEATMAP   } from '../../../modules/local/ee_phylo_heatmap/main'
include { EE_SWARMPLOT       } from '../../../modules/local/ee_swarmplot/main'
include { KRONA_KTIMPORTTEXT } from '../../../modules/nf-core/krona/ktimporttext/main'

workflow PLOTS {

    take:
    ch_genomes // channel: [ meta, genome, EEs.fa or [], EEs.tax.tsv or [] ]
    ch_tree    // channel: path(Newick), empty without a tree

    main:
    def ch_data = ch_genomes
        .toList()
        .map { genomes ->
            [
                genomes.collect { meta, _genome, _fasta, _taxonomy -> meta.id },
                genomes.collect { _meta, _genome, fasta, _taxonomy -> fasta }.findAll(),
                genomes.collect { _meta, _genome, _fasta, taxonomy -> taxonomy }.findAll(),
            ]
        }
    EE_PLOT_DATA(ch_data)

    EE_PHYLO_HEATMAP(EE_PLOT_DATA.out.elements, EE_PLOT_DATA.out.genomes, ch_tree.ifEmpty([]))

    // One Krona dataset per file, all.txt first
    KRONA_KTIMPORTTEXT(
        EE_PLOT_DATA.out.krona.flatten().map { dir ->
            [[id: dir.name], dir.listFiles().toList().sort { file -> [file.name != 'all.txt', file.name] }]
        }
    )

    EE_SWARMPLOT(
        ch_genomes
            .filter { _meta, _genome, _fasta, taxonomy -> taxonomy }
            .combine(EE_PLOT_DATA.out.elements)
            .map { meta, _genome, _fasta, _taxonomy, elements -> [meta, elements] }
    )

    emit:
    elements = EE_PLOT_DATA.out.elements    // path: elements.tsv
    genomes  = EE_PLOT_DATA.out.genomes     // path: genomes.tsv
    heatmap  = EE_PHYLO_HEATMAP.out.html    // path: phylogeny_heatmap.html
    krona    = KRONA_KTIMPORTTEXT.out.html  // channel: [ meta, krona.html ]
    swarm    = EE_SWARMPLOT.out.plots       // channel: [ meta, swarm.png, swarm.svg ]
}
