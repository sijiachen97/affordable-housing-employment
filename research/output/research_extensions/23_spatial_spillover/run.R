suppressPackageStartupMessages({library(tidyverse);library(sf);library(arrow);library(data.table)})
ROOT<-'.'
script_arg<-commandArgs(FALSE);script_dir<-dirname(normalizePath(sub('^--file=','',script_arg[grepl('^--file=',script_arg)][1])));args<-commandArgs(trailingOnly=TRUE);dest<-if(length(args))args[1] else file.path(script_dir,'stage_a');dir.create(dest,recursive=TRUE,showWarnings=FALSE)
Sys.setenv(LIHTC_EXTENSION_OUTPUT=dest)
source(file.path(script_dir,'00_common_snapshot.R'))
x<-load_design();p<-x$panel
pts<-read_parquet(path('data_raw/LODES/OD_related/cache/tract2010_points_from_shapefile.parquet')) %>% mutate(tract_id=as.numeric(tract_id))
stopifnot(!anyDuplicated(pts$tract_id),all(is.finite(pts$centroid_lat)),all(is.finite(pts$centroid_lon)))
base<-p %>% distinct(tract_id,county_id,first_pis_year,timing)
idx<-match(base$tract_id,pts$tract_id);stopifnot(!anyNA(idx))
full<-read_csv(path('data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE)
cov<-full %>% group_by(tract_id) %>% summarise(n_years=n_distinct(year),complete=all(is.finite(rac_total)&is.finite(wac_total)&is.finite(seer_total_population)) & n_distinct(year)==10,.groups='drop')
pts<-left_join(pts,cov,by='tract_id') %>% mutate(complete=replace_na(complete,FALSE))
raw<-x$raw %>% mutate(known=!is.na(pis)&!pis %in%c(8888,9999),lat=suppressWarnings(as.numeric(latitude)),lon=suppressWarnings(as.numeric(longitude)),valid_coords=is.finite(lat)&is.finite(lon)&abs(lat)<=90&abs(lon)<=180&!(lat==0&lon==0))
write_csv(raw %>% summarise(records=n(),known_year=sum(known),unknown_year=sum(!known),valid_coordinates=sum(valid_coords),tract_with_centroid=sum(tract_id%in%pts$tract_id)),file.path(dest,'project_geography_audit.csv'))
# Entire new-construction inventory, including previously treated and non-panel tracts.
rawby<-split(raw,raw$tract_id)
events<-lapply(pts$tract_id,function(id){z<-rawby[[as.character(id)]];if(is.null(z)) numeric() else z$pis[z$known]})
unk<-vapply(pts$tract_id,function(id){z<-rawby[[as.character(id)]];!is.null(z)&&any(!z$known)},logical(1))
geo<-st_as_sf(pts,coords=c('centroid_lon','centroid_lat'),crs=4326)
message('Spatial neighborhoods for ',nrow(base),' eligible centers')
nb10<-st_is_within_distance(geo[idx,],geo,dist=10010)
hav<-function(i,j){rr<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((pts$centroid_lat[j]-pts$centroid_lat[i])*rr/2)^2+cos(pts$centroid_lat[i]*rr)*cos(pts$centroid_lat[j]*rr)*sin((pts$centroid_lon[j]-pts$centroid_lon[i])*rr/2)^2)))}
nb<-list();stats<-list();ev<-list()
for(rad in c(1,3,5,10)){
 message('Radius ',rad)
 members<-lapply(seq_along(idx),function(k){j<-nb10[[k]];j[hav(idx[k],j)<=rad]})
 stopifnot(all(vapply(seq_along(idx),function(k)idx[k]%in%members[[k]],logical(1))))
 nb[[as.character(rad)]]<-members
 ev[[as.character(rad)]]<-lapply(members,function(j)unlist(events[j],use.names=FALSE))
 stats[[as.character(rad)]]<-base %>% mutate(radius_km=rad,tracts=vapply(members,length,integer(1)),missing_panel_tracts=vapply(members,function(j)sum(!pts$tract_id[j]%in%cov$tract_id),integer(1)),incomplete_outcome_tracts=vapply(members,function(j)sum(!pts$complete[j]),integer(1)),unknown_timing_tracts=vapply(members,function(j)sum(unk[j]),integer(1)),projects_2010_2019=vapply(ev[[as.character(rad)]],function(y)sum(y>=2010&y<=2019),integer(1)),historical_projects=vapply(ev[[as.character(rad)]],function(y)sum(y<2010),integer(1)))
}
stats<-bind_rows(stats);write_csv(stats,file.path(dest,'center_geography_coverage.csv.gz'))
saveRDS(list(base=base,pts=pts,members=nb,events=ev,unknown=unk),file.path(dest,'neighborhood_cache.rds'))
message('Area diagnostic from DBF files')
files<-list.files(path('data_raw/LODES/tiger2010_tract/unzipped'),pattern='[.]dbf$',full.names=TRUE)
areas<-bind_rows(lapply(files,function(f){a<-foreign::read.dbf(f,as.is=TRUE);tibble(tract_id=as.numeric(a$GEOID10),land_km2=as.numeric(a$ALAND10)/1e6,total_km2=(as.numeric(a$ALAND10)+as.numeric(a$AWATER10))/1e6)})) %>% distinct(tract_id,.keep_all=TRUE)
write_csv(left_join(base,areas,by='tract_id'),file.path(dest,'tract_area.csv'))
qsum<-function(z)tibble(n=length(z),mean=mean(z),p25=unname(quantile(z,.25)),median=median(z),p75=unname(quantile(z,.75)),p90=unname(quantile(z,.9)),max=max(z))
write_csv(left_join(base,areas,by='tract_id') %>% filter(!is.na(land_km2)) %>% group_by(timing) %>% group_modify(~qsum(.x$land_km2)),file.path(dest,'tract_area_summary.csv'))
write_csv(stats %>% group_by(timing,radius_km) %>% summarise(centers=n(),mean_tracts=mean(tracts),median_tracts=median(tracts),p90_tracts=quantile(tracts,.9),center_only=sum(tracts==1),complete_regions=sum(incomplete_outcome_tracts==0),no_new_projects_2010_2019=sum(projects_2010_2019==0),unknown_regions=sum(unknown_timing_tracts>0),.groups='drop'),file.path(dest,'region_summary.csv'))
# Original pooled pairs: distance, exact shared-tract membership, and prospective exposure scenarios.
pairs<-x$pairs %>% filter(group=='pooled') %>% select(match_id,tract_id,treated_cohort,cohort) %>% pivot_wider(names_from=treated_cohort,values_from=tract_id,names_prefix='id')
pairs$ti<-match(pairs$id1,base$tract_id);pairs$ci<-match(pairs$id0,base$tract_id)
pairs$distance_km<-vapply(seq_len(nrow(pairs)),function(k)hav(idx[pairs$ti[k]],idx[pairs$ci[k]]),numeric(1))
pr<-list();cand<-list();treated<-which(base$timing=='treated_2011_2019')
for(rad in c(1,3,5,10)){
 rr<-as.character(rad);st<-stats %>% filter(radius_km==rad);mem<-nb[[rr]];ee<-ev[[rr]]
 for(win in c('full_panel','cohort_window')){
  message('Candidates ',rad,' ',win)
  rows<-lapply(treated,function(k){g<-base$first_pis_year[k];lo<-if(win=='full_panel')2010 else max(2010,g-1);hi<-if(win=='full_panel')2019 else min(2019,g+5)
   ids<-which(base$county_id==base$county_id[k]&(is.na(base$first_pis_year)|base$first_pis_year>hi))
   clean<-ids[vapply(ids,function(j)!any(ee[[j]]>=lo&ee[[j]]<=hi)&&st$unknown_timing_tracts[j]==0,logical(1))]
   far<-clean[hav(idx[k],idx[clean])>2*rad]
   complete<-far[st$incomplete_outcome_tracts[far]==0]
   tibble(tract_id=base$tract_id[k],cohort=g,county_id=base$county_id[k],radius_km=rad,window=win,start=lo,end=hi,candidates_own_untreated=length(ids),candidates_no_local_new_projects=length(clean),candidates_disjoint=length(far),candidates_complete=length(complete),treated_complete=st$incomplete_outcome_tracts[k]==0,treated_unknown=st$unknown_timing_tracts[k]>0,other_tract_projects=sum(vapply(mem[[k]][mem[[k]]!=idx[k]],function(j)sum(events[[j]]>=lo&events[[j]]<=hi),integer(1))))
  });cand[[paste(rr,win)]]<-bind_rows(rows)
  pr[[paste(rr,win)]]<-bind_rows(lapply(seq_len(nrow(pairs)),function(k){g<-pairs$cohort[k];lo<-if(win=='full_panel')2010 else max(2010,g-1);hi<-if(win=='full_panel')2019 else min(2019,g+5);ci<-pairs$ci[k];ti<-pairs$ti[k]; y<-ee[[ci]]
   tibble(match_id=pairs$match_id[k],cohort=g,radius_km=rad,window=win,distance_km=pairs$distance_km[k],shared_tracts=length(intersect(mem[[ti]],mem[[ci]])),control_new_projects=sum(y>=lo&y<=hi),control_unknown=st$unknown_timing_tracts[ci]>0,control_complete=st$incomplete_outcome_tracts[ci]==0,treated_complete=st$incomplete_outcome_tracts[ti]==0)
  }))
 }
}
cand<-bind_rows(cand);pr<-bind_rows(pr)
write_csv(cand,file.path(dest,'candidate_counts_by_treated.csv'));write_csv(pr,file.path(dest,'original_pairs_spatial_audit.csv'))
cs<-cand %>% group_by(radius_km,window) %>% summarise(treated=n(),own_untreated_available=sum(candidates_own_untreated>0),clean_available=sum(candidates_no_local_new_projects>0),disjoint_available=sum(candidates_disjoint>0),complete_control_available=sum(candidates_complete>0),both_complete_available=sum(candidates_complete>0&treated_complete),both_complete_no_unknown=sum(candidates_complete>0&treated_complete&!treated_unknown),isolated_other_tract_available=sum(candidates_complete>0&treated_complete&!treated_unknown&other_tract_projects==0),median_disjoint_candidates=median(candidates_disjoint),.groups='drop')
write_csv(cs,file.path(dest,'candidate_summary.csv'))
write_csv(cand %>% group_by(radius_km,window,cohort) %>% summarise(treated=n(),disjoint_available=sum(candidates_disjoint>0),both_complete_available=sum(candidates_complete>0&treated_complete),.groups='drop'),file.path(dest,'candidate_summary_by_cohort.csv'))
ps<-pr %>% group_by(radius_km,window) %>% summarise(pairs=n(),overlap=sum(shared_tracts>0),exposed_controls=sum(control_new_projects>0),unknown_controls=sum(control_unknown),unexposed_nonoverlap=sum(shared_tracts==0&control_new_projects==0&!control_unknown),complete_unexposed_nonoverlap=sum(shared_tracts==0&control_new_projects==0&!control_unknown&control_complete&treated_complete),.groups='drop')
write_csv(ps,file.path(dest,'original_pair_summary.csv'))
# Verify index-based neighborhoods against independent all-point haversine for random centers.
set.seed(2310);check<-sample(seq_along(idx),30)
for(k in check)for(rad in c(1,3,5,10))stopifnot(setequal(which(hav(idx[k],seq_len(nrow(pts)))<=rad),nb[[as.character(rad)]][[k]]))
stopifnot(all(cand$candidates_complete<=cand$candidates_disjoint),all(cand$candidates_disjoint<=cand$candidates_no_local_new_projects))
writeLines(c('PASS: original treatment timing and never-treated audits from load_design.', 'PASS: all eligible centers have unique finite coordinates.', 'PASS: 30 independently checked origins at all four radii.', 'PASS: all neighborhood lists include center.', 'PASS: candidate counts nested under successive restrictions.', 'Missing outcomes are not zero. Full geographic neighbors include pre-2010-treated and non-panel tracts.', 'Exposure is tract-centroid based, not exact project coordinates. Unknown-year projects excluded from candidate regions.', 'Distance >2r is a sufficient non-overlap screen and may be conservative; actual original-pair overlaps use set intersections.', 'Candidate counts are availability only: reuse allowed; no propensity matching, caliper, balance, or causal estimates yet.'),file.path(dest,'VALIDATION.txt'))
ggplot(ps,aes(radius_km,100*exposed_controls/pairs,color=window))+geom_line()+geom_point()+theme_bw()+labs(x='Radius (km)',y='Original controls with new LIHTC exposure (%)',color='Window')->fig;ggsave(file.path(dest,'control_exposure.png'),fig,width=8,height=5,dpi=180)
cs %>% pivot_longer(c(disjoint_available,both_complete_available),names_to='screen',values_to='n') %>% ggplot(aes(radius_km,n,color=screen))+geom_line()+geom_point()+facet_wrap(~window)+theme_bw()+labs(x='Radius (km)',y='Treated centers with at least one candidate')->fig;ggsave(file.path(dest,'candidate_availability.png'),fig,width=10,height=5,dpi=180)
print(cs,width=Inf);print(ps,width=Inf)
writeLines('COMPLETE',file.path(dest,'COMPLETE.txt'))
