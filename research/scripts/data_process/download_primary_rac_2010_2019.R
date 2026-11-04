suppressPackageStartupMessages({library(lehdr);library(arrow);library(dplyr)})
options(timeout=600,readr.num_threads=1)
root <- '.'
base <- file.path(root,'data_raw/LODES/primary_rac_2010_2019')
for(z in c('raw_cache','tract_chunks','logs')) dir.create(file.path(base,z),recursive=TRUE,showWarnings=FALSE)
states<-c(tolower(state.abb),'dc')
jobs<-expand.grid(state=states,year=2010:2019,stringsAsFactors=FALSE)
worker<-function(i){
 st<-jobs$state[i];yr<-jobs$year[i];key<-paste(st,yr,sep='_');dest<-file.path(base,'tract_chunks',paste0('rac_JT01_',key,'.parquet'))
 log<-file.path(base,'logs',paste0(key,'.log'))
 tryCatch({
 
 cache<-file.path(base,'raw_cache');old<-file.path(root,'data_raw/LODES/LODES7',paste0(toupper(st),'-lodes7'),'rac')
 fn<-paste0(st,'_rac_S000_JT01_',yr,'.csv.gz');if(file.exists(file.path(old,fn)))cache<-old
 rawpath<-file.path(cache,fn)
 valid_gz<-function() file.exists(rawpath) && file.info(rawpath)$size>0 && system2('/usr/bin/gzip',c('-t',shQuote(rawpath)),stdout=FALSE,stderr=FALSE)==0
 if(file.exists(dest) && valid_gz()){a<-read_parquet(dest);stopifnot(nrow(a)>0,!anyDuplicated(a$h_tract));return(data.frame(state=st,year=yr,status='cached',rows=nrow(a)))}
 if(file.exists(dest))file.rename(dest,paste0(dest,'.invalid'))
 for(attempt in 1:10){
 rawpath<-file.path(cache,fn)
 if(file.exists(rawpath) && !valid_gz()) file.rename(rawpath,paste0(rawpath,'.invalid.',attempt))
 ans<-try(grab_lodes(state=st,year=yr,version='LODES7',lodes_type='rac',job_type='JT01',segment='S000',agg_geo='tract',state_part='main',download_dir=cache,use_cache=TRUE),silent=TRUE)
 if(!inherits(ans,'try-error') && nrow(ans)>0 && valid_gz())break
 if(!inherits(ans,'try-error'))ans<-structure('Empty or truncated downloaded file',class='try-error')
 write(as.character(ans),log,append=TRUE)
 }
 if(inherits(ans,'try-error'))stop(as.character(ans))
 stopifnot(nrow(ans)>0,!anyDuplicated(ans$h_tract),all(ans$year==yr),all(ans$C000>=0),all(ans$C000==ans$CE01+ans$CE02+ans$CE03))
 write_parquet(ans,paste0(dest,'.tmp'));file.rename(paste0(dest,'.tmp'),dest)
 data.frame(state=st,year=yr,status='success',rows=nrow(ans))
 },error=function(e){write(conditionMessage(e),log,append=TRUE);data.frame(state=st,year=yr,status='FAILED',rows=0)})
}
cl<-parallel::makeCluster(3)
parallel::clusterEvalQ(cl,{suppressPackageStartupMessages({library(lehdr);library(arrow);library(dplyr)});options(timeout=600,readr.num_threads=1)})
parallel::clusterExport(cl,c('jobs','base','root','worker'))
r<-parallel::parLapplyLB(cl,seq_len(nrow(jobs)),worker)
parallel::stopCluster(cl)
m<-bind_rows(r);write.csv(m,file.path(base,'download_manifest.csv'),row.names=FALSE)
stopifnot(nrow(m)==510,!any(m$status=='FAILED'))
writeLines(c('LODES7 RAC S000 JT01; all 50 states and DC, 2010-2019.',capture.output(sessionInfo())),file.path(base,'provenance.txt'))
