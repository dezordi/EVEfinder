include { searchTools; versionCommands } from '../functions'

process EEFINDER_GETDATABASES {
    tag "${meta.id}"
    label 'process_low'

    container "docker.io/dezordi/eefinder:2.0.0-dev"

    input:
    tuple val(meta), val(target), val(taxon)

    output:
    tuple val(meta), path("${prefix}.fa")                         , emit: fasta
    tuple val(meta), path("${prefix}.fa.*")                       , emit: index
    tuple val(meta), path("${prefix}.csv")                        , emit: metadata, optional: true
    tuple val(meta), path("${prefix}.{tracking.tsv,clstr,log}")   , emit: logs    , optional: true
    tuple val("${task.process}"), val('eefinder'), eval("eefinder --version | sed 's/.*version //'"), topic: versions, emit: versions_eefinder
    tuple val("${task.process}"), val('datasets'), eval("datasets --version | sed 's/.*: //'"), topic: versions, emit: versions_datasets
    tuple val("${task.process}"), val('cd-hit'), eval("${tool_versions['cd-hit']}"), topic: versions, emit: versions_cd_hit
    tuple val("${task.process}"), val('blast'), eval("${tool_versions['blast']}"), topic: versions, emit: versions_blast
    tuple val("${task.process}"), val('diamond'), eval("${tool_versions['diamond']}"), topic: versions, emit: versions_diamond
    tuple val("${task.process}"), val('mmseqs2'), eval("${tool_versions['mmseqs2']}"), topic: versions, emit: versions_mmseqs2

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    tool_versions = versionCommands(searchTools(args) + (args.contains('--no-cluster') ? [] : ['cd-hit']))
    def taxon_arg = taxon ? "-tx '${taxon}'" : ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    eefinder get-databases ${target} \\
        ${taxon_arg} \\
        -od . \\
        -pr ${prefix} \\
        -p ${task.cpus} \\
        ${args}
    """

    stub:
    def args = task.ext.args ?: ''
    tool_versions = versionCommands(searchTools(args) + (args.contains('--no-cluster') ? [] : ['cd-hit']))
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fa ${prefix}.fa.pin ${prefix}.log
    ${target == 'host' ? '' : "touch ${prefix}.csv"}
    """
}
