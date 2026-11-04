# Stage B: exploratory matching and balance; no causal estimates.
# All predictors are measured by g-1. Outcomes and manuscript are unchanged.
suppressPackageStartupMessages({library(tidyverse);library(Matrix);library(sf)})
a <- commandArgs(TRUE); src <- a[1]; out <- a[2]
metric <- if(length(a)>=3)a[3] else 'propensity'
stopifnot(metric %in% c('propensity','mahalanobis'))
dir.create(out,recursive=TRUE,showWarnings=FALSE)
root <- '.'
z <- readRDS(file.path(src,'neighborhood_cache.rds')); b <- z$base; pts <- z$pts
idx <- match(b$tract_id,pts$tract_id); state <- substr(sprintf('%011.0f',b$tract_id),1,2)
coverage <- read_csv(file.path(src,'center_geography_coverage.csv.gz'),show_col_types=FALSE)
vars <- c('rac_total','wac_total','seer_total_population','seer_nh_black','seer_nh_aian','seer_nh_api','seer_hispanic','seer_age_under_29','seer_age_55_plus','rac_earn_le_1250','rac_earn_ge_3333','wac_earn_le_1250','wac_earn_ge_3333')
p <- read_csv(file.path(root,'data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE,col_select=all_of(c('tract_id','year',vars)))
stopifnot(!anyDuplicated(p[c('tract_id','year')]))
# Include coordinates from projects lacking valid tract IDs. Centroid exposure
# remains an additional conservative screen, not a substitute for coordinates.
raw <- read_csv(file.path(root,'data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv'),col_types=cols(.default=col_character())) %>%
 filter(str_trim(type)=='1') %>% mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)),
 lat=suppressWarnings(as.numeric(latitude)),lon=suppressWarnings(as.numeric(longitude)),units=suppressWarnings(as.numeric(n_units)),
 known=!is.na(pis)&!pis%in%c(8888,9999),validxy=is.finite(lat)&is.finite(lon)&abs(lat)<=90&abs(lon)<=180&!(lat==0&lon==0))
