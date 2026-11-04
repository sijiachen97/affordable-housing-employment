source('code/analysis/main/engine.R')
files<-list.files(OUT,pattern='^att.csv$',recursive=TRUE,full.names=TRUE);at<-map_dfr(files,~read_csv(.x,show_col_types=FALSE));cf<-map_dfr(sub('att.csv$','event_study.csv',files),~read_csv(.x,show_col_types=FALSE));qa<-map_dfr(sub('att.csv$','sample_audit.csv',files),~read_csv(.x,show_col_types=FALSE));pr<-map_dfr(sub('att.csv$','pretrend.csv',files),~read_csv(.x,show_col_types=FALSE))
stopifnot(!anyDuplicated(at[c('analysis','group','specification','outcome')]))
write_csv(at,file.path(OUT,'all_att.csv'));write_csv(cf,file.path(OUT,'all_event_study.csv'));write_csv(qa,file.path(OUT,'all_sample_audits.csv'));write_csv(pr,file.path(OUT,'all_pretrend_tests.csv'))
ref<-read_csv(path('output/research_extensions/26_main_state_guarded_matching/sunab_att.csv'),show_col_types=FALSE)
rp<-at%>%filter(str_starts(analysis,'main/'),specification=='matched_pair_year')%>%inner_join(ref%>%select(group,outcome,old_estimate=estimate,old_se=std_error,old_n=observations),by=c('group','outcome'))%>%mutate(error=estimate-old_estimate,se_error=std_error-old_se)
stopifnot(nrow(rp)==39,all(abs(rp$error)<1e-8),all(abs(rp$se_error)<1e-8),all(rp$observations==rp$old_n));write_csv(rp,file.path(OUT,'replication_of_guarded_main.csv'))
# Preserve additive identities for near/far outcomes on the identical fitted rows.
nf<-at%>%filter(analysis=='near_far')%>%select(group,specification,outcome,estimate)%>%pivot_wider(names_from=outcome,values_from=estimate)
for(r in c(5,10,20))stopifnot(all(abs(nf[[paste0('near_per_pop_',r)]]+nf[[paste0('far_per_pop_',r)]]-nf$od_per_pop)<1e-8))
stopifnot(all(abs(nf$od_per_pop+nf$rac_od_gap_per_pop-nf$rac_per_pop)<1e-8))
ne<-cf%>%filter(analysis=='near_far')%>%select(group,specification,term,outcome,estimate)%>%pivot_wider(names_from=outcome,values_from=estimate)
for(r in c(5,10,20))stopifnot(all(abs(ne[[paste0('near_per_pop_',r)]]+ne[[paste0('far_per_pop_',r)]]-ne$od_per_pop)<1e-7))
stopifnot(all(abs(ne$od_per_pop+ne$rac_od_gap_per_pop-ne$rac_per_pop)<1e-7))
stopifnot(nrow(at)==648,nrow(qa)==648,all(qa$never_tracts>0))

# Standard readable plot styling, standalone main model only.
th<-theme_bw(base_size=12)+theme(panel.grid.minor=element_blank(),panel.grid.major.x=element_blank(),panel.grid.major.y=element_line(color='#e1e7ef',linetype='dotted'),strip.background=element_blank(),strip.text=element_text(face='bold',color='#214F80'),panel.border=element_rect(color='#c5cfdc'),legend.position='bottom')
label<-function(s){s<-gsub('_',' ',s);tools::toTitleCase(s)}
nice<-c(emp_pop_ratio='Employment-to-population ratio',primary_emp_pop_ratio='Primary-job employment-to-population ratio',seer_total_population='Population',log_seer_pop='Population (log)',rac_total='Resident-held jobs',log_rac='Resident-held jobs (log)',wac_total='Workplace jobs',log_wac='Workplace jobs (log)',log_primary_rac='Primary resident-held jobs (log)',primary_rac_total='Primary resident-held jobs')
for(side in c('rac','wac'))for(tier in c('low','mid','high'))nice[paste0('log_',side,'_',tier)]<-paste(toupper(side),tier,'wage jobs (log)')
for(k in c('s000','sa01','sa02','sa03','se01','se02','se03','si01','si02','si03'))nice[paste0('avg_road_dist_from_',k)]<-paste('Commuting distance:',c(s000='all workers',sa01='age 29 or younger',sa02='age 30–54',sa03='age 55 or older',se01='low wage',se02='mid wage',se03='high wage',si01='goods producing',si02='trade, transportation, utilities',si03='other services')[k])
sector_labels<-read_csv(path('code/analysis/figures/industry_definitions.csv'),show_col_types=FALSE)
for(j in seq_len(nrow(sector_labels))){nice[sector_labels$sector[j]]<-sector_labels$industry[j];nice[paste0('log_',sector_labels$sector[j])]<-paste0(sector_labels$industry[j],' (log)')}
pretty_y<-function(y){if(y%in%names(nice))unname(nice[y])else label(y)}

