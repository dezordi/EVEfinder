// Swarm plot of a genome's elements: family against length, coloured by protein
process EE_SWARMPLOT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "community.wave.seqera.io/library/python_pandas_plotly_seaborn_pruned:7298f08c05d82da0"

    input:
    tuple val(meta), path(elements)

    output:
    tuple val(meta), path("${prefix}.png"), path("${prefix}.svg"), emit: plots
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/Python //'"), topic: versions, emit: versions_python
    tuple val("${task.process}"), val('seaborn'), eval("python -c 'import seaborn; print(seaborn.__version__)'"), topic: versions, emit: versions_seaborn
    tuple val("${task.process}"), val('matplotlib'), eval("python -c 'import matplotlib; print(matplotlib.__version__)'"), topic: versions, emit: versions_matplotlib
    tuple val("${task.process}"), val('pandas'), eval("python -c 'import pandas; print(pandas.__version__)'"), topic: versions, emit: versions_pandas

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}.swarm"
    """
    export MPLCONFIGDIR=\$PWD/.matplotlib
    ee_swarmplot.py \\
        --elements ${elements} \\
        --sample '${meta.id}' \\
        --prefix '${prefix}' \\
        ${args}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}.swarm"
    """
    touch ${prefix}.png ${prefix}.svg
    """
}
