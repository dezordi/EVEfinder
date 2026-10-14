//
// Subworkflow with functionality specific to the nf-core/evefinder pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { paramsHelp                } from 'plugin/nf-schema'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //

    def before_text = ""
    def after_text = ""
    before_text = """
-\033[2m----------------------------------------------------\033[0m-
                                        \033[0;32m,--.\033[0;30m/\033[0;32m,-.\033[0m
\033[0;34m        ___     __   __   __   ___     \033[0;32m/,-._.--~\'\033[0m
\033[0;34m  |\\ | |__  __ /  ` /  \\ |__) |__         \033[0;33m}  {\033[0m
\033[0;34m  | \\| |       \\__, \\__/ |  \\ |___     \033[0;32m\\`-._,-`-,\033[0m
                                        \033[0;32m`._,._,\'\033[0m
\033[0;35m  nf-core/evefinder ${workflow.manifest.version}\033[0m
-\033[2m----------------------------------------------------\033[0m-
"""
    after_text = """${workflow.manifest.doi ? "\n* The pipeline\n" : ""}${workflow.manifest.doi.tokenize(",").collect { doi -> "    https://doi.org/${doi.trim().replace('https://doi.org/','')}"}.join("\n")}${workflow.manifest.doi ? "\n" : ""}
* The nf-core framework
    https://doi.org/10.1038/s41587-020-0439-x

* Software dependencies
    https://github.com/nf-core/evefinder/blob/master/CITATIONS.md
"""
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command,
        false
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    //
    // Create channel from input file provided through params.input
    //

    if (params.step == 'prepare_inputs') {
        // One map per genome: [ id: accession, virus_taxid: ... ]
        ch_samplesheet = channel
            .fromList(samplesheetToList(input, "${projectDir}/assets/schema_prepare_inputs.json"))
            .map { row -> row[0] }
    }
    else {
        // [ meta, genome, baits, db_fasta, db_metadata ]
        ch_samplesheet = channel
            .fromList(samplesheetToList(input, "${projectDir}/assets/schema_input.json"))
    }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report  //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)

    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
//
// Check and validate pipeline parameters
//
def validateInputParameters() {
    genomeExistsError()

    if (params.step == 'prepare_inputs') {
        def local_db = params.virus_db_fasta || params.virus_db_metadata
        if (params.download_virus_db && local_db) {
            error("Use either --download_virus_db or --virus_db_fasta/--virus_db_metadata, not both.")
        }
        if (!params.download_virus_db && !(params.virus_db_fasta && params.virus_db_metadata)) {
            error("--step prepare_inputs needs a viral database: pass --download_virus_db, or both --virus_db_fasta and --virus_db_metadata.")
        }
    }
    if (params.cluster_tool == 'cdhit' && params.cluster_identity < 0.8) {
        error("cd-hit-est clusters at --cluster_identity 0.8 or more; use --cluster_tool vclust for a lower identity.")
    }
    if (params.step == 'analysis' && !params.screening_outdir) {
        error("--step analysis needs --screening_outdir: the --outdir of the --step screening run.")
    }
}

//
// Get attribute from genome config file e.g. fasta
//
def getGenomeAttribute(attribute) {
    if (params.genomes && params.genome && params.genomes.containsKey(params.genome)) {
        if (params.genomes[ params.genome ].containsKey(attribute)) {
            return params.genomes[ params.genome ][ attribute ]
        }
    }
    return null
}