plot_events<-function(d,file,title,facets='group',scale=1,ylab=NULL){
 d<-d%>%mutate(group=factor(group,levels=c('pooled','lower_income','higher_income','low_intensity','high_intensity'),labels=c('Pooled','Lower income','Higher income','Low intensity','High intensity')),event=as.numeric(sub('year::','',term)))%>%filter(between(event,-5,5))
 d<-bind_rows(d,d%>%distinct(across(all_of(facets)))%>%mutate(event=-1,estimate=0,std_error=0))%>%mutate(estimate=estimate*scale,std_error=std_error*scale)
 p<-ggplot(d,aes(event,estimate))+geom_hline(yintercept=0,color='#8995A5',linewidth=.4)+geom_vline(xintercept=-1,linetype=2,color='#a1aebc',linewidth=.4)+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,color='#214F80')+geom_line(color='#214F80')+geom_point(color='#214F80',size=1.3)+facet_wrap(vars(!!!syms(facets)),ncol=3)+scale_x_continuous(breaks=-5:5)+th+labs(title=title,x='Years relative to first placement',y=ylab,caption='Tract and pair × year fixed effects; tract-clustered SE; 95% pointwise intervals.')
 ggsave(file,p,width=12,height=max(4,3.1*ceiling(nrow(distinct(d,across(all_of(facets))))/3)),dpi=160)
}
dir.create(file.path(OUT,'figures'),showWarnings=FALSE)
manifest<-list()
for(an in unique(cf$analysis)){
 d<-cf%>%filter(analysis==an,specification=='matched_pair_year')
 for(y in unique(d$outcome)){
  fname<-paste0(gsub('/','_',an),'__',y,'.png');ratio<-grepl('per_pop|emp_pop_ratio|near_share',y)
  plot_events(filter(d,outcome==y),file.path(OUT,'figures',fname),paste0(if(str_starts(an,'industry/'))paste0(toupper(sub('industry/','',an)),': ') else if(str_starts(an,'intensity/'))'Construction intensity: ' else '',pretty_y(y)),scale=if(ratio)100 else 1,ylab=if(ratio)'Percentage points' else if(str_starts(y,'log_'))'Log points' else if(str_starts(y,'avg_road'))'km' else 'Count')
  manifest[[paste(an,y)]]<-tibble(analysis=an,outcome=y,file=paste0('figures/',fname))
 }
}
# Wage tiers share scales in each combined plot, including income panels.
for(side in c('rac','wac')){
 d<-cf%>%filter(analysis==paste0('main/log_',side,'_low'),specification=='matched_pair_year')%>%mutate(wage=factor(outcome,levels=paste0('log_',side,'_',c('low','mid','high')),labels=c('Low wage','Mid wage','High wage')))
 plot_events(d,file.path(OUT,'figures',paste0(side,'_wage_combined.png')),paste(toupper(side),'by wage tier and neighborhood income'),c('group','wage'),ylab='Log points')
}
# Industry forest plots, no BH coding; show all sectors and ordinary 95% intervals.
def<-read_csv(path('code/analysis/figures/industry_definitions.csv'),show_col_types=FALSE)
for(metric in c('log','level')){
 d<-at%>%filter(str_starts(analysis,'industry/'),specification=='matched_pair_year',if(metric=='log')str_starts(outcome,'log_CNS') else str_starts(outcome,'CNS'))%>%mutate(sector=sub('log_','',outcome),side=if_else(analysis=='industry/rac','RAC: jobs held by residents','WAC: jobs located in the tract'))%>%left_join(def,by='sector')%>%mutate(industry=factor(industry,levels=rev(def$industry)),estimate=estimate*if(metric=='log')100 else 1,std_error=std_error*if(metric=='log')100 else 1)
 q<-ggplot(d,aes(estimate,industry))+geom_vline(xintercept=0,color='grey55')+geom_errorbar(aes(xmin=estimate-1.96*std_error,xmax=estimate+1.96*std_error),orientation='y',width=.12,color='#214F80')+geom_point(color='#214F80',size=1.7)+facet_wrap(~side)+th+labs(title=paste('Industry employment:',metric,'effects'),x=if(metric=='log')'100 × effect on log jobs' else 'Jobs',y=NULL)
 ggsave(file.path(OUT,'figures',paste0('industry_',metric,'.png')),q,width=13,height=9,dpi=170)
}
# Nearby/farther, separate rows for rate and logs, paired scales within measure.
d<-cf%>%filter(analysis=='near_far',specification=='matched_pair_year',outcome%in%c('near_per_pop_10','far_per_pop_10','log_near_jobs_10','log_far_jobs_10'))%>%mutate(measure=if_else(str_starts(outcome,'log_'),'Log jobs','Employment-to-population ratio (pp)'),distance=if_else(str_detect(outcome,'near'),'Nearby','Farther'),event=as.numeric(sub('year::','',term)),estimate=estimate*if_else(str_starts(outcome,'log_'),1,100),std_error=std_error*if_else(str_starts(outcome,'log_'),1,100))%>%filter(between(event,-5,5))
d<-bind_rows(d,distinct(d,measure,distance)%>%mutate(event=-1,estimate=0,std_error=0))
q<-ggplot(d,aes(event,estimate))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,color='#214F80')+geom_line(color='#214F80')+geom_point(color='#214F80')+facet_grid(measure~distance,scales='free_y')+th+labs(x='Years relative to first placement',y=NULL,title='Employment by workplace distance: 10 km')
ggsave(file.path(OUT,'figures/near_far_10km.png'),q,width=10,height=7,dpi=170)
d<-at%>%filter(analysis=='near_far',specification=='matched_pair_year',str_detect(outcome,'^(near_per_pop|far_per_pop|log_near_jobs|log_far_jobs)_'))%>%mutate(radius=as.numeric(sub('.*_','',outcome)),measure=if_else(str_starts(outcome,'log_'),'Log jobs','Employment-to-population ratio (pp)'),distance=if_else(str_detect(outcome,'near'),'Nearby','Farther'),estimate=estimate*if_else(str_starts(outcome,'log_'),1,100),std_error=std_error*if_else(str_starts(outcome,'log_'),1,100))
q<-ggplot(d,aes(radius,estimate,color=distance))+geom_hline(yintercept=0,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.4,position=position_dodge(.8))+geom_point(position=position_dodge(.8))+facet_wrap(~measure,ncol=1,scales='free_y')+scale_x_continuous(breaks=c(5,10,20))+scale_color_manual(values=c('#b1672f','#214F80'))+th+labs(x='Radius (km)',y=NULL,color=NULL,title='Workplace-distance radius sensitivity')
ggsave(file.path(OUT,'figures/radius_sensitivity.png'),q,width=9,height=7,dpi=170)

