//
// Cluster each genome's elements with cd-hit-est or vclust
//

include { CDHIT_CDHITEST   } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { VCLUST_PREFILTER } from '../../../modules/nf-core/vclust/prefilter/main'
include { VCLUST_ALIGN     } from '../../../modules/nf-core/vclust/align/main'
include { VCLUST_CLUSTER   } from '../../../modules/nf-core/vclust/cluster/main'
include { EE_CLUSTER_TABLE } from '../../../modules/local/ee_cluster_table/main'

workflow EE_CLUSTERING {

    take:
    ch_elements      // channel: [ meta, EEs.fa ], one per genome with elements
    cluster_tool     // string : 'cdhit' or 'vclust'
    cluster_identity // number : minimum identity (cd-hit-est -c, vclust --ani)

    main:
    def ch_clusters = channel.empty()
    if (cluster_tool == 'vclust') {
        // vclust align fails on a single sequence
        def ch_vclust = ch_elements.branch { _meta, fasta ->
            single: fasta.countFasta() == 1
            several: true
        }
        VCLUST_PREFILTER(ch_vclust.several)
        // Pair the inputs by meta, not by arrival order
        def ch_align_input = ch_vclust.several.join(VCLUST_PREFILTER.out.txt).multiMap { meta, fasta, filter ->
            fasta: [meta, fasta]
            filter: [meta, filter]
        }
        VCLUST_ALIGN(ch_align_input.fasta, ch_align_input.filter, false)
        def ch_cluster_input = VCLUST_ALIGN.out.tsv.join(VCLUST_ALIGN.out.ids).multiMap { meta, tsv, ids ->
            tsv: [meta, tsv]
            ids: [meta, ids]
        }
        VCLUST_CLUSTER(ch_cluster_input.tsv, ch_cluster_input.ids, 'ani', 0, 0, cluster_identity)
        ch_clusters = ch_vclust.several
            .join(VCLUST_CLUSTER.out.clusters)
            .join(VCLUST_ALIGN.out.tsv)
            .mix(ch_vclust.single.map { meta, fasta -> [meta, fasta, [], []] })
    }
    else {
        CDHIT_CDHITEST(ch_elements)
        ch_clusters = ch_elements.join(CDHIT_CDHITEST.out.clusters).map { meta, fasta, clstr -> [meta, fasta, clstr, []] }
    }
    EE_CLUSTER_TABLE(ch_clusters)

    emit:
    table = EE_CLUSTER_TABLE.out.tsv   // channel: [ meta, cluster table TSV ]
    fasta = EE_CLUSTER_TABLE.out.fasta // channel: [ meta, representatives FASTA ]
}
