// Tables the plots read (elements.tsv, genomes.tsv) and the Krona inputs
process EE_PLOT_DATA {
    tag "plots"
    label 'process_single'

    container "quay.io/biocontainers/python:3.12"

    input:
    // every sample, and the EEs.{fa,tax.tsv} of those with elements
    tuple val(samples), path(fastas, stageAs: 'eefinder/*'), path(taxonomies, stageAs: 'eefinder/*')

    output:
    path "elements.tsv", emit: elements
    path "genomes.tsv" , emit: genomes
    path "krona/*"     , emit: krona, type: 'dir', optional: true
    tuple val("${task.process}"), val('python'), eval("python3 --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    ee_plot_data.py \\
        --samples ${samples.collect { sample -> "'${sample}'" }.join(' ')} \\
        --dir eefinder
    """

    stub:
    """
    touch elements.tsv genomes.tsv
    """
}
