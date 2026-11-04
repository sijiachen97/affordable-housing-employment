suppressPackageStartupMessages({library(tidyverse);library(sf)})
d<-commandArgs(TRUE)[1];z<-readRDS(file.path(d,'neighborhood_cache.rds'));b<-z$base;p<-z$pts
raw<-read_csv('./data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv',col_types=cols(.default=col_character())) %>% filter(str_trim(type)=='1') %>% mutate(tract_id=suppressWarnings(as.numeric(fips2010)),lat=as.numeric(latitude),lon=as.numeric(longitude),year=as.numeric(yr_pis)) %>% filter(year>=2010,year<=2019,is.finite(lat),is.finite(lon),abs(lat)<=90,abs(lon)<=180,!(lat==0&lon==0))
orig<-read_csv('./output/robustness_specs/event_study/spec_a_county_trajectory_matching/matched_pairs.csv',show_col_types=FALSE)%>%filter(group=='pooled',treated_cohort==0)
i<-match(orig$tract_id,p$tract_id);go<-st_as_sf(p[i,],coords=c('centroid_lon','centroid_lat'),crs=4326);gp<-st_as_sf(raw,coords=c('lon','lat'),crs=4326)
n<-st_is_within_distance(go,gp,dist=10010)
hav<-function(k,j){rr<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((raw$lat[j]-p$centroid_lat[i[k]])*rr/2)^2+cos(raw$lat[j]*rr)*cos(p$centroid_lat[i[k]]*rr)*sin((raw$lon[j]-p$centroid_lon[i[k]])*rr/2)^2)))}
a<-bind_rows(lapply(c(1,3,5,10),function(rad)bind_rows(lapply(seq_len(nrow(orig)),function(k){jj<-n[[k]];jj<-jj[hav(k,jj)<=rad];tibble(match_id=orig$match_id[k],radius_km=rad,projects_actual_point=length(jj),projects_without_cached_tract=sum(!raw$tract_id[jj]%in%p$tract_id))}))))
old<-read_csv(file.path(d,'original_pairs_spatial_audit.csv'),show_col_types=FALSE)%>%filter(window=='full_panel')
a<-left_join(a,old%>%select(match_id,radius_km,control_new_projects),by=c('match_id','radius_km'))
write_csv(a,file.path(d,'actual_project_coordinate_check.csv'))
write_csv(a%>%group_by(radius_km)%>%summarise(pairs=n(),exposed_actual=sum(projects_actual_point>0),exposed_tract_centroid=sum(control_new_projects>0),classification_differs=sum((projects_actual_point>0)!=(control_new_projects>0)),invalid_tract_exposure=sum(projects_without_cached_tract>0),.groups='drop'),file.path(d,'actual_project_coordinate_summary.csv'))
