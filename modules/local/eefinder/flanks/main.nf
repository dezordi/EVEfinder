process EEFINDER_FLANKS {
    tag "${meta.id}"
    label 'process_single'

    // Local EEfinder 2.0.0 build (DIAMOND exit-status fix), not on Docker Hub yet
    container "docker.io/dezordi/eefinder@sha256:75366bb63e4672daa6839ba4caa8224dd5472e69b9d1b29d8f65a14aa15e5916"

    input:
    tuple val(meta), path(ee_elements), path(genome)

    output:
    tuple val(meta), path("${prefix}.flanks.fa")                                                     , emit: flanks
    tuple val(meta), path("${prefix}.{cleaned_genome.lengths.tsv,flanks.bed,flanks.slop.bed}")      , emit: intermediates
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('bedtools'), eval("bedtools --version | sed 's/.* v//'"), topic: versions, emit: versions_bedtools

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening flanks \\
        --ee-elements ${ee_elements} \\
        --genome ${genome} \\
        -od . \\
        -pr ${prefix} \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.flanks.fa ${prefix}.cleaned_genome.lengths.tsv ${prefix}.flanks.bed ${prefix}.flanks.slop.bed
    """
}
