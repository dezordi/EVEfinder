// Versions of the tools EEfinder runs; a tool the options do not run gets an empty version

// Version command of each tool, or `true` (prints nothing) when not in `used`
def versionCommands(List used) {
    def commands = [
        'blast'       : "blastx -version | sed '1!d;s/.* //;s/+\$//'",
        'cd-hit'      : "cd-hit -h | head -n 1 | sed 's/^.*CD-HIT version //;s/ (built.*//'",
        'diamond'     : "diamond version | sed 's/.* //'",
        'pyrodigal-gv': "python -c 'import pyrodigal_gv; print(pyrodigal_gv.__version__)'",
        'pyrodigal-rv': "python -c 'import pyrodigal_rv; print(pyrodigal_rv.__version__)'",
    ]
    return commands.collectEntries { tool, command -> [tool, tool in used ? command : 'true'] }
}

// Tools the similarity search runs for the `-md` and `-tm` options in `args`
def searchTools(args) {
    def text = args ?: ''
    def mode = (text =~ /(?:-md|--mode)[\s=]+(\S+)/).with { m -> m.find() ? m.group(1) : 'blastx' }
    def method = (text =~ /(?:-tm|--translation_method)[\s=]+(\S+)/).with { m -> m.find() ? m.group(1) : 'default' }
    def tools = [mode == 'blastx' ? 'blast' : 'diamond']
    if( method in ['gv', 'gv-rv'] ) {
        tools << 'pyrodigal-gv'
    }
    if( method in ['rv', 'gv-rv'] ) {
        tools << 'pyrodigal-rv'
    }
    if( method == 'gv-rv' ) {
        tools << 'cd-hit'
    }
    return tools
}
