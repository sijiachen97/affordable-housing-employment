suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2];z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base;p<-z$pts
h<-read_csv(file.path(root,'stage_h/matching/matched_pairs.csv'),show_col_types=FALSE);q<-read_csv(file.path(out,'combined_matched_pairs.csv'),show_col_types=FALSE);iso<-read_csv(file.path(root,'stage_j/matching/treated_surroundings_audit.csv'),show_col_types=FALSE);el<-read_csv(file.path(root,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)
panel<-read_csv('./data_panels/2010_2019_did_panel_with_seer.csv',show_col_types=FALSE,col_select=c(tract_id,year,seer_total_population,rac_total,wac_total))
annual<-lapply(2010:2019,function(y){v<-filter(panel,year==y);as.matrix(v[match(b$tract_id,v$tract_id),c('seer_total_population','rac_total','wac_total')])})
for(r in c(3,5,7)){
 hh<-filter(h,radius_km==r);qq<-filter(q,radius_km==r);ii<-filter(iso,radius_km==r);cv<-filter(el,radius_km==r)
 expected<-hh%>%filter(ii$isolated[match(treated_id,ii$tract_id)])
 stopifnot(isTRUE(all.equal(as.data.frame(qq),as.data.frame(expected),check.attributes=FALSE)),all(cv$clean_control[qq$control_index]))
 sums<-readRDS(file.path(root,'stage_b',paste0('region_annual_sums_',r,'km.rds')));sur<-lapply(1:10,function(t)sums[[t]][,c('seer_total_population','rac_total','wac_total')]-annual[[t]])
 for(k in seq_len(nrow(hh))){tt<-hh$treated_index[k];cc<-hh$control_index[k];g<-hh$cohort[k];ids<-b$tract_id[c(tt,cc)]
 stopifnot(all(!(ids%%1000000>=980000&ids%%1000000<990000)),is.na(b$first_pis_year[cc])||b$first_pis_year[cc]>2019,substr(sprintf('%011.0f',ids[1]),1,2)==substr(sprintf('%011.0f',ids[2]),1,2),length(intersect(z$members[[as.character(r)]][[tt]],z$members[[as.character(r)]][[cc]]))==0)
 for(t in seq_len(g-2010))stopifnot(all(annual[[t]][c(tt,cc),1]>=100),all(sur[[t]][c(tt,cc),1]>=100))
 for(x in list(annual[[g-2010]],sur[[g-2010]]))stopifnot(all(abs(log(pmax(x[tt,],1))-log(pmax(x[cc,],1)))<=log(c(3,5,5))+1e-10))
 }
 stopifnot(!anyDuplicated(hh[c('cohort','control_id')]),all(hh$max_core_distance<=1+1e-10))
}
writeLines('PASS: residential/pre-population eligibility, center/surround scale guards, clean controls, within-state disjoint areas, core caliper, no within-cohort reuse and exact isolation subset verified.',file.path(out,'INDEPENDENT_VALIDATION.txt'))
