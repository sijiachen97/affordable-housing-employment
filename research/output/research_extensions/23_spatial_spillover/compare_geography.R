suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);d<-a[1];out<-a[2];dir.create(out,recursive=TRUE,showWarnings=FALSE)
z<-readRDS(file.path(d,'neighborhood_cache.rds'));b<-z$base;p<-z$pts;ii<-match(b$tract_id,p$tract_id);st<-read_csv(file.path(d,'center_geography_coverage.csv.gz'),show_col_types=FALSE);old<-read_csv(file.path(d,'candidate_counts_by_treated.csv'),show_col_types=FALSE)
state<-substr(sprintf('%011.0f',b$tract_id),1,2)
hav<-function(k,j){rr<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((p$centroid_lat[ii[j]]-p$centroid_lat[ii[k]])*rr/2)^2+cos(p$centroid_lat[ii[j]]*rr)*cos(p$centroid_lat[ii[k]]*rr)*sin((p$centroid_lon[ii[j]]-p$centroid_lon[ii[k]])*rr/2)^2)))}
res<-list()
for(r in c(3,5,10))for(w in c('full_panel','cohort_window')){
 s<-st%>%filter(radius_km==r);stopifnot(identical(s$tract_id,b$tract_id));ev<-z$events[[as.character(r)]]
 for(g in 2011:2019){
 lo<-if(w=='full_panel')2010 else max(2010,g-1);hi<-if(w=='full_panel')2019 else min(2019,g+5)
 clean<-which((is.na(b$first_pis_year)|b$first_pis_year>hi)&s$unknown_timing_tracts==0&vapply(ev,function(y)!any(y>=lo&y<=hi),logical(1)))
 for(k in which(b$first_pis_year==g&!is.na(b$first_pis_year))){
  far<-clean[hav(k,clean)>2*r];complete<-far[s$incomplete_outcome_tracts[far]==0]
  for(scope in c('county','state','national')){
   q<-switch(scope,county=complete[b$county_id[complete]==b$county_id[k]],state=complete[state[complete]==state[k]],national=complete)
   res[[length(res)+1]]<-tibble(tract_id=b$tract_id[k],cohort=g,radius_km=r,window=w,scope=scope,complete_candidates=length(q),treated_complete=s$incomplete_outcome_tracts[k]==0,treated_unknown=s$unknown_timing_tracts[k]>0)
  }
 }
 }
 message(r,' ',w)
}
x<-bind_rows(res)
check<-x%>%filter(scope=='county')%>%left_join(old%>%select(tract_id,radius_km,window,candidates_complete),by=c('tract_id','radius_km','window'))
stopifnot(all(check$complete_candidates==check$candidates_complete))
y<-x%>%group_by(radius_km,window,scope)%>%summarise(treated=n(),complete_treated=sum(treated_complete),any_candidate=sum(complete_candidates>0),both_complete=sum(treated_complete&complete_candidates>0),both_complete_known_timing=sum(treated_complete&!treated_unknown&complete_candidates>0),median_candidates=median(complete_candidates[treated_complete]),.groups='drop')
write_csv(x,file.path(out,'candidate_counts.csv'));write_csv(y,file.path(out,'comparison_summary.csv'));writeLines('PASS: same-county counts reproduce stage A exactly. No restriction on additional known-year projects in treated regions. Candidate availability, not completed matching. Exposure uses stage A tract-centroid proxy; unresolved geocoding limits remain.',file.path(out,'VALIDATION.txt'));print(y,n=30,width=Inf)
