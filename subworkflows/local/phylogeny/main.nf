//
// Genome tree, one leaf per sample: mashtree
//

include { RENAME_GENOME } from '../../../modules/local/rename_genome/main'
include { MASHTREE      } from '../../../modules/nf-core/mashtree/main'

workflow PHYLOGENY {

    take:
    ch_genomes // channel: [ meta, genome ], every genome of the samplesheet

    main:
    // A tree needs at least 3 leaves
    def ch_enough = ch_genomes
        .toList()
        .filter { genomes ->
            if (genomes.size() < 3) {
                log.warn("Phylogeny skipped: ${genomes.size()} genome(s), a tree needs at least 3")
            }
            genomes.size() >= 3
        }
        .flatMap()

    // mashtree names a leaf after the genome's file
    RENAME_GENOME(ch_enough)
    MASHTREE(RENAME_GENOME.out.genome.map { _meta, genome -> genome }.collect().map { genomes -> [[id: 'genomes'], genomes] })

    emit:
    tree = MASHTREE.out.tree.map { _meta, tree -> tree } // channel: path(Newick), empty with fewer than 3 genomes
}