write_csv(raw %>% count(known,validxy),file.path(out,'project_location_audit.csv'))
rp <- raw %>% filter(validxy, !known | between(pis,2010,2019))
message('Checking actual project coordinates')
geo <- st_as_sf(pts[idx,],coords=c('centroid_lon','centroid_lat'),crs=4326)
gp <- st_as_sf(rp,coords=c('lon','lat'),crs=4326)
near <- st_is_within_distance(geo,gp,dist=10010)
hav <- function(la,lo,lat,lon) { q<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((lat-la)*q/2)^2+cos(la*q)*cos(lat*q)*sin((lon-lo)*q/2)^2))) }
features <- function(m,prefix) {
 pop<-m[,'seer_total_population']; rac<-m[,'rac_total']; wac<-m[,'wac_total']
 f<-cbind(log_pop=log(pmax(pop,1)),log_rac=log(pmax(rac,1)),log_wac=log(pmax(wac,1)),
 black=m[,'seer_nh_black']/pop,aian=m[,'seer_nh_aian']/pop,api=m[,'seer_nh_api']/pop,hispanic=m[,'seer_hispanic']/pop,
 age_0_24=m[,'seer_age_under_29']/pop,age_55plus=m[,'seer_age_55_plus']/pop,
 rac_low=m[,'rac_earn_le_1250']/rac,rac_high=m[,'rac_earn_ge_3333']/rac,wac_low=m[,'wac_earn_le_1250']/wac,wac_high=m[,'wac_earn_ge_3333']/wac)
 colnames(f)<-paste0(prefix,colnames(f)); f
}
annual <- lapply(2010:2019,function(yr){v<-p %>% filter(year==yr);as.matrix(v[match(pts$tract_id,v$tract_id),vars])}); names(annual)<-2010:2019
allpairs<-list(); audit<-list(); balance<-list(); sizes<-list(); eligibility<-list(); models<-list()
for(rad in c(3,5,10)) {
 message('Building region predictors: ',rad,' km')
 mem<-z$members[[as.character(rad)]]; cv<-coverage %>% filter(radius_km==rad)
 stopifnot(identical(cv$tract_id,b$tract_id))
 A<-sparseMatrix(i=rep(seq_len(nrow(b)),lengths(mem)),j=unlist(mem),x=1,dims=c(nrow(b),nrow(pts)))
 sums<-lapply(annual,function(m){missing<-!is.finite(m); m[missing]<-0; s<-as.matrix(A%*%m);s[as.matrix(A%*%missing)>0]<-NA_real_;s})
 fs<-lapply(seq_along(annual),function(t)cbind(features(annual[[t]][idx,,drop=FALSE],'center_'),features(sums[[t]],'region_')))
 exact_exposed<-vapply(seq_len(nrow(b)),function(k){j<-near[[k]];any(hav(pts$centroid_lat[idx[k]],pts$centroid_lon[idx[k]],rp$lat[j],rp$lon[j])<=rad)},logical(1))
 centroid_exposed<-vapply(z$events[[as.character(rad)]],function(v)any(v>=2010&v<=2019),logical(1))
 clean<- (is.na(b$first_pis_year)|b$first_pis_year>2019)&cv$incomplete_outcome_tracts==0&cv$unknown_timing_tracts==0&!centroid_exposed&!exact_exposed
 # Treated neighbors may have additional projects, including prior projects.
 # Unknown neighboring timing is flagged, not used to drop treated centers.
 eligibility[[as.character(rad)]]<-tibble(radius_km=rad,tract_id=b$tract_id,treated_complete=cv$incomplete_outcome_tracts==0,
   unknown_timing_neighbors=cv$unknown_timing_tracts,clean_control=clean,actual_coordinate_exposure=exact_exposed)
 for(g in 2011:2019) {
  X<-fs[[g-2010]]
  if(g>=2012){start<-max(2010,g-3);den<-g-1-start
   growth<-(fs[[g-2010]][,c('center_log_rac','center_log_wac','region_log_rac','region_log_wac')]-fs[[start-2009]][,c('center_log_rac','center_log_wac','region_log_rac','region_log_wac')])/den
   colnames(growth)<-paste0(colnames(growth),'_growth');X<-cbind(X,growth)
  }
  treated<-which(!is.na(b$first_pis_year)&b$first_pis_year==g&cv$incomplete_outcome_tracts==0)
  controls<-which(clean)
  good<-rowSums(!is.finite(X))==0; tr<-treated[good[treated]]; co<-controls[good[controls]]
  # Score estimated once per radius/cohort; same score used for county/state
  # comparison. One-to-one, greedy descending PS, no replacement within cohort.
  ids<-c(tr,co); d<-as.data.frame(X[ids,,drop=FALSE]); d$treatment<-c(rep(1,length(tr)),rep(0,length(co)))
  keep<-names(d)[vapply(d,function(v)sd(v)>1e-10,logical(1))];d<-d[,keep,drop=FALSE]
  fit<-glm(treatment~.,family=binomial(),data=d); stopifnot(fit$converged)
  ps<-rep(NA_real_,nrow(b));ps[ids]<-fitted(fit)
  # MatchIt's default logit distance is fitted probability, with standardized
  # caliper based on within-group pooled SD (not SD of the linear predictor).
  cal<-.2*sqrt((var(ps[tr])+var(ps[co]))/2)
  # Regularized pooled within-group covariance, fixed before matching.
  scale_x<-sqrt((apply(X[tr,,drop=FALSE],2,var)+apply(X[co,,drop=FALSE],2,var))/2)
  active<-is.finite(scale_x)&scale_x>1e-10
  xx<-sweep(X[,active,drop=FALSE],2,scale_x[active],'/')
  C<-(cov(xx[tr,,drop=FALSE])+cov(xx[co,,drop=FALSE]))/2
  eig<-eigen(C,symmetric=TRUE); invroot<-eig$vectors %*% diag(1/sqrt(pmax(eig$values,.01*max(eig$values))))
  transform_x<-xx%*%invroot
  models[[paste(rad,g)]]<-tibble(radius_km=rad,cohort=g,converged=fit$converged,score_min=min(ps[ids]),score_max=max(ps[ids]),caliper=cal)
  for(scope in c('county','state')) {
   used<-integer(); rows<-list(); reason<-list()
   for(k in tr[order(-ps[tr],b$tract_id[tr])]){
    cc<-co[if(scope=='county')b$county_id[co]==b$county_id[k] else state[co]==state[k]]
    cc<-cc[hav(pts$centroid_lat[idx[k]],pts$centroid_lon[idx[k]],pts$centroid_lat[idx[cc]],pts$centroid_lon[idx[cc]])>2*rad]
    n_geo<-length(cc);cc<-cc[abs(ps[cc]-ps[k])<=cal];n_cal<-length(cc);cc<-setdiff(cc,used)
    distance<-if(metric=='propensity')abs(ps[cc]-ps[k]) else rowSums(sweep(transform_x[cc,,drop=FALSE],2,transform_x[k,],'-')^2)
    chosen<-if(length(cc))cc[order(distance,abs(ps[cc]-ps[k]),b$tract_id[cc])][1] else NA_integer_
    reason[[length(reason)+1]]<-tibble(radius_km=rad,scope=scope,cohort=g,tract_id=b$tract_id[k],candidates=n_geo,within_caliper=n_cal,
     status=if(!is.na(chosen))'matched' else if(n_geo==0)'no_spatial_candidate' else if(n_cal==0)'outside_caliper' else 'candidate_already_used')
    if(is.na(chosen))next
    used<-c(used,chosen)
    rows[[length(rows)+1]]<-tibble(radius_km=rad,scope=scope,cohort=g,treated_index=k,control_index=chosen,treated_id=b$tract_id[k],control_id=b$tract_id[chosen],score_t=ps[k],score_c=ps[chosen],score_distance=abs(ps[k]-ps[chosen]))
   }
   pairs<-bind_rows(rows); allpairs[[paste(rad,g,scope)]]<-pairs
   eligibility[[paste(rad,g,scope)]]<-bind_rows(reason)
   audit[[paste(rad,g,scope)]]<-tibble(radius_km=rad,scope=scope,cohort=g,treated_raw=sum(b$first_pis_year==g,na.rm=TRUE),treated_region_complete=length(treated),treated_covariates_complete=length(tr),control_covariates_complete=length(co),matched=nrow(pairs))
   for(v in colnames(X)) {
    den<-sd(X[tr,v]); tt<-pairs$treated_index;ct<-pairs$control_index
    balance[[length(balance)+1]]<-tibble(radius_km=rad,scope=scope,cohort=g,covariate=v,n_matched=length(tt),
      treated_mean_before=mean(X[tr,v]),control_mean_before=mean(X[co,v]),
      treated_mean_after=mean(X[tt,v]),control_mean_after=mean(X[ct,v]),
      smd_before=(mean(X[tr,v])-mean(X[co,v]))/den,smd_after=(mean(X[tt,v])-mean(X[ct,v]))/den)
   }
   stopifnot(!anyDuplicated(pairs$control_id),all(is.na(b$first_pis_year[pairs$control_index])|b$first_pis_year[pairs$control_index]>2019))
   for(k in pairs$treated_index)for(period_name in c('first_year','through_2019')) {
    endpoint<-if(period_name=='first_year')g else 2019
    rr<-raw %>% filter(tract_id%in%pts$tract_id[mem[[k]]],known,pis>=g,pis<=endpoint)
    sizes[[length(sizes)+1]]<-tibble(radius_km=rad,scope=scope,cohort=g,treated_id=b$tract_id[k],period=period_name,
      projects=nrow(rr),units_observed=sum(rr$units[is.finite(rr$units)&rr$units>=0]),projects_missing_units=sum(!is.finite(rr$units)|rr$units<0))
   }
   message(rad,' km / ',g,' / ',scope,': ',nrow(pairs),' matches')
  }
 }
 saveRDS(sums,file.path(out,paste0('region_annual_sums_',rad,'km.rds')))
}
pairs<-bind_rows(allpairs);write_csv(pairs,file.path(out,'matched_pairs.csv'))
write_csv(bind_rows(audit),file.path(out,'sample_flow.csv'));write_csv(bind_rows(balance),file.path(out,'balance_by_cohort.csv'))
write_csv(bind_rows(sizes)%>%distinct(),file.path(out,'treated_housing_scale.csv'))
write_csv(bind_rows(eligibility),file.path(out,'eligibility_and_matching_status.csv'))
write_csv(bind_rows(models),file.path(out,'propensity_model_audit.csv'))
sumflow<-bind_rows(audit)%>%group_by(radius_km,scope)%>%summarise(across(c(treated_raw,treated_region_complete,treated_covariates_complete,matched),sum),.groups='drop')
write_csv(sumflow,file.path(out,'sample_summary.csv'));print(sumflow)
bal<-bind_rows(balance)%>%group_by(radius_km,scope,covariate)%>%summarise(smd_before=weighted.mean(smd_before,n_matched,na.rm=TRUE),mean_abs_smd_after=weighted.mean(abs(smd_after),n_matched,na.rm=TRUE),smd_after=weighted.mean(smd_after,n_matched,na.rm=TRUE),.groups='drop')
write_csv(bal,file.path(out,'balance_summary.csv'))
gg<-ggplot(bal,aes(abs(smd_before),reorder(covariate,abs(smd_before))))+geom_point(color='grey65')+geom_point(aes(x=abs(smd_after)),color='#215B88')+geom_vline(xintercept=.1,linetype=2,color='grey50')+facet_grid(scope~radius_km)+theme_bw(base_size=9)+labs(x='Absolute cohort-weighted standardized difference',y=NULL,caption='Grey: before; blue: after. Cohort-specific diagnostics are also exported.')
ggsave(file.path(out,'covariate_balance.png'),gg,width=13,height=10,dpi=160)
writeLines(c('PASS: controls are never treated or first treated after 2019; none have recorded 2010-2019 projects within the radius under centroid or available actual-coordinate screening.',
'PASS: every pair is within chosen geography, exceeds twice radius, meets propensity caliper; no control reuse within cohort.',
'Unknown-year neighboring treated projects are flagged, not excluded. Known-year additional treated-region projects allowed.',
'Unlocated projects with invalid tract identifiers cannot be screened; no claim of perfectly unexposed controls.',
'No estimates or significance tests: overlap-aware inference and pretrend checks are later stages.'),file.path(out,'VALIDATION.txt'))
writeLines(paste('Matching distance:',metric),file.path(out,'MATCHING_DISTANCE.txt'))
writeLines('COMPLETE',file.path(out,'COMPLETE.txt'))
