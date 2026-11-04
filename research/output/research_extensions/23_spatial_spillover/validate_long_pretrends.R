suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2];z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base
p<-read_csv('./data_panels/2010_2019_did_panel_with_seer.csv',show_col_types=FALSE,col_select=c(tract_id,year,rac_total,wac_total,seer_total_population))
annual<-lapply(2010:2019,function(y){v<-p%>%filter(year==y);log(pmax(as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')]),1))})
rawannual<-lapply(2010:2019,function(y){v<-p%>%filter(year==y);as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')])})
el<-read_csv(file.path(root,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control))
m<-read_csv(file.path(out,'matched_pairs.csv'),show_col_types=FALSE);checks<-list()
for(r in c(3,5,10)){
 sums<-readRDS(file.path(root,'stage_b',paste0('region_annual_sums_',r,'km.rds')))
 f<-lapply(1:10,function(t)cbind(annual[[t]],log(pmax(sums[[t]][,c('rac_total','wac_total','seer_total_population')]-rawannual[[t]],1))))
 cv<-el%>%filter(radius_km==r);nonempty<-lengths(z$members[[as.character(r)]])>1
 for(g in 2015:2019){
  # Columns: center RAC/WAC/pop, surrounding RAC/WAC/pop, recent slopes, early slopes.
  j<-c(1,2,4,5);X<-cbind(f[[g-2010]],(f[[g-2010]][,j]-f[[g-2012]][,j])/2,(f[[g-2012]][,j]-f[[g-2014]][,j])/2)
  tr<-which(!is.na(b$first_pis_year)&b$first_pis_year==g&cv$treated_complete&nonempty)
  sdT<-apply(X[tr,,drop=FALSE],2,sd);mm<-m%>%filter(radius_km==r,cohort==g)
  dist<-abs(sweep(X[mm$treated_index,,drop=FALSE]-X[mm$control_index,,drop=FALSE],2,sdT,'/'))
  checks[[length(checks)+1]]<-tibble(radius_km=r,cohort=g,pairs=nrow(mm),max_core_distance_recomputed=max(dist),max_early_growth_distance=max(dist[,11:14]),difference_from_recorded=max(abs(apply(dist,1,max)-mm$max_core_distance)))
 }
}
checks<-bind_rows(checks);stopifnot(all(checks$max_core_distance_recomputed<=1+1e-10),all(checks$difference_from_recorded<1e-9))
write_csv(checks,file.path(out,'independent_early_growth_validation.csv'))
