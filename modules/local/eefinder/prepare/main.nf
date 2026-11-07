include { searchTools; versionCommands } from '../functions'

// Validate a database + baits set and index the FASTAs staged without an index
process EEFINDER_PREPARE {
    tag "${meta.id}"
    label 'process_low'

    container "docker.io/dezordi/eefinder:2.0.0-dev"

    input:
    tuple val(meta), path(database), path(dbmetadata), path(baits), path(database_index), path(baits_index)

    output:
    // includeInputs: a reused index is an input, a built one a new file
    tuple val(meta), path("${database}.*", includeInputs: true), emit: database_index
    tuple val(meta), path("${baits}.*", includeInputs: true)   , emit: baits_index
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('blast'), eval("${tool_versions['blast']}"), topic: versions, emit: versions_blast
    tuple val("${task.process}"), val('diamond'), eval("${tool_versions['diamond']}"), topic: versions, emit: versions_diamond
    tuple val("${task.process}"), val('mmseqs2'), eval("${tool_versions['mmseqs2']}"), topic: versions, emit: versions_mmseqs2

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    tool_versions = versionCommands(searchTools(args))
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder screening prepare \\
        -db ${database} \\
        -mt ${dbmetadata} \\
        -bt ${baits} \\
        -od . \\
        -pr ${prefix} \\
        -p ${task.cpus} \\
        ${args}
    """

    stub:
    tool_versions = versionCommands(searchTools(task.ext.args))
    """
    touch ${database}.pin ${baits}.pin
    """
}
