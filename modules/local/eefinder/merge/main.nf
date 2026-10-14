process EEFINDER_MERGE {
    tag "${meta.id}"
    label 'process_single'

    // Local EEfinder 2.0.0 build (DIAMOND exit-status fix), not on Docker Hub yet
    container "docker.io/dezordi/eefinder@sha256:75366bb63e4672daa6839ba4caa8224dd5472e69b9d1b29d8f65a14aa15e5916"

    input:
    tuple val(meta), path(taxonomy_signature), path(genome)

    output:
    tuple val(meta), path("${prefix}.elements.fa"), path("${prefix}.elements.tax.tsv")  , emit: elements
    tuple val(meta), path("${prefix}.merge.{annotated,merged,elements}.bed")            , emit: intermediates
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('bedtools'), eval("bedtools --version | sed 's/.* v//'"), topic: versions, emit: versions_bedtools

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening merge \\
        --taxonomy-signature ${taxonomy_signature} \\
        --genome ${genome} \\
        -od . \\
        -pr ${prefix} \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.elements.fa ${prefix}.elements.tax.tsv
    touch ${prefix}.merge.annotated.bed ${prefix}.merge.merged.bed ${prefix}.merge.elements.bed
    """
}
