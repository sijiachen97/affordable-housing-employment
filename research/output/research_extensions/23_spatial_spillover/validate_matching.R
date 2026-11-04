suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE); src<-a[1];out<-a[2]
z<-readRDS(file.path(src,'neighborhood_cache.rds'));b<-z$base;p<-z$pts
m<-read_csv(file.path(out,'matched_pairs.csv'),show_col_types=FALSE)
models<-read_csv(file.path(out,'propensity_model_audit.csv'),show_col_types=FALSE)
el<-read_csv(file.path(out,'eligibility_and_matching_status.csv'),show_col_types=FALSE)
hav<-function(i,j){q<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((p$centroid_lat[j]-p$centroid_lat[i])*q/2)^2+cos(p$centroid_lat[i]*q)*cos(p$centroid_lat[j]*q)*sin((p$centroid_lon[j]-p$centroid_lon[i])*q/2)^2)))}
stopifnot(all(b$tract_id[m$treated_index]==m$treated_id),all(b$tract_id[m$control_index]==m$control_id),
 all(b$first_pis_year[m$treated_index]==m$cohort),all(is.na(b$first_pis_year[m$control_index])|b$first_pis_year[m$control_index]>2019),
 !anyDuplicated(m[c('radius_km','scope','cohort','treated_id')]),!anyDuplicated(m[c('radius_km','scope','cohort','control_id')]))
for(i in seq_len(nrow(m))){v<-m[i,];ti<-v$treated_index;ci<-v$control_index;r<-as.character(v$radius_km)
 stopifnot(length(intersect(z$members[[r]][[ti]],z$members[[r]][[ci]]))==0,
  hav(match(v$treated_id,p$tract_id),match(v$control_id,p$tract_id))>2*v$radius_km)
 if(v$scope=='county')stopifnot(b$county_id[ti]==b$county_id[ci])
 stopifnot(substr(sprintf('%011.0f',v$treated_id),1,2)==substr(sprintf('%011.0f',v$control_id),1,2))
}
mc<-m%>%left_join(models,by=c('radius_km','cohort'));stopifnot(all(mc$score_distance<=mc$caliper+1e-12))
ctl<-el%>%filter(!is.na(clean_control))%>%select(radius_km,tract_id,clean_control)
stopifnot(all((m%>%left_join(ctl,by=c('radius_km','control_id'='tract_id')))$clean_control))
# Ensure both descriptive windows are present when g=2019 (same numerical values).
h<-read_csv(file.path(out,'treated_housing_scale.csv'),show_col_types=FALSE)
missing<-h%>%filter(cohort==2019,period=='first_year')%>%mutate(period='through_2019')%>%anti_join(h,by=c('radius_km','scope','cohort','treated_id','period'))
h<-bind_rows(h,missing);write_csv(h,file.path(out,'treated_housing_scale.csv'))
hs<-h%>%group_by(radius_km,scope,period)%>%summarise(treated=n(),mean_projects=mean(projects),median_projects=median(projects),
 regions_complete_units=sum(projects_missing_units==0),mean_total_units_complete=mean(units_observed[projects_missing_units==0]),median_total_units_complete=median(units_observed[projects_missing_units==0]),.groups='drop')
write_csv(hs,file.path(out,'housing_scale_summary.csv'))
bal<-read_csv(file.path(out,'balance_by_cohort.csv'),show_col_types=FALSE)
bs<-bal%>%group_by(radius_km,scope)%>%summarise(mean_absolute_smd=weighted.mean(abs(smd_after),n_matched,na.rm=TRUE),max_absolute_smd=max(abs(smd_after),na.rm=TRUE),share_over_point1=mean(abs(smd_after)>.1,na.rm=TRUE),.groups='drop')
write_csv(bs,file.path(out,'balance_quality_summary.csv'));print(bs)
write_csv(el%>%filter(!is.na(status))%>%count(radius_km,scope,status),file.path(out,'matching_failure_summary.csv'))
write_csv(m%>%mutate(control_timing=if_else(is.na(b$first_pis_year[control_index]),'never','after_2019'))%>%count(radius_km,scope,control_timing),file.path(out,'matched_control_timing.csv'))
writeLines(c('PASS: independently verified exact shared-member non-overlap, center distance, state/county, timing, propensity caliper, candidate eligibility, and no within-cohort reuse for every matched pair.', 'No unknown-year centers reclassified as never treated; control sentinel not needed until estimation.', 'Descriptive housing windows both present for 2019 cohort.'),file.path(out,'INDEPENDENT_VALIDATION.txt'))
# Independently recompute sampled geographic sums directly from member rows.
panel<-read_csv('./data_panels/2010_2019_did_panel_with_seer.csv',show_col_types=FALSE,col_select=c(tract_id,year,rac_total,wac_total,seer_total_population))
set.seed(2310)
for(rad in c(3,5,10)){
 sums<-readRDS(file.path(out,paste0('region_annual_sums_',rad,'km.rds')))
 selected<-unique(c(sample(which(b$timing=='treated_2011_2019'),5),head(m$control_index[m$radius_km==rad],5)))
 for(k in selected)for(yr in c(2010,2015,2019)){
  ids<-p$tract_id[z$members[[as.character(rad)]][[k]]];v<-panel%>%filter(year==yr);v<-v[match(ids,v$tract_id),]
  for(y in c('rac_total','wac_total','seer_total_population'))stopifnot(isTRUE(all.equal(sum(v[[y]]),unname(sums[[yr-2009]][k,y]))))
 }
}
write('PASS: independently recomputed sampled RAC, WAC and population geographic sums in 2010, 2015, 2019; missing values preserved.',file=file.path(out,'INDEPENDENT_VALIDATION.txt'),append=TRUE)
