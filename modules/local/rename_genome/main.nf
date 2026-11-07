// Link a genome as <label>.fa[.gz] (meta.label, or the sample), so tree leaves are named after it
process RENAME_GENOME {
    tag "${meta.id}"
    label 'process_single'

    container "quay.io/biocontainers/python:3.12"

    input:
    tuple val(meta), path(genome, stageAs: 'input/*')

    output:
    tuple val(meta), path("${name}"), emit: genome

    when:
    task.ext.when == null || task.ext.when

    script:
    name = "${meta.label ?: meta.id}.fa${genome.name.endsWith('.gz') ? '.gz' : ''}"
    """
    ln -s ${genome} ${name}
    """

    stub:
    name = "${meta.label ?: meta.id}.fa${genome.name.endsWith('.gz') ? '.gz' : ''}"
    """
    touch ${name}
    """
}