//
// Exit pipeline if incorrect --genome key provided
//
def genomeExistsError() {
    if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
        def error_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
            "  Genome '${params.genome}' not found in any config files provided to the pipeline.\n" +
            "  Currently, the available genome keys are:\n" +
            "  ${params.genomes.keySet().join(", ")}\n" +
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        error(error_string)
    }
}
//
// Generate methods description for MultiQC
//
// [ in-text citation, bibliography entry ] of each tool, see CITATIONS.md
def toolReferences() {
    return [
        eefinder: ["EEfinder (Dias et al. 2024)", "Dias YJM, Dezordi FZ, Wallau GL. (2024) EEFinder: A general-purpose tool for identification of bacterial and viral endogenized elements in eukaryotic genomes. Comput Struct Biotechnol J. doi: 10.1016/j.csbj.2024.10.012"],
        datasets: ["NCBI Datasets (O'Leary et al. 2024)", "O'Leary NA, et al. (2024) Exploring and retrieving sequence and metadata for species across the tree of life with NCBI Datasets. Sci Data 11:732. doi: 10.1038/s41597-024-03571-y"],
        seqkit: ["SeqKit (Shen et al. 2016)", "Shen W, Le S, Li Y, Hu F. (2016) SeqKit: a cross-platform and ultrafast toolkit for FASTA/Q file manipulation. PLoS One 11(10):e0163962. doi: 10.1371/journal.pone.0163962"],
        blast: ["BLAST+ (Camacho et al. 2009)", "Camacho C, et al. (2009) BLAST+: architecture and applications. BMC Bioinformatics 10:421. doi: 10.1186/1471-2105-10-421"],
        diamond: ["DIAMOND (Buchfink et al. 2015)", "Buchfink B, Xie C, Huson DH. (2015) Fast and sensitive protein alignment using DIAMOND. Nat Methods 12(1):59-60. doi: 10.1038/nmeth.3176"],
        bedtools: ["BEDTools (Quinlan and Hall 2010)", "Quinlan AR, Hall IM. (2010) BEDTools: a flexible suite of utilities for comparing genomic features. Bioinformatics 26(6):841-2. doi: 10.1093/bioinformatics/btq033"],
        cdhit: ["CD-HIT (Fu et al. 2012)", "Fu L, Niu B, Zhu Z, Wu S, Li W. (2012) CD-HIT: accelerated for clustering the next-generation sequencing data. Bioinformatics 28(23):3150-2. doi: 10.1093/bioinformatics/bts565"],
        vclust: ["Vclust (Zielezinski et al. 2025)", "Zielezinski A, et al. (2025) Ultrafast and accurate sequence alignment and clustering of viral genomes. Nat Methods. doi: 10.1038/s41592-025-02701-7"],
        mashtree: ["Mashtree (Katz et al. 2019)", "Katz LS, et al. (2019) Mashtree: a rapid comparison of whole genome sequence files. J Open Source Softw 4(44):1762. doi: 10.21105/joss.01762"],
        mash: ["Mash (Ondov et al. 2016)", "Ondov BD, et al. (2016) Mash: fast genome and metagenome distance estimation using MinHash. Genome Biol 17:132. doi: 10.1186/s13059-016-0997-x"],
        krona: ["Krona (Ondov et al. 2011)", "Ondov BD, Bergman NH, Phillippy AM. (2011) Interactive metagenomic visualization in a Web browser. BMC Bioinformatics 12:385. doi: 10.1186/1471-2105-12-385"],
        biopython: ["Biopython (Cock et al. 2009)", "Cock PJA, et al. (2009) Biopython: freely available Python tools for computational molecular biology and bioinformatics. Bioinformatics 25(11):1422-3. doi: 10.1093/bioinformatics/btp163"],
        pandas: ["pandas (McKinney 2010)", "McKinney W. (2010) Data structures for statistical computing in Python. Proceedings of the 9th Python in Science Conference, 56-61. doi: 10.25080/Majora-92bf1922-00a"],
        plotly: ["Plotly (Plotly Technologies Inc. 2015)", "Plotly Technologies Inc. (2015) Collaborative data science. Montréal, QC. URL: https://plot.ly"],
        matplotlib: ["Matplotlib (Hunter 2007)", "Hunter JD. (2007) Matplotlib: A 2D graphics environment. Comput Sci Eng 9(3):90-95. doi: 10.1109/MCSE.2007.55"],
        seaborn: ["seaborn (Waskom 2021)", "Waskom ML. (2021) seaborn: statistical data visualization. J Open Source Softw 6(60):3021. doi: 10.21105/joss.03021"],
        multiqc: ["MultiQC (Ewels et al. 2016)", "Ewels P, Magnusson M, Lundin S, Käller M. (2016) MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics 32(19):3047-3048. doi: 10.1093/bioinformatics/btw354"],
    ]
}

// The tools this run's --step and options use
def toolsUsed() {
    def tools = []
    if (params.step == 'prepare_inputs') {
        tools += ['datasets', 'seqkit', 'eefinder', 'cdhit']
    }
    else if (params.step == 'screening') {
        tools += ['eefinder', params.search_mode == 'diamond' ? 'diamond' : 'blast', 'bedtools']
        if (!params.skip_clustering) {
            tools += [params.cluster_tool]
        }
    }
    else if (params.step == 'analysis') {
        if (!params.skip_phylogeny) {
            tools += ['mashtree', 'mash']
        }
        if (!params.skip_plots) {
            tools += ['krona', 'biopython', 'pandas', 'plotly', 'matplotlib', 'seaborn']
        }
    }
    return (tools + ['multiqc']).unique()
}

def toolCitationText() {
    def references = toolReferences()
    return "Tools used in the workflow included: " + toolsUsed().collect { tool -> references[tool][0] }.join(', ') + "."
}

def toolBibliographyText() {
    def references = toolReferences()
    return toolsUsed().collect { tool -> "<li>${references[tool][1]}</li>" }.join(' ')
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = toolCitationText()
    meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
