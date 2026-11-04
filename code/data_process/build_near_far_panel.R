# Question 3. Two EXPLICIT stages: prepare OD aggregates, then fit models.
suppressPackageStartupMessages({library(tidyverse);library(arrow)})
ROOT <- '.'; OUT <- 'output/research_extensions'; path <- function(...) file.path(ROOT, ...)
options(warn=1)


folder<-file.path(OUT,'03_near_far');dir.create(folder,recursive=TRUE,showWarnings=FALSE)
STAGE<-Sys.getenv('LIHTC_OD_STAGE','prepare') # check | prepare | estimate
stopifnot(STAGE %in% c('check','prepare','estimate'))
files<-sort(list.files(path('data_raw/LODES/OD_related/out_od_full_parquet_with_dist_both'),pattern='^od_full_.*_20(1[0-9])\\.parquet$',full.names=TRUE))
stopifnot(length(files)>0)
write_csv(tibble(file=files,bytes=file.info(files)$size),file.path(folder,'od_input_manifest.csv'))
aggregate_file<-file.path(folder,'od_near_far_panel.parquet')
if(STAGE=='prepare') {
 suppressPackageStartupMessages(library(data.table))
 data.table::setDTthreads(4)
 arrow::set_cpu_count(4)
 road<-open_dataset(path('data_raw/LODES/OD_related/cache/tract_pair_road_distance_2021.parquet'))
 chunks<-list(); file_audit<-list(); cached_state<-NA_character_;rd_cache<-NULL
 states<-sub('^od_full_([^_]+)_.*$','\\1',basename(files))
 for(i in seq_along(files)) {
  message(i,' / ',length(files),' ',basename(files[i]))
  # Read lookup once per file-state across ALL years; preserve identical formulas.
  if(!identical(cached_state,states[i])) {
   if(!is.null(rd_cache)){rm(rd_cache);gc()}
   homes<-open_dataset(files[states==states[i]]) %>% select(h_tract) %>% distinct() %>% collect() %>% pull(h_tract)
   rd_cache<-as.data.table(road %>% filter(h_tract %in% homes) %>% select(h_tract,w_tract,road_dist_km,success) %>% collect())
   stopifnot(!anyDuplicated(rd_cache[,.(h_tract,w_tract)]))
   setkey(rd_cache,h_tract,w_tract);cached_state<-states[i]
  }
  d<-as.data.table(read_parquet(files[i],col_select=c('h_tract','w_tract','year','S000','dist_centroid_km')))
  stopifnot(!anyDuplicated(d[,.(h_tract,w_tract,year)]),!anyNA(d$S000),all(d$S000>=0))
  n_before<-nrow(d);d<-rd_cache[d,on=.(h_tract,w_tract)]
  stopifnot(nrow(d)==n_before)
  d[,distance:=fifelse(is.finite(dist_centroid_km)&dist_centroid_km>=0,dist_centroid_km,NA_real_)]
  d[,route:=fifelse(h_tract==w_tract,distance,fifelse(!is.na(success)&success==1&is.finite(road_dist_km)&road_dist_km>=0,road_dist_km,NA_real_))]
  d[,`:=`(missing_distance=fifelse(is.na(distance),as.numeric(S000),0),
    valid_road=fifelse(is.finite(route),as.numeric(S000),0),
    road_sum=fifelse(is.finite(route),as.numeric(S000)*route,0))]
  file_audit[[i]]<-tibble(file=basename(files[i]),rows=nrow(d),jobs=sum(d$S000),
   cross_state_jobs=sum(d$S000[substr(d$h_tract,1,2)!=substr(d$w_tract,1,2)]),missing_distance_jobs=sum(d$missing_distance))
  for(r in c(5,10,20)) {
   d[,(paste0('near_',r)):=fifelse(!is.na(distance)&distance<=r,as.numeric(S000),0)]
   d[,(paste0('far_',r)):=fifelse(!is.na(distance)&distance>r,as.numeric(S000),0)]
  }
  d[,same_tract:=fifelse(h_tract==w_tract,as.numeric(S000),0)]
  cols<-c('S000','same_tract','missing_distance','valid_road','road_sum','near_5','far_5','near_10','far_10','near_20','far_20')
  tmp<-d[,lapply(.SD,sum),by=.(h_tract,year),.SDcols=cols]
  setnames(tmp,c('S000','missing_distance'),c('od_total','unknown'))
  tmp[,source_file:=basename(files[i])]
  chunks[[i]]<-as_tibble(tmp)
  # Small checkpoint audit so a long aggregation remains inspectable.
  if(i%%10==0)write_csv(bind_rows(file_audit),file.path(folder,'od_file_audit_progress.csv'))
  rm(d,tmp);gc()
 }
 z<-bind_rows(chunks)
 # If origins overlap across files, STOP: resolve file partition/duplicates before summing.
 dup<-z %>% count(h_tract,year) %>% filter(n>1)
 write_csv(dup,file.path(folder,'overlapping_origin_years.csv'));stopifnot(nrow(dup)==0)
 z<-z %>% mutate(tract_id=as.numeric(h_tract),road_coverage=if_else(od_total>0,valid_road/od_total,NA_real_),
  reconstructed_commute=if_else(valid_road>0,road_sum/valid_road,NA_real_))
 for(r in c(5,10,20)) stopifnot(max(abs(z[[paste0('near_',r)]]+z[[paste0('far_',r)]]+z$unknown-z$od_total))<1e-8)
 stopifnot(all(z$near_5<=z$near_10),all(z$near_10<=z$near_20))
 old<-read_parquet(path('data_panels/od_commute_panel_residence_road.parquet')) %>%
  transmute(tract_id=as.numeric(h_tract),year,old_total=total_s000,old_mean=avg_road_dist_from_s000)
 check<-full_join(select(z,tract_id,year,od_total,reconstructed_commute),old,by=c('tract_id','year')) %>%
  filter(between(year,2010,2019)) %>% mutate(total_difference=od_total-old_total,mean_difference=reconstructed_commute-old_mean)
 write_csv(check,file.path(folder,'existing_commute_reconciliation.csv'))
 stopifnot(!anyNA(check$total_difference),all(abs(check$total_difference)<1e-6),
  all(is.na(check$reconstructed_commute)==is.na(check$old_mean)),all(abs(na.omit(check$mean_difference))<1e-6))
 write_csv(bind_rows(file_audit),file.path(folder,'od_file_audit.csv'))
 write_parquet(z,aggregate_file)
}
