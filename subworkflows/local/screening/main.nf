//
// Run each `eefinder screening` stage as its own process, per genome
//

include { EEFINDER_PREPARE     } from '../../../modules/local/eefinder/prepare/main'
include { EEFINDER_CLEAN       } from '../../../modules/local/eefinder/clean/main'
include { EEFINDER_ALIGN       } from '../../../modules/local/eefinder/align/main'
include { EEFINDER_FILTER      } from '../../../modules/local/eefinder/filter/main'
include { EEFINDER_TAXONOMY    } from '../../../modules/local/eefinder/taxonomy/main'
include { EEFINDER_MERGE       } from '../../../modules/local/eefinder/merge/main'
include { EEFINDER_POSTPROCESS } from '../../../modules/local/eefinder/postprocess/main'
include { EEFINDER_FLANKS      } from '../../../modules/local/eefinder/flanks/main'
include { EE_CLUSTERING        } from '../ee_clustering'

// One key per database + baits set
def setKey(db, baits) {
    return "${db.toUriString()}|${baits.toUriString()}".toString()
}

// Search indexes written beside a local FASTA by `get-databases`
def indexBeside(fasta) {
    return fasta.toUri().scheme == 'file' ? files("${fasta}.*") : []
}

workflow SCREENING {

    take:
    ch_samplesheet   // channel: [ meta, genome, baits, db_fasta, db_metadata ]
    outdir           // string : pipeline output directory
    skip_clustering  // boolean
    cluster_tool     // string : 'cdhit' or 'vclust'
    cluster_identity // number

    main:
    def ch_baits    = ch_samplesheet.map { meta, _genome, baits, _db, _mt -> [meta, baits] }
    def ch_metadata = ch_samplesheet.map { meta, _genome, _baits, _db, mt -> [meta, mt] }

    // Once per set: reuses the indexes beside its FASTAs, builds the missing ones.
    // A FASTA without index shared by several sets is indexed once per set.
    EEFINDER_PREPARE(
        ch_samplesheet
            .map { _meta, _genome, baits, db, mt -> [db, mt, baits] }
            .unique()
            .map { db, mt, baits ->
                [[id: "${db.baseName}.${baits.baseName}", key: setKey(db, baits)], db, mt, baits, indexBeside(db), indexBeside(baits)]
            }
    )

    EEFINDER_CLEAN(ch_samplesheet.map { meta, genome, _baits, _db, _mt -> [meta, genome] })

    def ch_sets = ch_samplesheet.map { meta, _genome, baits, db, _mt -> [meta, setKey(db, baits)] }
    EEFINDER_ALIGN(
        EEFINDER_CLEAN.out.genome
            .join(ch_samplesheet.map { meta, _genome, _baits, db, _mt -> [meta, db] })
            .join(ch_sets)
            .map { meta, genome, db, set_key -> [set_key, meta, genome, db] }
            .combine(EEFINDER_PREPARE.out.database_index.map { meta, index -> [meta.key, index] }, by: 0)
            .map { _set_key, meta, genome, db, index -> [meta, genome, db, index] }
    )

    // Genomes without viral hits have no candidates and drop out of the joins below
    def ch_no_hits = EEFINDER_ALIGN.out.viral_hits
        .filter { _meta, hits -> hits == 'none' }
        .map { meta, _hits -> [meta.id, 'no viral hits'] }

    EEFINDER_FILTER(
        EEFINDER_ALIGN.out.candidates
            .join(ch_baits)
            .join(ch_sets)
            .map { meta, candidates, hits, baits, set_key -> [set_key, meta, candidates, hits, baits] }
            .combine(EEFINDER_PREPARE.out.baits_index.map { meta, index -> [meta.key, index] }, by: 0)
            .map { _set_key, meta, candidates, hits, baits, index -> [meta, candidates, hits, baits, index] }
    )

    // Header only: every candidate matched a host bait better
    def ch_validated = EEFINDER_FILTER.out.validated.branch { _meta, hits ->
        none: hits.countLines() < 2
        found: true
    }

    def ch_skipped = ch_no_hits.mix(
        ch_validated.none.map { meta, _hits -> [meta.id, 'every viral hit matches a host bait better'] }
    )
    ch_skipped.subscribe { id, reason -> log.warn("${id}: ${reason}, left out of the rest of the screening") }
    ch_skipped
        .map { id, reason -> "${id}\t${reason}" }
        .collectFile(name: 'skipped_genomes.tsv', storeDir: "${outdir}/screening", seed: 'sample\treason', newLine: true, sort: true)

    EEFINDER_TAXONOMY(ch_validated.found.join(ch_metadata))

    EEFINDER_MERGE(EEFINDER_TAXONOMY.out.signature.join(EEFINDER_CLEAN.out.genome))

    EEFINDER_POSTPROCESS(EEFINDER_MERGE.out.elements.join(EEFINDER_TAXONOMY.out.signature))

    EEFINDER_FLANKS(EEFINDER_POSTPROCESS.out.fasta.join(EEFINDER_CLEAN.out.genome))

    if (!skip_clustering) {
        EE_CLUSTERING(EEFINDER_POSTPROCESS.out.fasta, cluster_tool, cluster_identity)
    }

    emit:
    fasta  = EEFINDER_POSTPROCESS.out.fasta // channel: [ meta, PREFIX.elements.resolved.fa ]
    tax    = EEFINDER_POSTPROCESS.out.tax   // channel: [ meta, PREFIX.elements.resolved.tax.tsv ]
    gff3   = EEFINDER_POSTPROCESS.out.gff3  // channel: [ meta, PREFIX.elements.gff3 ]
    faa    = EEFINDER_POSTPROCESS.out.faa   // channel: [ meta, PREFIX.elements.faa ]
    flanks = EEFINDER_FLANKS.out.flanks     // channel: [ meta, PREFIX.flanks.fa ]
}
