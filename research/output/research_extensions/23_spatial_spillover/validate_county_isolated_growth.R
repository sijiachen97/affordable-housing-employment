suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2];z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base
p<-read_csv('./data_panels/2010_2019_did_panel_with_seer.csv',show_col_types=FALSE,col_select=c(tract_id,year,rac_total,wac_total,seer_total_population))
annual<-lapply(2010:2019,function(y){v<-p%>%filter(year==y);log(pmax(as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')]),1))})
rawannual<-lapply(2010:2019,function(y){v<-p%>%filter(year==y);as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')])})
el<-read_csv(file.path(root,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control))
iso<-read_csv(file.path(out,'treated_surroundings_audit.csv'),show_col_types=FALSE)
m<-read_csv(file.path(out,'matched_pairs.csv'),show_col_types=FALSE);checks<-list()
for(r in c(3,5,10)){
 sums<-readRDS(file.path(root,'stage_b',paste0('region_annual_sums_',r,'km.rds')))
 f<-lapply(1:10,function(t)cbind(annual[[t]],log(pmax(sums[[t]][,c('rac_total','wac_total','seer_total_population')]-rawannual[[t]],1))))
 cv<-el%>%filter(radius_km==r);nonempty<-lengths(z$members[[as.character(r)]])>1
 for(g in 2011:2019){
  X<-f[[g-2010]]
  raw<-lapply(1:10,function(t)cbind(rawannual[[t]][,1:2],sums[[t]][,c('rac_total','wac_total')]-rawannual[[t]][,1:2]))
  block<-function(t0,t1)cbind((f[[t1-2009]]-f[[t0-2009]])/(t1-t0),(raw[[t1-2009]]-raw[[t0-2009]])/(t1-t0))
  if(g>=2012)X<-cbind(X,block(max(2010,g-3),g-1))
  if(g>=2015)X<-cbind(X,block(g-5,g-3))
  tr<-which(!is.na(b$first_pis_year)&b$first_pis_year==g&cv$treated_complete&nonempty)
  tr<-intersect(tr,match((iso%>%filter(radius_km==r,cohort==g,isolated))$tract_id,b$tract_id))
  sdT<-apply(X[tr,,drop=FALSE],2,sd);mm<-m%>%filter(radius_km==r,cohort==g)
  dist<-abs(sweep(X[mm$treated_index,,drop=FALSE]-X[mm$control_index,,drop=FALSE],2,sdT,'/'))
  checks[[length(checks)+1]]<-tibble(radius_km=r,cohort=g,pairs=nrow(mm),max_core_distance_recomputed=if(nrow(mm))max(dist) else NA_real_,n_core=ncol(X),difference_from_recorded=if(nrow(mm))max(abs(apply(dist,1,max)-mm$max_core_distance)) else NA_real_)
 }
}
checks<-bind_rows(checks);stopifnot(all(checks$max_core_distance_recomputed<=1+1e-10,na.rm=TRUE),all(checks$difference_from_recorded<1e-9,na.rm=TRUE))
write_csv(checks,file.path(out,'independent_growth_validation.csv'))
