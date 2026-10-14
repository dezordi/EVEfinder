// Interactive HTML: genome tree beside a heatmap of elements per taxon
process EE_PHYLO_HEATMAP {
    tag "plots"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "community.wave.seqera.io/library/python_pandas_plotly_seaborn_pruned:7298f08c05d82da0"

    input:
    path elements
    path genomes
    path tree // [] without a tree

    output:
    path "phylogeny_heatmap.html", emit: html
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/Python //'"), topic: versions, emit: versions_python
    tuple val("${task.process}"), val('plotly'), eval("python -c 'import plotly; print(plotly.__version__)'"), topic: versions, emit: versions_plotly
    tuple val("${task.process}"), val('biopython'), eval("python -c 'import Bio; print(Bio.__version__)'"), topic: versions, emit: versions_biopython

    when:
    task.ext.when == null || task.ext.when

    script:
    def tree_arg = tree ? "--tree ${tree}" : ''
    """
    ee_phylo_heatmap.py \\
        --elements ${elements} \\
        --genomes ${genomes} \\
        ${tree_arg} \\
        --output phylogeny_heatmap.html
    """

    stub:
    """
    touch phylogeny_heatmap.html
    """
}
