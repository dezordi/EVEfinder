include { searchTools; versionCommands } from '../functions'

process EEFINDER_ALIGN {
    tag "${meta.id}"
    label 'process_high'

    container "docker.io/dezordi/eefinder:2.0.0-dev"

    input:
    tuple val(meta), path(genome), path(database), path(database_index)

    output:
    tuple val(meta), path("${prefix}.ee_candidates.fa"), path("${prefix}.ee_hits.filtered.tsv"), emit: candidates, optional: true
    // with -tm gv/rv/gv-rv, the proteins predicted on the genome, reused by EEFINDER_FILTER
    tuple val(meta), path("${prefix}.predicted_proteins.{faa,coords.tsv}")                     , emit: proteins  , optional: true
    tuple val(meta), path("${prefix}.ee_hits.tsv"), path("${prefix}.ee_candidates.bed")         , emit: intermediates, optional: true
    tuple val(meta), env('VIRAL_HITS')                                                           , emit: viral_hits
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('bedtools'), eval("bedtools --version | sed 's/.* v//'"), topic: versions, emit: versions_bedtools
    tuple val("${task.process}"), val('blast'), eval("${tool_versions['blast']}"), topic: versions, emit: versions_blast
    tuple val("${task.process}"), val('diamond'), eval("${tool_versions['diamond']}"), topic: versions, emit: versions_diamond
    tuple val("${task.process}"), val('mmseqs2'), eval("${tool_versions['mmseqs2']}"), topic: versions, emit: versions_mmseqs2
    tuple val("${task.process}"), val('pyrodigal-gv'), eval("${tool_versions['pyrodigal-gv']}"), topic: versions, emit: versions_pyrodigal_gv
    tuple val("${task.process}"), val('pyrodigal-rv'), eval("${tool_versions['pyrodigal-rv']}"), topic: versions, emit: versions_pyrodigal_rv
    tuple val("${task.process}"), val('cd-hit'), eval("${tool_versions['cd-hit']}"), topic: versions, emit: versions_cd_hit

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    tool_versions = versionCommands(searchTools(args))
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    status=0
    eefinder screening align \\
        --genome ${genome} \\
        -db ${database} \\
        -od . \\
        -pr ${prefix} \\
        -p ${task.cpus} \\
        ${args} || status=\$?

    VIRAL_HITS=found
    if [ \$status -ne 0 ]; then
        # EEfinder fails on an empty hit table. A failed search raises before
        # the table is written, so an empty one is a genome without viral hits
        [ -f ${prefix}.ee_hits.tsv ] && [ ! -s ${prefix}.ee_hits.tsv ] || exit \$status
        VIRAL_HITS=none
    fi
    """

    stub:
    tool_versions = versionCommands(searchTools(task.ext.args))
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.ee_candidates.fa ${prefix}.ee_hits.filtered.tsv ${prefix}.ee_hits.tsv ${prefix}.ee_candidates.bed
    VIRAL_HITS=found
    """
}
