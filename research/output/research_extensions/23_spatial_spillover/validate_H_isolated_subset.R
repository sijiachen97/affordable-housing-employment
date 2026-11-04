suppressPackageStartupMessages(library(tidyverse))
a<-commandArgs(TRUE);root<-a[1];out<-a[2]
z<-readRDS(file.path(root,'stage_a/neighborhood_cache.rds'));b<-z$base;p<-z$pts
h<-read_csv(file.path(root,'stage_h/matching/matched_pairs.csv'),show_col_types=FALSE)
m<-read_csv(file.path(out,'combined_matched_pairs.csv'),show_col_types=FALSE)
raw<-read_csv('./data_raw/LIHTC/LIHTC_public/LIHTCPUB.csv',col_types=cols(.default=col_character()))%>%filter(str_trim(type)=='1')%>%mutate(tract_id=suppressWarnings(as.numeric(fips2010)),pis=suppressWarnings(as.numeric(yr_pis)))
unknown<-unique(raw$tract_id[is.na(raw$pis)|raw$pis%in%c(8888,9999)])
recent<-unique(raw$tract_id[is.finite(raw$pis)&raw$pis>=2010&raw$pis<=2019])
keep<-vapply(seq_len(nrow(h)),function(i){v<-h[i,];nb<-setdiff(p$tract_id[z$members[[as.character(v$radius_km)]][[v$treated_index]]],v$treated_id);!any(nb%in%c(unknown,recent))},logical(1))
key<-c('radius_km','cohort','treated_id','control_id')
stopifnot(nrow(anti_join(h[keep,],m,by=key))==0,nrow(anti_join(m,h[keep,],by=key))==0,nrow(m)==sum(keep))
el<-read_csv(file.path(root,'stage_b/eligibility_and_matching_status.csv'),show_col_types=FALSE)%>%filter(!is.na(clean_control))
for(i in seq_len(nrow(m))){v<-m[i,];ti<-v$treated_index;ci<-v$control_index
 stopifnot(b$first_pis_year[ti]==v$cohort,is.na(b$first_pis_year[ci])||b$first_pis_year[ci]>2019,
 substr(sprintf('%011.0f',v$treated_id),1,2)==substr(sprintf('%011.0f',v$control_id),1,2),
 el$clean_control[el$radius_km==v$radius_km&el$tract_id==v$control_id],
 length(intersect(z$members[[as.character(v$radius_km)]][[ti]],z$members[[as.character(v$radius_km)]][[ci]]))==0)
}
stopifnot(!anyDuplicated(m[c('radius_km','cohort','treated_id')]),!anyDuplicated(m[c('radius_km','cohort','control_id')]))
writeLines(c('PASS: independent raw-project check exactly reproduces retained H pairs.', 'PASS: all original H controls retained without rematching; retained pairs need not appear in J.', 'PASS: same-state, never/future control eligibility, clean-control flag, nonoverlap, and within-cohort nonreuse.'),file.path(out,'INDEPENDENT_VALIDATION.txt'))
