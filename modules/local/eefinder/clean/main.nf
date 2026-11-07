process EEFINDER_CLEAN {
    tag "${meta.id}"
    label 'process_single'

    container "docker.io/dezordi/eefinder:2.0.0-dev"

    input:
    tuple val(meta), path(genome)

    output:
    tuple val(meta), path("${prefix}.cleaned_genome.fa"), emit: genome
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening clean \\
        -in ${genome} \\
        -od . \\
        -pr ${prefix} \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.cleaned_genome.fa
    """
}
