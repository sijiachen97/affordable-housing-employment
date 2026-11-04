library(tidyverse)
W<-dirname(normalizePath(sub('^--file=', '', commandArgs()[grepl('^--file=', commandArgs())][1])))
meta<-tibble(sector=sprintf('CNS%02d',1:20),naics=c('11','21','22','23','31–33','42','44–45','48–49','51','52','53','54','55','56','61','62','71','72','81','92'),industry=c('Agriculture, forestry, fishing','Mining and extraction','Utilities','Construction','Manufacturing','Wholesale trade','Retail trade','Transportation and warehousing','Information','Finance and insurance','Real estate and leasing','Professional and technical services','Management of companies','Administrative and waste services','Education','Health care and social assistance','Arts and recreation','Accommodation and food services','Other services','Public administration'),industry_cn=c('农林牧渔','采矿及油气开采','公用事业','建筑','制造','批发','零售','运输与仓储','信息','金融与保险','房地产与租赁','专业及技术服务','公司和企业管理','行政支持及废物管理','教育','医疗及社会援助','文娱','住宿餐饮','其他服务','公共行政'))
write_csv(meta,file.path(W,'industry_definitions.csv'))
all<-map_dfr(c('rac','wac'),function(side){
 a<-read_csv(file.path(W,side,'estimates/att_long.csv'),show_col_types=FALSE) %>% mutate(perspective=toupper(side),metric=if_else(str_starts(outcome,'log_'),'log','count'),sector=str_remove(outcome,'^log_'))
 pre<-read_csv(file.path(W,side,'estimates/pretrend_tests.csv'),show_col_types=FALSE) %>% select(group,specification,outcome,window,p_value) %>% pivot_wider(names_from=window,values_from=p_value,names_prefix='pretrend_p_')
 b<-map_dfr(c('matched','full'),function(g)read_csv(file.path(W,side,paste0('baseline_',g,'.csv')),show_col_types=FALSE))
 a %>% left_join(pre,by=c('group','specification','outcome')) %>% mutate(sample=if_else(specification=='full_county_year','full','matched')) %>% left_join(b %>% rename(sector=outcome),by=c('sample','sector'))
})
totals<-filter(all,sector=='total_jobs');write_csv(totals,file.path(W,'total_outcome_replication.csv'))
a<-all %>% filter(sector!='total_jobs') %>% left_join(meta,by='sector') %>% group_by(perspective,metric,specification) %>% mutate(q_bh_20=p.adjust(p_value,'BH'),p_holm_20=p.adjust(p_value,'holm')) %>% ungroup() %>% group_by(specification) %>% mutate(q_bh_80=p.adjust(p_value,'BH'),p_holm_80=p.adjust(p_value,'holm')) %>% ungroup() %>% mutate(ci_low=estimate-1.96*std_error,ci_high=estimate+1.96*std_error)
stopifnot(nrow(a)==240)
write_csv(a,file.path(W,'all_industry_results.csv'))
wide<-a %>% mutate(cell=sprintf('%.4f%s (%.4f)',estimate,case_when(p_value<.01~'***',p_value<.05~'**',p_value<.1~'*',TRUE~''),std_error)) %>% select(perspective,metric,sector,naics,industry,industry_cn,specification,cell) %>% pivot_wider(names_from=specification,values_from=cell) %>% select(perspective,metric,sector,naics,industry,industry_cn,matched_pair_year,full_county_year,matched_year)
write_csv(wide,file.path(W,'three_specifications_wide.csv'))
write_csv(a %>% group_by(perspective,metric,sector,industry,industry_cn) %>% summarise(same_sign=n_distinct(sign(estimate))==1,all_nominal_5pct=all(p_value<.05),all_bh20_5pct=all(q_bh_20<.05),any_display_pretrend_rejection=any(pretrend_p_displayed<.05),.groups='drop'),file.path(W,'cross_specification_summary.csv'))
# Forest plots retain NAICS ordering and the same scale for RAC/WAC within a metric.
a<-a %>% mutate(Industry=factor(industry,levels=rev(meta$industry)),Perspective=factor(perspective,levels=c('RAC','WAC'),labels=c('RAC: jobs held by residents','WAC: jobs located in the tract')),Model=factor(specification,levels=c('matched_pair_year','full_county_year','matched_year'),labels=c('Matched: pair × year FE','Full panel: county × year FE','Matched: year FE')))
for(m in c('count','log')){
 z<-filter(a,metric==m)
 scale<-if(m=='log')100 else 1
 z<-z %>% mutate(value=estimate*scale,lower=ci_low*scale,upper=ci_high*scale)
 p<-ggplot(filter(z,specification=='matched_pair_year'),aes(value,Industry))+geom_vline(xintercept=0,color='grey55')+geom_errorbar(aes(xmin=lower,xmax=upper),orientation='y',width=.15,color='#2B5685')+geom_point(aes(shape=q_bh_20<.05),color='#2B5685',size=2)+scale_shape_manual(values=c('FALSE'=1,'TRUE'=16),name='BH-adjusted q < 0.05')+facet_grid(.~Perspective)+theme_bw(base_size=11)+theme(panel.grid.minor=element_blank(),legend.position='bottom')+labs(x=if(m=='log')'100 × effect on log(max(jobs, 1))' else 'Aggregate effect on number of jobs',y=NULL,title=paste('Industry employment:',if(m=='log')'log changes' else 'job counts'),subtitle='Main specification: same-county matching, tract and pair × year fixed effects',caption='Bars: pointwise 95% confidence intervals. Filled points pass BH adjustment within 20 sectors; pretrend diagnostics are reported separately.')
 ggsave(file.path(W,paste0('main_',m,'_rac_wac.png')),p,width=13,height=9,dpi=180)
 p<-ggplot(z,aes(value,Industry,color=Model))+geom_vline(xintercept=0,color='grey55')+geom_errorbar(aes(xmin=lower,xmax=upper),orientation='y',width=.15,position=position_dodge(width=.7))+geom_point(position=position_dodge(width=.7),size=1.5)+scale_color_manual(values=c('#2B5685','#C06B32','#28887F'))+facet_grid(.~Perspective)+theme_bw(base_size=11)+theme(panel.grid.minor=element_blank(),legend.position='bottom')+labs(x=if(m=='log')'100 × effect on log(max(jobs, 1))' else 'Aggregate effect on number of jobs',y=NULL,title=paste('Industry employment across specifications:',m),caption='Bars: pointwise 95% confidence intervals. All models include tract fixed effects. The two matched models use identical observations.')
 ggsave(file.path(W,paste0('comparison_',m,'_rac_wac.png')),p,width=14,height=11,dpi=180)
}
print(a %>% filter(specification=='matched_pair_year') %>% select(perspective,metric,industry_cn,estimate,std_error,p_value,q_bh_20,pretrend_p_displayed),n=80,width=160)
