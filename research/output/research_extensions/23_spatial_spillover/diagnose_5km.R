# Spatial-region effects on fixed Stage C pairs; no rematching.
# Spatial covariance: full-time center-score aggregation + PSD Wendland kernel.
suppressPackageStartupMessages({library(tidyverse);library(fixest);library(Matrix)})
a<-commandArgs(TRUE);root<-a[1];out<-a[2];dir.create(out,recursive=TRUE,showWarnings=FALSE)
setFixest_nthreads(2)
z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base;pts<-z$pts
pairs<-read_csv(file.path(root,'stage_c/matched_pairs.csv'),show_col_types=FALSE)%>%filter(core_caliper==1)
stopifnot(all((pairs%>%count(radius_km))$n==c(1043,1014,733)))
project<-'.'
p<-read_csv(file.path(project,'data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE,col_select=c(tract_id,year,rac_total,wac_total,seer_total_population))
annual<-lapply(2010:2019,function(yr){v<-p%>%filter(year==yr);as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')])})
common35<-intersect(pairs$treated_id[pairs$radius_km==3],pairs$treated_id[pairs$radius_km==5])
write_csv(tibble(tract_id=common35),file.path(out,'common_treated_3_5.csv'))
writeLines(c('Frozen Stage C pairs, core_caliper = 1; no rematching.',
'Outcomes: RAC, WAC, population levels and log(max(count,1)), RAC/population. Center, surroundings excluding center, cumulative region.',
'FE: original geographic center and matched pair x calendar year; unweighted pair-row estimation; duplicated controls retained and covariance grouped by original center.',
'Standard DID uses focal treated x post. Sun-Abraham uses center cohort, never/future control sentinel 9999, ref.p=c(-1,.F), matching paper convention.',
'ATT: supported post-treatment cohort-event cells weighted by treated observation counts via fixest aggregation. Standard DID coefficient may use different implicit weights.',
'Primary covariance: full-time spatial HAC, 50 km bandwidth. Sensitivity 25/100 km and unadjusted original-center cluster.',
'Spatial kernel on 3D Earth chord distance: K=(1-d/h)^4*(1+4*d/h) for d<h, zero otherwise. Wendland positive-semidefinite kernel.',
'All row influence contributions for one original center are summed across every year and repeated cohort before spatial covariance. This includes cross-location, cross-year score products.',
'Asymptotic normal 95% pointwise intervals; HC0-style covariance without FE degrees-of-freedom multiplier, conditional on fixed matching. No claim that matching uncertainty is fully propagated.',
'Bandwidths fixed before outcomes: all exceed twice the largest 10km radius. Correlation beyond bandwidth is assumed negligible; overlapping regions are weighted by center distance, not assumed independent.',
'Common-treated 3/5km sensitivity retains each radius original controls; controls can differ across radii.'),file.path(out,'METHODS.txt'))
# Build and project covariance onto ATT/event contrasts, avoiding expensive full
# p x p covariance repetition. Kernel is applied after full-time aggregation.
make_kernels<-function(ids){
 j<-match(ids,pts$tract_id);lat<-pts$centroid_lat[j]*pi/180;lon<-pts$centroid_lon[j]*pi/180
 xyz<-6371.0088*cbind(cos(lat)*cos(lon),cos(lat)*sin(lon),sin(lat))
 ds<-as.matrix(dist(xyz));ans<-list(center_cluster=Diagonal(length(ids)))
 for(h in c(25,50,100)){u<-ds/h;K<-pmax(1-u,0)^4*(1+4*u);diag(K)<-1;ans[[paste0('spatial_',h,'km')]]<-Matrix(K,sparse=TRUE)}
 ans
}
wald_test<-function(beta,V){ev<-eigen((V+t(V))/2,symmetric=TRUE);keep<-ev$values>max(ev$values)*1e-8
 if(!any(keep))return(c(stat=NA_real_,df=0,p=NA_real_))
 q<-sum((crossprod(ev$vectors[,keep,drop=FALSE],beta))^2/ev$values[keep]);c(stat=q,df=sum(keep),p=pchisq(q,sum(keep),lower.tail=FALSE))}
# Cohort attribution on the frozen 5km pairs, no model-selection exclusions.
r<-5;pp<-pairs%>%filter(radius_km==5)%>%mutate(pair_id=row_number())
units<-bind_rows(pp%>%transmute(pair_id,cohort,center_id=treated_id,center_index=treated_index,focal=1L),pp%>%transmute(pair_id,cohort,center_id=control_id,center_index=control_index,focal=0L))%>%arrange(pair_id,desc(focal))
d<-units[rep(seq_len(nrow(units)),each=10),];d$year<-rep(2010:2019,nrow(units));d$post<-as.integer(d$focal==1&d$year>=d$cohort);d$cohort_sa<-ifelse(d$focal==1,d$cohort,9999);d$center_fe<-as.integer(factor(d$center_id));d$pair_year<-interaction(d$pair_id,d$year,drop=TRUE)
ids<-sort(unique(d$center_id));ord<-match(d$center_id,ids);K<-make_kernels(ids)$spatial_50km
sums<-readRDS(file.path(root,'stage_b/region_annual_sums_5km.rds'))
ct<-do.call(rbind,lapply(seq_len(nrow(units)),function(k)do.call(rbind,lapply(annual,function(v)v[units$center_index[k],]))))
cu<-do.call(rbind,lapply(seq_len(nrow(units)),function(k)do.call(rbind,lapply(sums,function(v)v[units$center_index[k],c('rac_total','wac_total','seer_total_population')]))))
mat<-cu-ct;d$rac<-mat[,1];d$wac<-mat[,2];d$population<-mat[,3];d$log_rac<-log(pmax(d$rac,1));d$log_wac<-log(pmax(d$wac,1));d$log_population<-log(pmax(d$population,1));d$emp_pop_ratio<-d$rac/d$population
coefout<-aggout<-tests<-rawout<-weightout<-compare<-loo<-list()
for(y in c('log_rac','rac','log_wac','wac','log_population','population','emp_pop_ratio')){
 f<-feols(as.formula(paste(y,'~ sunab(cohort_sa,year,ref.p=c(-1,.F)) | center_fe + pair_year')),d,notes=FALSE)
 mm<-model.matrix(f);bn<-names(f$coefficients);mm<-mm[,bn,drop=FALSE]
 ev<-as.numeric(sub('^year::(-?[0-9]+):.*','\\1',bn));co<-as.numeric(sub('.*:cohort::','',bn));stopifnot(!anyNA(ev),!anyNA(co))
 bread<-solve(f$hessian);U<-rowsum(f$scores%*%bread,ord,reorder=TRUE);V<-as.matrix(crossprod(U,K%*%U));be<-f$coefficients;se<-sqrt(diag(V));counts<-colSums(sign(mm))
 ctab<-tibble(outcome=y,term=bn,cohort=co,event=ev,estimate=be,std_error=se,p_value=2*pnorm(-abs(be/se)),pairs=counts)
 ctab<-ctab%>%group_by(event)%>%mutate(event_weight=pairs/sum(pairs),contribution=estimate*event_weight)%>%ungroup();coefout[[y]]<-ctab
 for(g in 2011:2019){jj<-which(co==g&ev>=-5&ev<=-2);if(length(jj)){
  w<-wald_test(be[jj],V[jj,jj,drop=FALSE]);tests[[paste(y,g)]]<-tibble(outcome=y,cohort=g,pairs=sum(pp$cohort==g),leads_tested=paste(ev[jj],collapse=','),p_value=w['p'],df=w['df'])}}
 for(composition in c('varying','fixed_2015_2019'))for(t in -5:-2){
  jj<-which(ev==t&(composition=='varying'|co>=2015));ww<-counts[jj]/sum(counts[jj]);est<-sum(ww*be[jj]);ss<-sqrt(drop(t(ww)%*%V[jj,jj,drop=FALSE]%*%ww))
  aggout[[length(aggout)+1]]<-tibble(outcome=y,composition=composition,event=t,estimate=est,std_error=ss,contributing_pairs=sum(counts[jj]))
  if(composition=='varying')for(g in sort(unique(co[jj]))){kk<-jj[co[jj]!=g];w<-counts[kk]/sum(counts[kk]);loo[[length(loo)+1]]<-tibble(outcome=y,event=t,omitted_from_aggregation=g,estimate_without=sum(w*be[kk]),original=est)}
 }
 # Exact decomposition of standard DID coefficient into estimated SA cells.
 xp<-resid(feols(post~1|center_fe+pair_year,d,notes=FALSE));den<-sum(xp^2);weights<-drop(crossprod(xp,mm))/den
 std<-feols(as.formula(paste(y,'~ post | center_fe+pair_year')),d,notes=FALSE)$coefficients[1]
 reconstructed<-sum(weights*be);stopifnot(abs(std-reconstructed)<1e-6)
 sa<-aggregate(f,'ATT')[1,1]
 weightout[[y]]<-ctab%>%mutate(standard_did_weight=weights,standard_did_contribution=weights*estimate,sa_att_weight=if_else(event>=0,pairs/sum(pairs[event>=0]),0))
 compare[[y]]<-tibble(outcome=y,standard_did=std,reconstructed=reconstructed,sun_abraham_att=sa,standard_pre_component=sum(weights[ev<0]*be[ev<0]),standard_post_component=sum(weights[ev>=0]*be[ev>=0]),post_weight_sum=sum(weights[ev>=0]),negative_post_weights=sum(weights[ev>=0]< -1e-10))
 # Raw matched T-C gap changes relative to g-1, for every cohort and year.
 raw<-d%>%mutate(value=.data[[y]])%>%select(pair_id,cohort,year,focal,value)%>%pivot_wider(names_from=focal,values_from=value,names_prefix='arm')%>%mutate(gap=arm1-arm0,event=year-cohort)%>%group_by(pair_id)%>%mutate(gap_change=gap-gap[event==-1])%>%ungroup()%>%group_by(cohort,event)%>%summarise(mean_gap_change=mean(gap_change),pairs=n(),.groups='drop')%>%mutate(outcome=y)
 rawout[[y]]<-raw
}
write_csv(bind_rows(coefout),file.path(out,'cohort_event_coefficients.csv'));write_csv(bind_rows(aggout),file.path(out,'fixed_composition_pretrends.csv'));write_csv(bind_rows(tests),file.path(out,'cohort_pretrend_tests.csv'));write_csv(bind_rows(rawout),file.path(out,'raw_pair_gap_changes.csv'));write_csv(bind_rows(weightout),file.path(out,'did_weight_decomposition.csv'));write_csv(bind_rows(compare),file.path(out,'did_vs_sa_explained.csv'));write_csv(bind_rows(loo),file.path(out,'leave_cohort_out_aggregation.csv'))
cc<-bind_rows(coefout)%>%filter(outcome=='log_rac',between(event,-5,5))
ref<-cc%>%distinct(outcome,cohort,pairs)%>%mutate(event=-1,estimate=0,std_error=0)
fig<-bind_rows(cc,ref)%>%ggplot(aes(event,estimate))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.1,color='#CC7722')+geom_line(color='#CC7722')+geom_point(color='#CC7722',size=1.2)+facet_wrap(~cohort,ncol=3)+scale_x_continuous(breaks=seq(-5,5,2))+theme_bw()+labs(title='5 km surroundings: log RAC by treatment cohort',subtitle='Frozen matched pairs; Sun-Abraham cohort coefficients, 50 km spatial HAC',x='Years relative to center first placement',y='Log points')
ggsave(file.path(out,'surrounding_log_rac_by_cohort.png'),fig,width=13,height=10,dpi=180)
f<-bind_rows(aggout)%>%filter(outcome=='log_rac')%>%ggplot(aes(event,estimate,color=composition))+geom_hline(yintercept=0,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.1,position=position_dodge(.12))+geom_line()+geom_point()+theme_bw()+labs(title='5 km surroundings: does changing cohort composition explain the pretrend?',x='Event year',y='Log RAC coefficient',color='Cohorts')
ggsave(file.path(out,'fixed_composition_pretrends.png'),f,width=9,height=5,dpi=180)
writeLines('PASS: weighted cohort coefficients reproduce stage D aggregation; standard DID reconstructed exactly from raw Sun-Abraham coefficients using residualized post-regressor weights. No pairs or source results changed.',file.path(out,'VALIDATION.txt'))
# Reference-period sensitivity, not a replacement for the saved Stage D model.
y<-'log_rac';f1<-feols(log_rac~sunab(cohort_sa,year,ref.p=-1)|center_fe+pair_year,d,notes=FALSE)
cc<-names(f1$coefficients);ee<-as.numeric(sub('^year::(-?[0-9]+):.*','\\1',cc));ct<-colSums(sign(model.matrix(f1)[,cc,drop=FALSE]));u<-rowsum(f1$scores%*%solve(f1$hessian),ord,reorder=TRUE);vv<-as.matrix(crossprod(u,K%*%u))
alt<-bind_rows(lapply(-5:5,function(t){jj<-which(ee==t);if(!length(jj))return(NULL);w<-ct[jj]/sum(ct[jj]);tibble(event=t,estimate=sum(w*f1$coefficients[jj]),std_error=sqrt(drop(t(w)%*%vv[jj,jj,drop=FALSE]%*%w)))}))
write_csv(alt,file.path(out,'single_reference_log_rac.csv'))
# Audit neighboring placement before center's g; retain all original pairs.
raw<-read_csv(file.path(project,'data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv'),col_types=cols(.default=col_character()))%>%filter(str_trim(type)=='1')%>%mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)))
exp<-bind_rows(lapply(seq_len(nrow(pp)),function(k){v<-pp[k,];members<-pts$tract_id[z$members[['5']][[v$treated_index]]];rr<-raw%>%filter(tract_id%in%setdiff(members,v$treated_id),pis>=v$cohort-5,pis<v$cohort);tibble(pair_id=v$pair_id,cohort=v$cohort,treated_id=v$treated_id,prior_surrounding_projects=nrow(rr))}))
write_csv(exp,file.path(out,'prior_surrounding_project_exposure.csv'))
write_csv(exp%>%group_by(cohort)%>%summarise(pairs=n(),with_prior_projects=sum(prior_surrounding_projects>0),mean_prior_projects=mean(prior_surrounding_projects),.groups='drop'),file.path(out,'prior_exposure_by_cohort.csv'))
rawgap<-d%>%select(pair_id,cohort,year,focal,log_rac)%>%pivot_wider(names_from=focal,values_from=log_rac,names_prefix='arm')%>%mutate(gap=arm1-arm0,event=year-cohort)%>%group_by(pair_id)%>%mutate(change=gap-gap[event==-1])%>%ungroup()%>%left_join(exp%>%select(pair_id,prior_surrounding_projects),by='pair_id')
write_csv(rawgap%>%filter(cohort>=2015,between(event,-5,-1))%>%mutate(prior_exposure=if_else(prior_surrounding_projects>0,'prior_projects','none_recorded'))%>%group_by(prior_exposure,event)%>%summarise(pairs=n(),mean_gap_change=mean(change),.groups='drop'),file.path(out,'fixed_cohort_raw_pretrend_by_prior_exposure.csv'))
# Explicit reproduction checks against original Stage D coefficients.
old<-read_csv(file.path(root,'stage_d/event_study.csv'),show_col_types=FALSE)%>%filter(sample=='radius_specific',radius_km==5,component=='surroundings',covariance=='spatial_50km',between(event,-5,-2))
new<-bind_rows(aggout)%>%filter(composition=='varying')%>%inner_join(old%>%select(outcome,event,original=estimate),by=c('outcome','event'))
stopifnot(nrow(new)==28,max(abs(new$estimate-new$original))<1e-8)
write('PASS: all 28 displayed aggregate pre-coefficients for seven outcomes reproduce Stage D exactly.',file=file.path(out,'VALIDATION.txt'),append=TRUE)
writeLines(c('Diagnostic only: fixed Stage C 5km 1-SD pairs; no rematching or cohort exclusions.', 'Replicates Stage D with full-time 50km spatial HAC. Checks cohort contributions, fixed composition, raw pair gaps, reference-period sensitivity, prior surrounding projects, and standard-DID weight decomposition.', 'Original Stage D estimates unchanged. See RESULTS_CN.md.'),file.path(out,'METHODS.txt'))