# Primary-job comparison, retaining identical matched pairs and fitted rows.
for(section in c('primary','primary_intensity'))for(kind in c('emp_pop_ratio','rac_total')){
 d<-cf%>%filter(analysis==paste0(section,'/',kind),specification=='matched_pair_year')
 if(kind=='rac_total')d<-d%>%filter(outcome%in%c('log_rac','log_primary_rac'))
 d<-d%>%mutate(event=as.numeric(sub('year::','',term)),definition=if_else(str_detect(outcome,'primary'),'Primary jobs','All jobs'),group=factor(group,levels=c('pooled','lower_income','higher_income','low_intensity','high_intensity')))%>%filter(between(event,-5,5))
 d<-bind_rows(d,distinct(d,group,definition)%>%mutate(event=-1,estimate=0,std_error=0))
 if(kind=='emp_pop_ratio')d<-d%>%mutate(estimate=100*estimate,std_error=100*std_error)
 q<-ggplot(d,aes(event,estimate,color=definition,group=definition))+geom_hline(yintercept=0,color='grey60')+geom_vline(xintercept=-1,linetype=2,color='grey60')+geom_errorbar(aes(ymin=estimate-1.96*std_error,ymax=estimate+1.96*std_error),width=.08,position=position_dodge(.12))+geom_line()+geom_point(size=1)+facet_wrap(~group,nrow=1)+scale_color_manual(values=c('#969da5','#214F80'))+th+labs(x='Years relative to first placement',y=if(kind=='emp_pop_ratio')'Percentage points' else 'Log points',color=NULL,title='All jobs and primary jobs: identical matched observations')
 ggsave(file.path(OUT,'figures',paste0(section,'_comparison_',kind,'.png')),q,width=12,height=4,dpi=160)
}

b<-read_csv(file.path(OUT,'matching_balance.csv'),show_col_types=FALSE)
rt<-read_csv(file.path(OUT,'cohort_retention.csv'),show_col_types=FALSE)%>%select(group,cohort,matched_treated)
bb<-b%>%left_join(rt,by=c('group','cohort'))%>%group_by(group,covariate,stage)%>%summarise(mean_absolute_smd=weighted.mean(abs(smd),matched_treated,na.rm=TRUE),max_absolute_smd=max(abs(smd),na.rm=TRUE),.groups='drop')
write_csv(bb,file.path(OUT,'descriptives/balance_summary.csv'))
q<-ggplot(bb,aes(mean_absolute_smd,covariate,color=stage))+geom_vline(xintercept=.1,linetype=2,color='grey60')+geom_point()+facet_wrap(~group,nrow=1)+th+labs(x='Matched-cohort-weighted mean absolute standardized difference',y=NULL,color=NULL,title='Covariate balance before and after matching')
ggsave(file.path(OUT,'figures/matching_balance.png'),q,width=13,height=8,dpi=160)
write_csv(bind_rows(manifest),file.path(OUT,'figure_manifest.csv'))
writeLines('PASS: guarded main replicated, all model samples audited, near/far additive identities verified.',file.path(OUT,'VALIDATION.txt'))
