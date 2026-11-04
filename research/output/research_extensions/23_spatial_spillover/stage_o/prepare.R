suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);r<-a[1];w<-a[2]
z<-readRDS(file.path(r,'stage_a/neighborhood_cache.rds'));n<-readRDS(file.path(r,'stage_n/work/stage_a/neighborhood_cache.rds'));stopifnot(identical(z$base,n$base));z$members[['7']]<-n$members[['7']];z$events[['7']]<-n$events[['7']];saveRDS(z,file.path(w,'stage_a/neighborhood_cache.rds'))
el<-read_csv(file.path(r,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control),radius_km%in%c(3,5))
el<-bind_rows(el,read_csv(file.path(r,'stage_n/work/stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE));write_csv(el,file.path(w,'stage_b/eligibility_and_matching_status.csv'))
iso<-read_csv(file.path(r,'stage_j/matching/treated_surroundings_audit.csv'),show_col_types=FALSE)%>%filter(radius_km%in%c(3,5));iso<-bind_rows(iso,read_csv(file.path(r,'stage_n/work/stage_j/matching/treated_surroundings_audit.csv'),show_col_types=FALSE));write_csv(iso,file.path(w,'stage_j/matching/treated_surroundings_audit.csv'))
for(rad in c(3,5,7))file.symlink(file.path(r,if(rad==7)'stage_n/work/stage_b' else 'stage_b',paste0('region_annual_sums_',rad,'km.rds')),file.path(w,'stage_b',paste0('region_annual_sums_',rad,'km.rds')))
file.symlink(file.path(r,'stage_c'),file.path(w,'stage_c'))
