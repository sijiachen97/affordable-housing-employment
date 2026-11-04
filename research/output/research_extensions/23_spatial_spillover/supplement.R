suppressPackageStartupMessages({library(tidyverse);library(sf)})
args<-commandArgs(TRUE);d<-args[1];z<-readRDS(file.path(d,'neighborhood_cache.rds'));p<-z$pts;b<-z$base
# Pairwise shared-tract dependence among focal treated centers, including across county boundaries.
t<-which(b$timing=='treated_2011_2019');o<-list()
for(r in c(3,5,10)){
 m<-z$members[[as.character(r)]][t];rev<-split(rep(seq_along(m),lengths(m)),unlist(m));edges<-unique(do.call(rbind,lapply(rev,function(v){if(length(v)<2)return(NULL);t(combn(v,2))})))
 if(is.null(edges))edges<-matrix(integer(),ncol=2)
 o[[as.character(r)]]<-tibble(radius_km=r,centers=length(t),overlapping_pairs=nrow(edges),centers_with_overlap=length(unique(as.vector(edges))),cross_county_pairs=sum(b$county_id[t[edges[,1]]]!=b$county_id[t[edges[,2]]]))
}
write_csv(bind_rows(o),file.path(d,'treated_region_overlap.csv'))
# Reproducible illustrative maps of original pooled pair geometry (centroid maps, not polygons).
a<-read_csv(file.path(d,'original_pairs_spatial_audit.csv'),show_col_types=FALSE) %>% filter(radius_km==5,window=='full_panel')
orig<-read_csv('./output/robustness_specs/event_study/spec_a_county_trajectory_matching/matched_pairs.csv',show_col_types=FALSE) %>% filter(group=='pooled')
choose<-c(a$match_id[which.min(abs(a$distance_km-median(a$distance_km)))],a$match_id[which.max(a$shared_tracts)])
for(k in seq_along(choose)){
 pair<-orig%>%filter(match_id==choose[k]);ti<-match(pair$tract_id[pair$treated_cohort==1],b$tract_id);ci<-match(pair$tract_id[pair$treated_cohort==0],b$tract_id)
 tm<-z$members[['5']][[ti]];cm<-z$members[['5']][[ci]];ii<-union(tm,cm)
 f<-p[ii,]%>%mutate(region=case_when(ii%in%intersect(tm,cm)~'Shared',ii%in%tm~'Treated region',TRUE~'Control region'))
 centers<-p[match(pair$tract_id,p$tract_id),]%>%mutate(role=if_else(pair$treated_cohort==1,'Treated center','Control center'))
 g<-ggplot(f,aes(centroid_lon,centroid_lat,color=region))+geom_point(size=2)+geom_point(data=centers,aes(shape=role),color='black',size=4)+coord_quickmap()+theme_bw()+labs(x='Longitude',y='Latitude',title=paste('Original pair:',choose[k]),subtitle='5 km centroid-defined regions; each point represents one tract',color=NULL,shape=NULL)
 ggsave(file.path(d,paste0('example_pair_',k,'.png')),g,width=8,height=6,dpi=180)
}
