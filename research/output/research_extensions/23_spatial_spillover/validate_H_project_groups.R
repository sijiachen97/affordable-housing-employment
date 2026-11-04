suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2]
h<-read_csv(file.path(root,'stage_h/matching/matched_pairs.csv'),show_col_types=FALSE);m<-read_csv(file.path(out,'H_group_assignment.csv'),show_col_types=FALSE)
stopifnot(nrow(h)==nrow(m),nrow(anti_join(h,m,by=c('radius_km','cohort','treated_id','control_id')))==0)
z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));p<-z$pts
raw<-read_csv('./data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv',col_types=cols(.default=col_character()))%>%filter(str_trim(type)=='1')%>%mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)))
unk<-unique(raw$tract_id[is.na(raw$pis)|raw$pis%in%c(8888,9999)]);new<-unique(raw$tract_id[is.finite(raw$pis)&raw$pis>=2010&raw$pis<=2019])
for(i in seq_len(nrow(m))){v<-m[i,];ids<-setdiff(p$tract_id[z$members[[as.character(v$radius_km)]][[v$treated_index]]],v$treated_id);expected<-if(any(ids%in%unk))'unknown' else if(any(ids%in%new))'with_projects' else 'no_projects';stopifnot(expected==v$project_group)}
l<-read_csv(file.path(root,'stage_l/estimates/att_long.csv'),show_col_types=FALSE)%>%filter(sample=='new_full',covariance=='spatial_50km',outcome%in%c('rac','log_rac'))
n<-read_csv(file.path(out,'att_long.csv'),show_col_types=FALSE)%>%filter(sample=='no_projects',covariance=='spatial_50km')
q<-left_join(n,l,by=c('radius_km','component','outcome'),suffix=c('_M','_L'));stopifnot(max(abs(q$native_weight_att-q$estimate_L))<1e-7,all(q$pairs_M==q$pairs_L))
w<-read_csv(file.path(out,'common_aggregation_weights.csv'),show_col_types=FALSE)
counts<-m%>%filter(project_group!='unknown')%>%count(radius_km,cohort,name='N')
for(r in c(3,5,10)){
 den<-counts%>%filter(radius_km==r)%>%summarise(x=sum(N*(2020-cohort)))%>%pull(x)
 v<-w%>%filter(radius_km==r,event>=0)%>%left_join(counts,by=c('radius_km','cohort'))
 stopifnot(all(abs(v$att_weight-v$N/den)<1e-12))
}
writeLines(c('PASS: all H pairs preserved with original controls and independently verified group assignment from raw TYPE=1 data.', 'PASS: unknown-timing neighbors excluded from both known groups.', 'PASS: no-project native-weight ATT reproduces Stage L exactly.', 'PASS: common post-cell weights equal pooled known H cohort counts / pooled observed post cells; both groups share identical weights.'),file.path(out,'INDEPENDENT_VALIDATION.txt'))
