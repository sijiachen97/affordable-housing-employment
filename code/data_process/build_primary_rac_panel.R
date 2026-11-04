# Extracted data-construction block; old regressions omitted.
# Separate JT01 sensitivity analysis. Original panel, paper, and matches are read-only.
ROOT <- '.'
Sys.setenv(LIHTC_EXTENSION_OUTPUT=file.path(ROOT,'output/primary_rac_replication'))
suppressPackageStartupMessages({library(tidyverse);library(arrow);library(fixest)})
path <- function(...) file.path(ROOT, ...)
options(warn=1);setFixest_nthreads(1)
base<-path('data_raw/LODES/primary_rac_2010_2019')
m<-read_csv(file.path(base,'download_manifest.csv'),show_col_types=FALSE)
stopifnot(nrow(m)==510,!any(m$status=='FAILED'))
r<-map2_dfr(m$state,m$year,~read_parquet(file.path(base,'tract_chunks',paste0('rac_JT01_',.x,'_',.y,'.parquet')))) %>% mutate(tract_id=as.numeric(h_tract),year=as.integer(year))
stopifnot(!anyDuplicated(r[c('tract_id','year')]),all(r$C000==r$CE01+r$CE02+r$CE03))
# Preserve all original columns; added primary counts use explicit names.
r<-r %>% transmute(tract_id,year,primary_rac_total=C000,primary_rac_low=CE01,primary_rac_mid=CE02,primary_rac_high=CE03)
original<-read_csv(path('data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE)
joined<-left_join(original,r,by=c('tract_id','year'),relationship='one-to-one')
stopifnot(nrow(joined)==nrow(original),all(vapply(names(original),function(nm) identical(joined[[nm]],original[[nm]]),logical(1))))
dir.create(path('data_panels/primary_rac'),showWarnings=FALSE)
write_parquet(joined,path('data_panels/primary_rac/2010_2019_panel_with_primary_rac.parquet'))
