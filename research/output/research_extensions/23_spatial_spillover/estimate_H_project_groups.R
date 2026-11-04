# Spatial-region effects on fixed Stage H pairs; matching completed separately.
# Spatial covariance: full-time center-score aggregation + PSD Wendland kernel.
suppressPackageStartupMessages({library(tidyverse);library(fixest);library(Matrix)})
a<-commandArgs(TRUE);root<-a[1];out<-a[2];dir.create(out,recursive=TRUE,showWarnings=FALSE)
setFixest_nthreads(2)
z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base;pts<-z$pts
oldpairs<-read_csv(file.path(root,'stage_h/matching/matched_pairs.csv'),show_col_types=FALSE)%>%filter(core_caliper==1)
isolation<-read_csv(file.path(root,'stage_j/matching/treated_surroundings_audit.csv'),show_col_types=FALSE)
stopifnot(!anyDuplicated(isolation[c('radius_km','tract_id','cohort')]))
audit<-oldpairs%>%left_join(isolation%>%select(radius_km,tract_id,cohort,neighbor_projects_2010_2019,neighbor_unknown_tracts,isolated),by=c('radius_km','treated_id'='tract_id','cohort'))
stopifnot(!anyNA(audit$isolated))
audit<-audit%>%mutate(project_group=case_when(neighbor_unknown_tracts>0~'unknown',neighbor_projects_2010_2019>0~'with_projects',TRUE~'no_projects'))
write_csv(audit,file.path(out,'H_group_assignment.csv'))
write_csv(audit%>%count(radius_km,project_group,name='pairs'),file.path(out,'sample_summary.csv'))
cohort_counts<-audit%>%filter(project_group!='unknown')%>%count(radius_km,cohort,project_group,name='pairs')
stopifnot(all((cohort_counts%>%count(radius_km,cohort))$n==2))
write_csv(cohort_counts,file.path(out,'cohort_counts.csv'))
target_cohorts<-cohort_counts%>%group_by(radius_km,cohort)%>%summarise(target_n=sum(pairs),.groups='drop')
newpairs<-audit%>%filter(project_group!='unknown')
write_csv(newpairs,file.path(out,'combined_matched_pairs.csv'))
WEIGHTS<-CELLS<-list()
project<-'.'
p<-read_csv(file.path(project,'data_panels/2010_2019_did_panel_with_seer.csv'),show_col_types=FALSE,col_select=c(tract_id,year,rac_total,wac_total,seer_total_population))
annual<-lapply(2010:2019,function(yr){v<-p%>%filter(year==yr);as.matrix(v[match(b$tract_id,v$tract_id),c('rac_total','wac_total','seer_total_population')])})
writeLines(c('Stage M: split H into known with/without surrounding TYPE=1 placements in 2010-2019. Any unknown neighboring timing goes to separate excluded category. Original H controls retained.', 'Common target cohort counts equal pooled counts of both known groups within radius. Post-cell weights proportional to pooled cohort count, normalized over common estimable g,event>=0 cells. Event weights same pooled counts normalized within each event.', 'Each group estimated separately with original-center and pair-year FE and sunab reference c(-1,.F). Group differences use joint spatial covariance, including shared controls and spatial dependence.', 'This compares development environments, not the causal contribution of neighboring projects. Some neighboring projects predate center placement; group definition uses entire 2010-2019 window.'),file.path(out,'METHODS.txt'))
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
ATT<-ES<-PRE<-AUD<-VAL<-list();N<-0
for(sample in c('no_projects','with_projects'))for(r in c(3,5,10)){
 pp<-newpairs%>%filter(radius_km==r,project_group==sample)
 pp<-pp%>%mutate(pair_id=row_number())
 units<-bind_rows(pp%>%transmute(pair_id,cohort,center_id=treated_id,center_index=treated_index,focal=1L),pp%>%transmute(pair_id,cohort,center_id=control_id,center_index=control_index,focal=0L))%>%arrange(pair_id,desc(focal))
 d<-units[rep(seq_len(nrow(units)),each=10),];d$year<-rep(2010:2019,nrow(units));d$post<-as.integer(d$focal==1&d$year>=d$cohort)
 d$cohort_sa<-ifelse(d$focal==1,d$cohort,9999);d$center_fe<-as.integer(factor(d$center_id));d$pair_year<-interaction(d$pair_id,d$year,drop=TRUE)
 ids<-sort(unique(d$center_id));ord<-match(d$center_id,ids);kernels<-make_kernels(ids)
 total<-readRDS(file.path(root,'stage_b',paste0('region_annual_sums_',r,'km.rds')))
 center<-do.call(rbind,lapply(seq_len(nrow(units)),function(k)do.call(rbind,lapply(annual,function(v)v[units$center_index[k],]))))
 cumul<-do.call(rbind,lapply(seq_len(nrow(units)),function(k)do.call(rbind,lapply(total,function(v)v[units$center_index[k],c('rac_total','wac_total','seer_total_population')]))))
 components<-list(center=center,surroundings=cumul-center,cumulative=cumul)
 stopifnot(all(is.finite(center)),all(is.finite(cumul)),max(abs(components$center+components$surroundings-components$cumulative))<1e-8,all(d$cohort_sa>2010),any(d$focal==0))
 # Lock a common row sample across outcomes/components. Nonpositive population
 # cannot support the ratio: if present remove the entire pair, never outcome-specific.
 bad<-unique(d$pair_id[components$center[,3]<=0|components$surroundings[,3]<=0|components$cumulative[,3]<=0])
 if(length(bad))stop('Nonpositive population requires explicit common-pair handling; do not silently drop rows.')
 write_csv(d%>%select(pair_id,center_id,year,cohort,focal,cohort_sa),file.path(out,paste0('sample_',sample,'_',r,'km.csv.gz')))
 message(sample,' / ',r,'km / ',nrow(pp),' pairs')
 for(comp in names(components)){
  dd<-d;mat<-components[[comp]];dd$rac<-mat[,1];dd$wac<-mat[,2];dd$population<-mat[,3]
  dd$log_rac<-log(pmax(dd$rac,1));dd$log_wac<-log(pmax(dd$wac,1));dd$log_population<-log(pmax(dd$population,1));dd$emp_pop_ratio<-dd$rac/dd$population
  for(y in c('rac','log_rac'))for(est in 'sun_abraham'){
   rhs<-if(est=='standard_did')'post' else 'sunab(cohort_sa,year,ref.p=c(-1,.F))'
   f<-feols(as.formula(paste(y,'~',rhs,'| center_fe + pair_year')),data=dd,notes=FALSE)
   stopifnot(nobs(f)==nrow(dd),identical(as.integer(obs(f)),seq_len(nrow(dd))),nrow(f$scores)==nrow(dd))
   bn<-names(f$coefficients);nc<-length(bn)
   if(est=='standard_did') {A<-matrix(1,1,1,dimnames=list('ATT',bn));events<-numeric()} else {
    mm<-model.matrix(f);counts<-colSums(sign(mm[,bn,drop=FALSE]));event<-as.numeric(sub('^year::(-?[0-9]+):.*','\\1',bn));stopifnot(!anyNA(event))
    events<-sort(unique(event));A<-matrix(0,1+length(events),nc,dimnames=list(c('ATT',paste0('event_',events)),bn))
    co<-as.numeric(sub('.*:cohort::','',bn));stopifnot(!anyNA(co))
    target_r<-target_cohorts%>%filter(radius_km==r);weights<-target_r$target_n[match(co,target_r$cohort)];stopifnot(!anyNA(weights))
    jj<-event>=0;A[1,jj]<-weights[jj]/sum(weights[jj])
    for(t in seq_along(events)){jj<-event==events[t];A[t+1,jj]<-weights[jj]/sum(weights[jj])}
    stopifnot(all(abs(rowSums(A)-1)<1e-12),all(A>=0))
    if(comp=='center'&&y=='rac')WEIGHTS[[sample_r<-paste(sample,r)]]<-tibble(sample=sample,radius_km=r,cohort=co,event=event,target_n=weights,att_weight=A[1,],event_weight=vapply(seq_along(event),function(j)A[match(event[j],events)+1,j],numeric(1)))
    CELLS[[paste(sample,r,comp,y)]]<-tibble(sample=sample,radius_km=r,component=comp,outcome=y,cohort=co,event=event,estimate=f$coefficients)
    nativeATT<-as.numeric(aggregate(f,'ATT')[1,1])

   }
   bet<-drop(A%*%f$coefficients)
   bread<-solve(f$hessian);stopifnot(max(abs(bread-f$cov.iid/f$sigma2))<1e-6)
   # Project row scores into ATT/event influence, then sum repeated centers/time.
   influence<-f$scores%*%bread%*%t(A);U<-rowsum(influence,ord,reorder=TRUE)
   stopifnot(nrow(U)==length(ids))
   saveRDS(list(ids=ids,U=U,beta=bet,events=events),file.path(out,paste0('influence_',sample,'_',r,'_',comp,'_',y,'.rds')))
   for(covname in names(kernels)){
    V<-as.matrix(crossprod(U,kernels[[covname]]%*%U));V<-(V+t(V))/2
    stopifnot(all(diag(V)>=-1e-10));se<-sqrt(pmax(diag(V),0));pv<-2*pnorm(-abs(bet/se))
    ATT[[length(ATT)+1]]<-tibble(sample=sample,radius_km=r,component=comp,outcome=y,estimator=est,covariance=covname,estimate=bet[1],native_weight_att=nativeATT,std_error=se[1],p_value=pv[1],ci_low=bet[1]-1.96*se[1],ci_high=bet[1]+1.96*se[1],observations=nobs(f),pairs=nrow(pp),unique_centers=length(ids))
    if(est=='sun_abraham'){
     ES[[length(ES)+1]]<-tibble(sample=sample,radius_km=r,component=comp,outcome=y,covariance=covname,event=events,estimate=bet[-1],std_error=se[-1],p_value=pv[-1],ci_low=bet[-1]-1.96*se[-1],ci_high=bet[-1]+1.96*se[-1])
     jj<-which(events>=-5&events<=-2)+1;wt<-wald_test(bet[jj],V[jj,jj,drop=FALSE])
     PRE[[length(PRE)+1]]<-tibble(sample=sample,radius_km=r,component=comp,outcome=y,covariance=covname,test='aggregated_displayed_leads',stat=wt[1],df=wt[2],p_value=wt[3])
    }
   }
   if(y=='rac'&&comp=='center'){
    vc<-vcov(f,cluster=~center_id,ssc=ssc(K.adj=FALSE,G.adj=FALSE));target<-A%*%vc%*%t(A)
    stopifnot(max(abs(target-crossprod(U)))/(1+max(abs(target)))<1e-6)
    VAL[[length(VAL)+1]]<-tibble(sample=sample,radius_km=r,estimator=est,cluster_covariance_relative_error=max(abs(target-crossprod(U)))/(1+max(abs(target))))
   }
   AUD[[length(AUD)+1]]<-tibble(sample=sample,radius_km=r,component=comp,outcome=y,estimator=est,nobs=nobs(f),pairs=nrow(pp),never_control_centers=n_distinct(dd$center_id[dd$focal==0&is.na(b$first_pis_year[dd$center_index])]),future_control_centers=n_distinct(dd$center_id[dd$focal==0&!is.na(b$first_pis_year[dd$center_index])]),n_coefficients=nc)
   N<-N+1;if(N%%3==0)message('Finished ',N,' fits')
  }
 }
 write_csv(bind_rows(ATT),file.path(out,'att_long.csv'));write_csv(bind_rows(ES),file.path(out,'event_study.csv'));write_csv(bind_rows(PRE),file.path(out,'pretrend_tests.csv'));write_csv(bind_rows(AUD),file.path(out,'estimation_audit.csv'));write_csv(bind_rows(VAL),file.path(out,'covariance_validation.csv'))
}
at<-bind_rows(ATT);es<-bind_rows(ES)
# Additivity is checked on point estimates; standard errors do not add.
add<-at%>%filter(outcome%in%c('rac','wac','population'),covariance=='spatial_50km')%>%select(sample,radius_km,outcome,estimator,component,estimate)%>%pivot_wider(names_from=component,values_from=estimate)%>%mutate(error=center+surroundings-cumulative)
stopifnot(max(abs(add$error))<1e-5);write_csv(add,file.path(out,'level_additivity_check.csv'))

