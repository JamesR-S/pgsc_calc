process PLINK2_RELABELBIM {
    tag "$meta.id chromosome $meta.chrom"

    storeDir ( params.genotypes_cache ? "$params.genotypes_cache/${meta.id}/${meta.build}/${meta.chrom}" :
              "$workDir/genomes/${meta.id}/${meta.build}/${meta.chrom}/")

    label 'process_low'
    label "${ params.copy_genomes ? 'copy_genomes' : '' }"

    conda (params.enable_conda ? "bioconda::plink2==2.00a3.3" : null)
    def dockerimg = "${ params.platform == 'amd64' ?
        'quay.io/biocontainers/plink2:2.00a3.3--hb2a7ceb_0' :
        'dockerhub.ebi.ac.uk/gdp-public/pgsc_calc/plink2:arm64-2.00a3.3' }"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/plink2:2.00a3.3--hb2a7ceb_0' :
        dockerimg }"

    input:
    // input is sorted alphabetically -> bed, bim, fam or pgen, psam, pvar
    tuple val(meta), path(geno), path(variants), path(pheno)

    output:
    tuple val(meta), path("*.bed"), emit: geno
    tuple val(meta), path("*.zst"), emit: variants
    tuple val(meta), path("*.fam"), emit: pheno
    path "versions.yml"           , emit: versions

    when:
    // only execute when bfile because output format is different (bim vs pvar)
    meta.is_bfile

    script:
    def args = task.ext.args ?: ''
    def compressed = variants.getName().endsWith("zst") ? 'vzs' : ''
    def prefix = task.ext.suffix ? "${meta.id}${task.ext.suffix}_" : "${meta.id}_"
    def build = meta.build? meta.build + '_': ''
    def mem_mb = task.memory.toMega() // plink is greedy
    // if dropping multiallelic variants, set a generic ID that won't match
    def set_ma_missing = params.keep_multiallelic ? '' : '--var-id-multi @:#'

    """
    plink2 \\
        --threads $task.cpus \\
        --memory $mem_mb \\
        $args \\
        --set-all-var-ids '@:#:\$r:\$a' \\
        $set_ma_missing \\
        --bfile ${geno.baseName} $compressed \\
        --make-just-bim zs \\
        --out ${build}${prefix}${meta.chrom}

    cp -RP $geno ${build}${prefix}${meta.chrom}.bed
    cp -RP $pheno ${build}${prefix}${meta.chrom}.fam

    cat <<-END_VERSIONS > versions.yml
    ${task.process.tokenize(':').last()}:
        plink2: \$(plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//' )
    END_VERSIONS
    """
}
