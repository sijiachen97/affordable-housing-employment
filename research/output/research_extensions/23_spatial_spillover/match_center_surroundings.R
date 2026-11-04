# Design-only refinement; no post-treatment effect estimates used.
suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);src<-a[1];prior<-a[2];out<-a[3];dir.create(out,recursive=TRUE,showWarnings=FALSE)
z<-readRDS(file.path(src,'neighborhood_cache.rds'));b<-z$base;p<-z$pts;idx<-match(b$tract_id,p$tract_id)
root<-'.'
vars<-c('rac_total','wac_total','seer_total_population','seer_nh_black','seer_nh_aian','seer_nh_api','seer_hispanic','seer_age_under_29','seer_age_55_plus','rac_earn_le_1250','rac_earn_ge_3333','wac_earn_le_1250','wac_earn_ge_3333')
panel<-read_csv(file.path(root,'data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE,col_select=all_of(c('tract_id','year',vars)))
el<-read_csv(file.path(prior,'eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control))
annual<-lapply(2010:2019,function(y){v<-panel%>%filter(year==y);as.matrix(v[match(b$tract_id,v$tract_id),vars])})
state<-substr(sprintf('%011.0f',b$tract_id),1,2)
hav<-function(k,j){q<-pi/180;2*6371.0088*asin(pmin(1,sqrt(sin((p$centroid_lat[idx[j]]-p$centroid_lat[idx[k]])*q/2)^2+cos(p$centroid_lat[idx[j]]*q)*cos(p$centroid_lat[idx[k]]*q)*sin((p$centroid_lon[idx[j]]-p$centroid_lon[idx[k]])*q/2)^2)))}
features<-function(m,prefix){pop<-m[,'seer_total_population'];rac<-m[,'rac_total'];wac<-m[,'wac_total']
 div<-function(x,d)ifelse(d>0,x/d,0)
 f<-cbind(log_pop=log(pmax(pop,1)),log_rac=log(pmax(rac,1)),log_wac=log(pmax(wac,1)),black=div(m[,'seer_nh_black'],pop),aian=div(m[,'seer_nh_aian'],pop),api=div(m[,'seer_nh_api'],pop),hispanic=div(m[,'seer_hispanic'],pop),age_0_24=div(m[,'seer_age_under_29'],pop),age_55plus=div(m[,'seer_age_55_plus'],pop),rac_low=div(m[,'rac_earn_le_1250'],rac),rac_high=div(m[,'rac_earn_ge_3333'],rac),wac_low=div(m[,'wac_earn_le_1250'],wac),wac_high=div(m[,'wac_earn_ge_3333'],wac),zero_pop=as.numeric(pop==0),zero_rac=as.numeric(rac==0),zero_wac=as.numeric(wac==0))
 colnames(f)<-paste0(prefix,colnames(f));f}
PA<-BA<-FL<-RE<-MO<-list()
# Thresholds fixed before inspecting matches: each core difference <= .5 or 1
# pretreatment treated SD; score caliper .2 pooled within-group score SD.
writeLines(c('Same state; full-panel control exposure rules inherited from audited Stage B.', 'Center and surrounding area exclude overlap by construction; empty surroundings excluded from this spillover sample, counted separately.', 'Two prespecified core calipers: 0.5 and 1.0 treated SD. PS caliper: 0.2 pooled within-group SD.', 'Core: center/surrounding log RAC,WAC,population and pre RAC/WAC growth. Rank candidates by mean squared standardized core distance + .25 * mean squared remaining covariate distance.', 'No replacement within cohort; reuse across cohorts allowed. All predictors <=g-1. 2011 has no growth predictors.'),file.path(out,'DESIGN.txt'))
for(r in c(3,5,10)){
 cv<-el%>%filter(radius_km==r);stopifnot(identical(cv$tract_id,b$tract_id))
 sums<-readRDS(file.path(prior,paste0('region_annual_sums_',r,'km.rds')))
 surround<-lapply(seq_along(sums),function(t)sums[[t]]-annual[[t]])
 for(t in 1:10)stopifnot(all(surround[[t]]>=-1e-8,na.rm=TRUE))
 fs<-lapply(1:10,function(t)cbind(features(annual[[t]],'center_'),features(surround[[t]],'surround_')))
 nonempty<-lengths(z$members[[as.character(r)]])>1
 for(g in 2011:2019){
  X<-fs[[g-2010]]
  if(g>=2012){start<-max(2010,g-3);v<-c('center_log_rac','center_log_wac','surround_log_rac','surround_log_wac');gr<-(X[,v]-fs[[start-2009]][,v])/(g-1-start);colnames(gr)<-paste0(v,'_growth');X<-cbind(X,gr)}
  treated<-which(!is.na(b$first_pis_year)&b$first_pis_year==g)
  complete<-treated[cv$treated_complete[treated]];region<-complete[nonempty[complete]]
  good<-rowSums(!is.finite(X))==0;tr<-region[good[region]];co<-which(cv$clean_control&nonempty&good)
  ids<-c(tr,co);d<-as.data.frame(X[ids,,drop=FALSE]);d$treatment<-c(rep(1,length(tr)),rep(0,length(co)))
  active<-vapply(d,function(v)sd(v)>1e-10,logical(1));fit<-glm(treatment~.,data=d[,active,drop=FALSE],family=binomial());stopifnot(fit$converged)
  ps<-rep(NA_real_,nrow(b));ps[ids]<-fitted(fit);pc<-.2*sqrt((var(ps[tr])+var(ps[co]))/2)
  sdT<-apply(X[tr,,drop=FALSE],2,sd);active<-is.finite(sdT)&sdT>1e-10
  Z<-sweep(X[,active,drop=FALSE],2,sdT[active],'/');core<-grepl('log_',colnames(Z));other<-!core
  MO[[paste(r,g)]]<-tibble(radius_km=r,cohort=g,ps_caliper=pc,converged=fit$converged)
  for(cap in c(.5,1)){
   used<-integer();rows<-list()
   for(k in tr[order(-ps[tr],b$tract_id[tr])]){
    cc<-co[state[co]==state[k]];cc<-cc[hav(k,cc)>2*r];ngeo<-length(cc)
    cc<-cc[abs(ps[cc]-ps[k])<=pc];nps<-length(cc)
    if(length(cc)){dd<-abs(sweep(Z[cc,core,drop=FALSE],2,Z[k,core],'-'));cc<-cc[apply(dd,1,max)<=cap+1e-12]}
    ncore<-length(cc);cc<-setdiff(cc,used)
    if(length(cc)){
     delta<-sweep(Z[cc,,drop=FALSE],2,Z[k,],'-');dist<-rowMeans(delta[,core,drop=FALSE]^2)+.25*rowMeans(delta[,other,drop=FALSE]^2)
     j<-cc[order(dist,abs(ps[cc]-ps[k]),b$tract_id[cc])][1];used<-c(used,j)
     rows[[length(rows)+1]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,treated_index=k,control_index=j,treated_id=b$tract_id[k],control_id=b$tract_id[j],score_distance=abs(ps[k]-ps[j]),max_core_distance=max(abs(Z[k,core]-Z[j,core])))
     stopifnot(length(intersect(z$members[[as.character(r)]][[k]],z$members[[as.character(r)]][[j]]))==0,cv$clean_control[j])
    }
    RE[[length(RE)+1]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,tract_id=b$tract_id[k],status=if(length(cc))'matched' else if(ngeo==0)'no_geographic_candidate' else if(nps==0)'outside_ps_caliper' else if(ncore==0)'outside_core_caliper' else 'already_used')
   }
   pairs<-bind_rows(rows);PA[[paste(r,g,cap)]]<-pairs
   FL[[paste(r,g,cap)]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,original=length(treated),complete=length(complete),with_neighbors=length(region),covariates_complete=length(tr),matched=nrow(pairs))
   for(v in colnames(X)){
    tt<-pairs$treated_index;ct<-pairs$control_index;den<-sdT[v]
    BA[[length(BA)+1]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,covariate=v,is_core=grepl('log_',v),n_matched=length(tt),smd_before=if(den>1e-10)(mean(X[tr,v])-mean(X[co,v]))/den else NA_real_,smd_after=if(den>1e-10)(mean(X[tt,v])-mean(X[ct,v]))/den else NA_real_)
   }
   stopifnot(!anyDuplicated(pairs$control_id),all(pairs$max_core_distance<=cap+1e-12),all(pairs$score_distance<=pc+1e-12))
   message(r,' km cohort ',g,' cap ',cap,': ',nrow(pairs),' pairs')
  }
 }
}
write_csv(bind_rows(PA),file.path(out,'matched_pairs.csv'));write_csv(bind_rows(FL),file.path(out,'sample_flow.csv'));write_csv(bind_rows(BA),file.path(out,'balance_by_cohort.csv'));write_csv(bind_rows(RE),file.path(out,'matching_status.csv'));write_csv(bind_rows(MO),file.path(out,'propensity_audit.csv'))
flow<-bind_rows(FL)%>%group_by(radius_km,core_caliper)%>%summarise(across(c(original,complete,with_neighbors,covariates_complete,matched),sum),.groups='drop');write_csv(flow,file.path(out,'sample_summary.csv'));print(flow)
bs<-bind_rows(BA)%>%filter(is.finite(smd_after))%>%group_by(radius_km,core_caliper,is_core)%>%summarise(mean_abs_smd=weighted.mean(abs(smd_after),n_matched),max_abs_smd=max(abs(smd_after)),share_over_point1=mean(abs(smd_after)>.1),.groups='drop');write_csv(bs,file.path(out,'balance_summary.csv'));print(bs,n=20)
writeLines(c('PASS: all predictors g-1 or earlier; same-state, >2r distance, exact non-overlap, clean controls, propensity and core calipers checked for all pairs.', 'PASS: no within-cohort control reuse; regional sums minus center nonnegative.', 'Treatment and control eligibility inherited from validated Stage A/B; never-treated retained.', 'No effect estimates or significance-driven design selection.'),file.path(out,'VALIDATION.txt'))