writeLines(c('PASS: all intended pair rows retained across all outcomes.', 'PASS: never-treated controls retained.', 'PASS: common aggregation weights nonnegative and sum to one; native ATT also retained. Score covariance equals fixest center clustering with identity kernel.', 'PASS: center plus surroundings equals cumulative for all level ATT estimates.'),file.path(out,'VALIDATION.txt'))
write_csv(bind_rows(WEIGHTS),file.path(out,'common_aggregation_weights.csv'))
write_csv(bind_rows(CELLS),file.path(out,'cohort_event_coefficients.csv'))
w<-bind_rows(WEIGHTS)%>%select(sample,radius_km,cohort,event,att_weight,event_weight)%>%pivot_wider(names_from=sample,values_from=c(att_weight,event_weight))
stopifnot(!anyNA(w),all(abs(w$att_weight_no_projects-w$att_weight_with_projects)<1e-12),all(abs(w$event_weight_no_projects-w$event_weight_with_projects)<1e-12))
DIFF<-list()
for(r in c(3,5,10))for(comp in c('center','surroundings','cumulative'))for(y in c('rac','log_rac')){
 n<-readRDS(file.path(out,paste0('influence_no_projects_',r,'_',comp,'_',y,'.rds')));v<-readRDS(file.path(out,paste0('influence_with_projects_',r,'_',comp,'_',y,'.rds')))
 stopifnot(identical(n$events,v$events));ids<-sort(union(n$ids,v$ids));D<-matrix(0,length(ids),length(v$beta))
 D[match(v$ids,ids),]<-v$U;D[match(n$ids,ids),]<-D[match(n$ids,ids),]-n$U;db<-v$beta-n$beta
 for(covn in names(ks<-make_kernels(ids))){V<-as.matrix(crossprod(D,ks[[covn]]%*%D));se<-sqrt(pmax(diag(V),0))
 DIFF[[length(DIFF)+1]]<-tibble(radius_km=r,component=comp,outcome=y,covariance=covn,term=c('ATT',paste0('event_',v$events)),estimate=db,std_error=se,p_value=2*pnorm(-abs(db/se)),ci_low=db-1.96*se,ci_high=db+1.96*se)}
}
write_csv(bind_rows(DIFF),file.path(out,'group_differences.csv'))
writeLines('COMPLETE',file.path(out,'COMPLETE.txt'))
