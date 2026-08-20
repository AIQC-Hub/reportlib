#!/usr/bin/env Rscript
#
# Install everything reportlib needs, into the library of whichever R runs this.
#
#   Rscript tools/install-deps.R            # from a reportlib checkout
#   Rscript tools/install-deps.R --check    # report only, install nothing
#
# `R CMD INSTALL` does NOT resolve dependencies -- it stops at the first missing
# one ("dependency 'maps' is not available for package 'reportlib'") and rolls
# the install back. Run this first, then R CMD INSTALL. Or skip both and use
# remotes::install_github("AIQC-Hub/reportlib@<tag>"), which resolves them.
#
args  <- commandArgs(trailingOnly = TRUE)
check <- "--check" %in% args

here <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
desc <- normalizePath(file.path(here, "..", "DESCRIPTION"), mustWork = TRUE)

# Depends and Imports both have to be present at install time; Suggests do not.
d <- read.dcf(desc)
field <- function(name) {
  if (!name %in% colnames(d)) return(character())
  v <- trimws(strsplit(d[1, name], ",")[[1]])
  v <- sub("\\s*\\(.*\\)$", "", v)          # drop version constraints
  v[nzchar(v)]
}
needed <- setdiff(c(field("Depends"), field("Imports")), "R")

have    <- rownames(installed.packages())
missing <- setdiff(needed, have)

cat("R:       ", R.version.string, "\n", sep = "")
cat("library: ", .libPaths()[1], "\n", sep = "")
cat("declared:", length(needed), "packages\n")

if (!length(missing)) {
  cat("all present\n")
  quit(status = 0)
}

cat("missing: ", paste(missing, collapse = ", "), "\n", sep = "")
if (check) quit(status = 1)

repos <- getOption("repos")
if (is.null(repos[["CRAN"]]) || repos[["CRAN"]] == "@CRAN@") {
  repos["CRAN"] <- "https://cloud.r-project.org"
}
install.packages(missing, repos = repos)

still <- setdiff(needed, rownames(installed.packages()))
if (length(still)) {
  cat("still missing after install: ", paste(still, collapse = ", "), "\n", sep = "")
  quit(status = 1)
}
cat("done\n")
