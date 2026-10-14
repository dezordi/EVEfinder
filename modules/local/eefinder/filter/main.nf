include { searchTools; versionCommands } from '../functions'

process EEFINDER_FILTER {
    tag "${meta.id}"
    label 'process_medium'

    // Local EEfinder 2.0.0 build (DIAMOND exit-status fix), not on Docker Hub yet
    container "docker.io/dezordi/eefinder@sha256:75366bb63e4672daa6839ba4caa8224dd5472e69b9d1b29d8f65a14aa15e5916"

    input:
    tuple val(meta), path(candidates), path(ee_hits_filtered), path(baits), path(baits_index)

    output:
    tuple val(meta), path("${prefix}.ee_hits.validated.tsv")                                 , emit: validated
    tuple val(meta), path("${prefix}.host_hits.tsv"), path("${prefix}.host_hits.filtered.tsv"), emit: intermediates
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('blast'), eval("${tool_versions['blast']}"), topic: versions, emit: versions_blast
    tuple val("${task.process}"), val('diamond'), eval("${tool_versions['diamond']}"), topic: versions, emit: versions_diamond
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
    eefinder screening filter \\
        --candidates ${candidates} \\
        --ee-hits-filtered ${ee_hits_filtered} \\
        -bt ${baits} \\
        -od . \\
        -pr ${prefix} \\
        -p ${task.cpus} \\
        ${args}
    """

    stub:
    tool_versions = versionCommands(searchTools(task.ext.args))
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.ee_hits.validated.tsv ${prefix}.host_hits.tsv ${prefix}.host_hits.filtered.tsv
    """
}
