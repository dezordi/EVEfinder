process EEFINDER_TAXONOMY {
    tag "${meta.id}"
    label 'process_single'

    container "docker.io/dezordi/eefinder:2.0.0-dev"

    input:
    tuple val(meta), path(ee_hits_validated), path(dbmetadata)

    output:
    tuple val(meta), path("${prefix}.taxonomy_signature.csv"), emit: signature
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening taxonomy \\
        --ee-hits-validated ${ee_hits_validated} \\
        -mt ${dbmetadata} \\
        -od . \\
        -pr ${prefix} \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.taxonomy_signature.csv
    """
}
