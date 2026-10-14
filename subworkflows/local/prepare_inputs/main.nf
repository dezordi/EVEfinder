//
// Download the genomes, host baits and viral database, and write the screening samplesheet
//

include { WGET as WGET_NCBI                              } from '../../../modules/nf-core/wget/main'
include { WGET as WGET_ENA_FASTA                         } from '../../../modules/nf-core/wget/main'
include { WGET as WGET_ENA_XML                           } from '../../../modules/nf-core/wget/main'
include { UNZIP                                          } from '../../../modules/nf-core/unzip/main'
include { SEQKIT_REPLACE                                 } from '../../../modules/nf-core/seqkit/replace/main'
include { RESOLVE_HOST_TAXON                             } from '../../../modules/local/resolve_host_taxon/main'
include { EEFINDER_GETDATABASES as EEFINDER_GETDATABASES_HOST  } from '../../../modules/local/eefinder/getdatabases/main'
include { EEFINDER_GETDATABASES as EEFINDER_GETDATABASES_VIRUS } from '../../../modules/local/eefinder/getdatabases/main'

workflow PREPARE_INPUTS {

    take:
    ch_samplesheet        // channel: [ meta ]  meta.id = genome accession, meta.virus_taxid (optional)
    genome_source         // string : 'ncbi' or 'ena'
    download_virus_db     // boolean: download the viral database with `eefinder get-databases virus`
    virus_db_release_date // string : YYYY-MM-DD passed as --released-before (default: today)
    virus_db_fasta        // string : local viral protein FASTA (used when not downloading)
    virus_db_metadata     // string : local viral metadata CSV (used when not downloading)
    host_refseq           // boolean: host baits from RefSeq assemblies only
    host_max_rank         // string : highest rank searched for an annotated host relative
    outdir                // string : pipeline output directory

    main:
    def ncbi_api = 'https://api.ncbi.nlm.nih.gov/datasets/v2/genome/accession'
    def ena_api  = 'https://www.ebi.ac.uk/ena/browser/api'
    // The samplesheet points to the published copies
    def published = "${file(outdir).toUriString()}/prepare_inputs"

    // Genomes: [ meta + [taxid], genome, published path ]
    def ch_genomes
    if (genome_source == 'ena') {
        // URLs are quoted: the WGET module pastes them unquoted into the shell
        WGET_ENA_FASTA(ch_samplesheet.map { meta -> [meta, "'${ena_api}/fasta/${meta.id}?download=true&gzip=true'", 'fasta.gz'] })
        WGET_ENA_XML(ch_samplesheet.map { meta -> [meta, "'${ena_api}/xml/${meta.id}'", 'xml'] })
        // EEfinder cannot handle the `|` of ENA headers (`ENA|<acc>|<acc.version>`)
        SEQKIT_REPLACE(WGET_ENA_FASTA.out.outfile, 'fasta')
        ch_genomes = SEQKIT_REPLACE.out.fastx
            .join(WGET_ENA_XML.out.outfile)
            .map { meta, fasta, xml ->
                def taxid = (xml.text =~ /<TAXON_ID>(\d+)<\/TAXON_ID>/).findAll()
                if (!taxid) {
                    error("No TAXON_ID found in the ENA record of ${meta.id}")
                }
                [meta + [taxid: taxid[0][1]], fasta, "${published}/genomes/${fasta.name}"]
            }
    }
    else {
        WGET_NCBI(ch_samplesheet.map { meta -> [meta, "'${ncbi_api}/${meta.id}/download?include_annotation_type=GENOME_FASTA&include_annotation_type=GENOME_GFF'", 'zip'] })
        UNZIP(WGET_NCBI.out.outfile)
        ch_genomes = UNZIP.out.unzipped_archive
            .map { meta, dir ->
                def fasta = files("${dir}/ncbi_dataset/data/*/*.fna")
                if (!fasta) {
                    error("NCBI returned no genome FASTA for ${meta.id}: check the accession")
                }
                def report = new groovy.json.JsonSlurper().parseText(dir.resolve('ncbi_dataset/data/assembly_data_report.jsonl').readLines()[0])
                [meta + [taxid: report.organism.taxId.toString()], fasta[0], "${published}/genomes/${dir.name}/${dir.relativize(fasta[0])}"]
            }
    }

    // Host baits, from the closest taxon with an annotated assembly: [ host taxid, published path ]
    RESOLVE_HOST_TAXON(
        ch_genomes
            .map { meta, _genome, _path -> meta.taxid }
            .unique()
            .map { taxid -> [taxid, host_refseq, host_max_rank] }
    )
    def ch_host_taxon = RESOLVE_HOST_TAXON.out.taxon // [ host taxid, baits taxid, rank ]
    ch_host_taxon
        .filter { _taxid, _baits_taxid, rank -> rank != 'requested' }
        .subscribe { taxid, baits_taxid, rank -> log.warn("Host taxon ${taxid} has no annotated assembly: using the ${rank} ${baits_taxid} for its baits") }
    ch_host_taxon
        .map { taxid, baits_taxid, rank -> "${taxid}\t${baits_taxid}\t${rank}" }
        .collectFile(name: 'host_taxa.tsv', storeDir: "${outdir}/prepare_inputs/host_baits", seed: 'host_taxid\tbaits_taxid\tbaits_rank', newLine: true, sort: true)

    EEFINDER_GETDATABASES_HOST(
        ch_host_taxon
            .map { _taxid, baits_taxid, _rank -> baits_taxid }
            .unique()
            .map { taxid -> [[id: "host_${taxid}", taxid: taxid], 'host', taxid] }
    )
    def ch_baits = ch_host_taxon
        .map { taxid, baits_taxid, _rank -> [baits_taxid, taxid] }
        .combine(EEFINDER_GETDATABASES_HOST.out.fasta.map { meta, fasta -> [meta.taxid, fasta] }, by: 0)
        .map { _baits_taxid, taxid, fasta -> [taxid, "${published}/host_baits/${fasta.name}"] }

    // Viral database, one per `virus_taxid` ('' = EEfinder's default, or a local database):
    // [ virus_taxid, published fasta, published metadata ]
    def ch_virus_db
    if (download_virus_db) {
        def release_date = virus_db_release_date ?: new Date().format('yyyy-MM-dd')
        log.info "Viral database: data released on or before ${release_date}"
        EEFINDER_GETDATABASES_VIRUS(
            ch_samplesheet
                .map { meta -> meta.virus_taxid ? meta.virus_taxid.toString() : '' }
                .unique()
                .map { taxid -> [[id: taxid ? "virus_${taxid}" : 'virus', taxid: taxid, released_before: release_date], 'virus', taxid] }
        )
        ch_virus_db = EEFINDER_GETDATABASES_VIRUS.out.fasta
            .join(EEFINDER_GETDATABASES_VIRUS.out.metadata)
            .map { meta, fasta, csv -> [meta.taxid, "${published}/virus_db/${fasta.name}", "${published}/virus_db/${csv.name}"] }
    }
    else {
        ch_virus_db = channel.of(['', file(virus_db_fasta, checkIfExists: true).toUriString(), file(virus_db_metadata, checkIfExists: true).toUriString()])
    }

    // Samplesheet for `--step screening`
    def ch_samplesheet_out = ch_genomes
        .map { meta, _genome, genome_path -> [meta.taxid, meta, genome_path] }
        .combine(ch_baits, by: 0)
        .map { _taxid, meta, genome_path, baits_path ->
            [download_virus_db && meta.virus_taxid ? meta.virus_taxid.toString() : '', meta, genome_path, baits_path]
        }
        .combine(ch_virus_db, by: 0)
        .map { _key, meta, genome_path, baits_path, db_fasta, db_metadata ->
            [meta.id, meta.taxid, genome_path, baits_path, db_fasta, db_metadata].join(',')
        }
        .collectFile(
            name: 'samplesheet.csv',
            storeDir: "${outdir}/prepare_inputs",
            seed: 'sample,taxid,genome,baits,db_fasta,db_metadata',
            newLine: true,
            sort: true,
        )

    emit:
    samplesheet = ch_samplesheet_out // channel: path(samplesheet.csv)
    genomes     = ch_genomes         // channel: [ meta, genome, published path ]
}
