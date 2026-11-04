# Design-only refinement; no post-treatment effect estimates used.
suppressPackageStartupMessages(library(tidyverse))
options(warn=1)
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
# Audit all TYPE=1 records, including tracts outside the estimation panel.
raw<-read_csv(file.path(root,'data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv'),col_types=cols(.default=col_character()))%>%filter(str_trim(type)=='1')%>%mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)))
known<-is.finite(raw$pis)&!raw$pis%in%c(8888,9999)
ct<-table(raw$tract_id[known&raw$pis>=2010&raw$pis<=2019]);cthist<-table(raw$tract_id[known&raw$pis<2010])
count_for<-function(tb){ans<-as.numeric(tb[as.character(p$tract_id)]);replace_na(ans,0)}
project_counts<-count_for(ct);historical_counts<-count_for(cthist)
ISO<-list()
PA<-BA<-FL<-RE<-MO<-OB<-list()
oldpairs<-read_csv(file.path(dirname(src),'stage_c/matched_pairs.csv'),show_col_types=FALSE)%>%filter(core_caliper==1)
# Thresholds retained from prior design: each core difference <= 1
# pretreatment treated SD; score caliper .2 pooled within-group score SD.
writeLines(c('Stage I: county matching and no 2010-2019 new construction in surrounding tracts; population log growth and RAC/WAC absolute annual change added in center and surroundings.', 'All 2011-2019 cohorts. 2011 levels only; 2012 recent 2010:2011 change; 2013 onward recent g-3:g-1 annual change; 2015 onward also g-5:g-3 annual change.', 'Same county, treated surroundings have no known 2010-2019 TYPE=1 placement and no unknown timing; historical pre-2010 projects allowed. Center subsequent projects allowed. Clean controls, center distance >2r, actual member non-overlap, no within-cohort control reuse, score caliper .2 pooled SD and each core variable <=1 treated SD unchanged.', 'All new growth variables enter propensity, hard core caliper and distance ranking. No raw level covariates added beyond existing log levels. No winsorization or outcome-based tuning.', 'No predictors dated g or later. Matching is a sensitivity design, not independent confirmation of parallel trends.'),file.path(out,'DESIGN.txt'))
for(r in c(3,5,10)){
 cv<-el%>%filter(radius_km==r);stopifnot(identical(cv$tract_id,b$tract_id))
 sums<-readRDS(file.path(prior,paste0('region_annual_sums_',r,'km.rds')))
 surround<-lapply(seq_along(sums),function(t)sums[[t]]-annual[[t]])
 for(t in 1:10)stopifnot(all(surround[[t]]>=-1e-8,na.rm=TRUE))
 fs<-lapply(1:10,function(t)cbind(features(annual[[t]],'center_'),features(surround[[t]],'surround_')))
 nonempty<-lengths(z$members[[as.character(r)]])>1
 neighbor_ids<-lapply(seq_along(z$members[[as.character(r)]]),function(k)setdiff(z$members[[as.character(r)]][[k]],idx[k]))
 nproj<-vapply(neighbor_ids,function(j)sum(project_counts[j]),numeric(1));nunknown<-vapply(neighbor_ids,function(j)sum(z$unknown[j]),numeric(1));nhist<-vapply(neighbor_ids,function(j)sum(historical_counts[j]),numeric(1))
 isolated<-nproj==0&nunknown==0
 ISO[[as.character(r)]]<-tibble(radius_km=r,tract_id=b$tract_id,cohort=b$first_pis_year,complete=cv$treated_complete,nonempty=nonempty,neighbor_projects_2010_2019=nproj,neighbor_unknown_tracts=nunknown,historical_neighbor_projects=nhist,isolated=isolated)
 for(g in 2011:2019){
  X<-fs[[g-2010]]
  growth_block<-function(t0,t1,suffix){
   v<-c('center_log_rac','center_log_wac','surround_log_rac','surround_log_wac','center_log_pop','surround_log_pop')
   lg<-(fs[[t1-2009]][,v]-fs[[t0-2009]][,v])/(t1-t0);colnames(lg)<-paste0(v,suffix)
   raw<-function(t)cbind(annual[[t-2009]][,c('rac_total','wac_total')],surround[[t-2009]][,c('rac_total','wac_total')])
   lev<-(raw(t1)-raw(t0))/(t1-t0);colnames(lev)<-paste0(c('center_rac','center_wac','surround_rac','surround_wac'),'_absolute',suffix)
   cbind(lg,lev)
  }
  if(g>=2012)X<-cbind(X,growth_block(max(2010,g-3),g-1,'_growth'))
  if(g>=2015)X<-cbind(X,growth_block(g-5,g-3,'_early_growth'))
  treated<-which(!is.na(b$first_pis_year)&b$first_pis_year==g)
  complete<-treated[cv$treated_complete[treated]];nonempty_region<-complete[nonempty[complete]];region<-nonempty_region[isolated[nonempty_region]]
  good<-rowSums(!is.finite(X))==0;tr<-region[good[region]];co<-which(cv$clean_control&nonempty&good)
  ids<-c(tr,co);d<-as.data.frame(X[ids,,drop=FALSE]);d$treatment<-c(rep(1,length(tr)),rep(0,length(co)))
  active<-vapply(d,function(v)sd(v)>1e-10,logical(1));fit<-glm(treatment~.,data=d[,active,drop=FALSE],family=binomial());stopifnot(fit$converged)
  ps<-rep(NA_real_,nrow(b));ps[ids]<-fitted(fit);pc<-.2*sqrt((var(ps[tr])+var(ps[co]))/2)
  sdT<-apply(X[tr,,drop=FALSE],2,sd);active<-is.finite(sdT)&sdT>1e-10
  Z<-sweep(X[,active,drop=FALSE],2,sdT[active],'/');core<-grepl('log_|_absolute',colnames(Z));other<-!core
  MO[[paste(r,g)]]<-tibble(radius_km=r,cohort=g,ps_caliper=pc,converged=fit$converged)
  old<-oldpairs%>%filter(radius_km==r,cohort==g)
  for(nm in colnames(X)){den<-sdT[nm];OB[[length(OB)+1]]<-tibble(radius_km=r,cohort=g,covariate=nm,n_matched=nrow(old),smd_after=if(den>1e-10)(mean(X[old$treated_index,nm])-mean(X[old$control_index,nm]))/den else NA_real_)}
  for(cap in 1){
   used<-integer();rows<-list()
   for(k in tr[order(-ps[tr],b$tract_id[tr])]){
    cc<-co[b$county_id[co]==b$county_id[k]];cc<-cc[hav(k,cc)>2*r];ngeo<-length(cc)
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
   pairs<-if(length(rows))bind_rows(rows) else oldpairs[0,];PA[[paste(r,g,cap)]]<-pairs
   FL[[paste(r,g,cap)]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,original=length(treated),complete=length(complete),with_neighbors=length(nonempty_region),isolated_neighbors=length(region),covariates_complete=length(tr),matched=nrow(pairs))
   for(v in colnames(X)){
    tt<-pairs$treated_index;ct<-pairs$control_index;den<-sdT[v]
    BA[[length(BA)+1]]<-tibble(radius_km=r,core_caliper=cap,cohort=g,covariate=v,is_core=grepl('log_|_absolute',v),n_matched=length(tt),smd_before=if(den>1e-10)(mean(X[tr,v])-mean(X[co,v]))/den else NA_real_,smd_after=if(den>1e-10)(mean(X[tt,v])-mean(X[ct,v]))/den else NA_real_)
   }
   stopifnot(!anyDuplicated(pairs$control_id),all(pairs$max_core_distance<=cap+1e-12),all(pairs$score_distance<=pc+1e-12))
   message(r,' km cohort ',g,' cap ',cap,': ',nrow(pairs),' pairs')
  }
 }
}
write_csv(bind_rows(PA),file.path(out,'matched_pairs.csv'));write_csv(bind_rows(FL),file.path(out,'sample_flow.csv'));write_csv(bind_rows(BA),file.path(out,'balance_by_cohort.csv'));write_csv(bind_rows(RE),file.path(out,'matching_status.csv'));write_csv(bind_rows(MO),file.path(out,'propensity_audit.csv'))
flow<-bind_rows(FL)%>%group_by(radius_km,core_caliper)%>%summarise(across(c(original,complete,with_neighbors,isolated_neighbors,covariates_complete,matched),sum),.groups='drop');write_csv(flow,file.path(out,'sample_summary.csv'));print(flow)
bs<-bind_rows(BA)%>%filter(is.finite(smd_after))%>%group_by(radius_km,core_caliper,is_core)%>%summarise(mean_abs_smd=weighted.mean(abs(smd_after),n_matched),max_abs_smd=max(abs(smd_after)),share_over_point1=mean(abs(smd_after)>.1),.groups='drop');write_csv(bs,file.path(out,'balance_summary.csv'));print(bs,n=20)
writeLines(c('PASS: all predictors g-1 or earlier; same-county, >2r distance, exact non-overlap, clean controls, propensity and core calipers checked for all pairs.', 'PASS: no within-cohort control reuse; regional sums minus center nonnegative.', 'Treatment and control eligibility inherited from validated Stage A/B; never-treated retained.', 'No effect estimates or significance-driven design selection.'),file.path(out,'VALIDATION.txt'))

write_csv(bind_rows(OB),file.path(out,'old_pairs_balance_on_expanded_covariates.csv'))

write_csv(bind_rows(ISO)%>%filter(cohort%in%2011:2019),file.path(out,'treated_surroundings_audit.csv'))
