# Runnable extraction of the original LODES7/JT00 download definitions.
# Preserves the source's state/year exceptions and within-state OD main files.
suppressPackageStartupMessages({library(lehdr);library(dplyr);library(purrr);library(arrow)})
root <- Sys.getenv('LODES_DIR', 'data_raw/LODES/OD_related/lodes7_tract_agg_2010_2019')
chunks <- file.path(root,'download_chunks');od_dir <- 'data_raw/LODES/OD_related/out_od_full_parquet'
cache <- 'data_raw/LODES/download_cache'
for (p in c(root,chunks,od_dir,cache)) dir.create(p,recursive=TRUE,showWarnings=FALSE)
states <- sort(c(tolower(state.abb),'dc'))
years_wac_od <- function(st) {
 if(st=='ak') return(2010:2016)
 if(st %in% c('ar','ms')) return(2010:2018)
 if(st=='ma') return(2011:2019)
 2010:2019
}
for (side in c('rac','wac','od')) {
 files <- list()
 for(st in states) for(yr in if(side=='rac')2010:2019 else years_wac_od(st)) {
  f <- file.path(chunks,paste0(side,'_',st,'_',yr,'.parquet'))
  if(!file.exists(f)) {
   message('Downloading ',side,' ',st,' ',yr)
   z <- grab_lodes(state=st,year=yr,lodes_type=side,job_type='JT00',segment='S000',agg_geo='tract',state_part='main',version='LODES7',download_dir=cache,use_cache=TRUE)
   stopifnot(nrow(z)>0,all(z$year==yr))
   z <- mutate(z,state=st)
   write_parquet(z,paste0(f,'.partial'));stopifnot(file.rename(paste0(f,'.partial'),f))
  }
  z <- read_parquet(f);stopifnot(nrow(z)>0,all(z$year==yr))
  if(side=='od') {
   stopifnot(!anyDuplicated(z[c('h_tract','w_tract','year')]))
   # Full within-state flows feed the geometry/road-distance workflow.
   write_parquet(z,file.path(od_dir,paste0('od_full_',st,'_',yr,'.parquet')))
   z <- z %>% filter(h_tract==w_tract) %>% group_by(h_tract,year) %>% summarise(od_same_total=sum(S000),.groups='drop') %>% rename(tract_id=h_tract)
   f <- file.path(chunks,paste0('od_same_',st,'_',yr,'.parquet'));write_parquet(z,f)
  }
  files[[length(files)+1]] <- f
 }
 combined <- map_dfr(files,read_parquet)
 name <- if(side=='od')'lodes_od_same_tract2010_2010_2019.parquet' else paste0('lodes_',side,'_outcomes_tract2010_2010_2019.parquet')
 write_parquet(combined,file.path(root,name))
 rm(combined);gc()
}
