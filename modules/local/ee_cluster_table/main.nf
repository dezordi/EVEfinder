// Standard cluster table and representatives FASTA, from cd-hit-est (`-p 1`) or vclust
process EE_CLUSTER_TABLE {
    tag "${meta.id}"
    label 'process_single'

    container "quay.io/biocontainers/python:3.12"

    input:
    // align: [] for cd-hit-est; clusters and align []: one element, its own cluster
    tuple val(meta), path(elements), path(clusters), path(align)

    output:
    tuple val(meta), path("${prefix}.tsv"), emit: tsv
    tuple val(meta), path("${prefix}.fa") , emit: fasta
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}.EEs.clusters"
    def clusters_arg = clusters ? "--clusters ${clusters}" : ''
    def align_arg = align ? "--align ${align}" : ''
    """
    ee_cluster_table.py \\
        --elements ${elements} \\
        ${clusters_arg} \\
        ${align_arg} \\
        --sample ${meta.id} \\
        --prefix ${prefix}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}.EEs.clusters"
    """
    touch ${prefix}.tsv ${prefix}.fa
    """
}
