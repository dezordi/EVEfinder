process EEFINDER_POSTPROCESS {
    tag "${meta.id}"
    label 'process_single'

    // Local EEfinder 2.0.0 build (DIAMOND exit-status fix), not on Docker Hub yet
    container "docker.io/dezordi/eefinder@sha256:75366bb63e4672daa6839ba4caa8224dd5472e69b9d1b29d8f65a14aa15e5916"

    input:
    tuple val(meta), path(ee_elements), path(ee_elements_tax), path(taxonomy_signature)

    output:
    tuple val(meta), path("${prefix}.elements.resolved.fa")            , emit: fasta
    tuple val(meta), path("${prefix}.elements.resolved.tax.tsv")       , emit: tax
    tuple val(meta), path("${prefix}.elements.gff3")                   , emit: gff3
    tuple val(meta), path("${prefix}.elements.faa")                    , emit: faa
    tuple val(meta), path("${prefix}.elements.cleaned.{fa,tax.tsv,gff3}"), emit: cleaned, optional: true
    tuple val(meta), path("tmp_outputs/*")                             , emit: removed, optional: true
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening postprocess \\
        --ee-elements ${ee_elements} \\
        --ee-elements-tax ${ee_elements_tax} \\
        --taxonomy-signature ${taxonomy_signature} \\
        -od . \\
        -pr ${prefix} \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.elements.resolved.fa ${prefix}.elements.resolved.tax.tsv ${prefix}.elements.gff3 ${prefix}.elements.faa
    """
}
