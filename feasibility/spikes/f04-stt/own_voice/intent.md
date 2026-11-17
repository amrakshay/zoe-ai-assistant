| Run | Same | Partial | Wrong |
|---|---|---|---|
| st_en-US_none | 7/15 | 2/15 | 6/15 |
| whisper_large-v3-v20240930_turbo_none | 11/15 | 3/15 | 1/15 |
| whisper_large-v3-v20240930_turbo_sentence | 13/15 | 1/15 | 1/15 |

| Run | Id | Transcript | Claude's reading | Reference | Grade |
|---|---|---|---|---|---|
| st_en-US_none | p05_me | Open the MR for Balpush batching in Gitlab. | Open the MR for batching in GitLab. (?) | open the MR for bulk push batching in GitLab | partial |
| st_en-US_none | p06_me | Tell hash collector, Dave, the build is clean. | Tell the collector team the build is clean. (?) | tell hash collector dev the build is green | wrong |
| st_en-US_none | p07_me | Check Rapana for the Alco cities in Keras. | Check Grafana for the alerts in Kubernetes. (?) | check Grafana for the ArgoCD sync errors | wrong |
| st_en-US_none | p08_me | What's the status of database versus collected? | What's the status of database versus collector? (?) | what's the status of the Databricks workspace collector | wrong |
| st_en-US_none | p09_me | Create my request for the community fix. | Create my merge request for the community fix. (?) | create a merge request for the Kubernetes fix | wrong |
| st_en-US_none | p10_me | When the next SUV meeting? | When's the next standup meeting? (?) | when is the next CCB meeting | wrong |
| st_en-US_none | p12_me | Restart the anniversary thing for beta environment. | Restart the Argo CD app for the beta environment. (?) | restart the ArgoCD sync for the beta environment | partial |
| st_en-US_none | p13_me | This is the fending pipelines and get... | Show the pending pipelines in GitLab. (?) | list the failing pipelines in GitLab | wrong |
| whisper_large-v3-v20240930_turbo_none | p04_me | is PRJ21419 merged | Is PRJ-21419 merged? | is PRJ-21499 merged | partial |
| whisper_large-v3-v20240930_turbo_none | p06_me | tell hash collector dev the build is green | Tell #collector-dev the build is green. | tell hash collector dev the build is green | partial |
| whisper_large-v3-v20240930_turbo_none | p07_me | Check Grafana for the Arco City's Inc. Carers. | Check Grafana for the ArgoCD city's in-cluster errors. (?) | check Grafana for the ArgoCD sync errors | partial |
| whisper_large-v3-v20240930_turbo_none | p10_me | When the next DC will be meeting? | When is the next DC meeting? (?) | when is the next CCB meeting | wrong |
| whisper_large-v3-v20240930_turbo_sentence | p06_me | Tell hash collector dev the build is green. | Tell #collector-dev the build is green. (?) | tell hash collector dev the build is green | partial |
| whisper_large-v3-v20240930_turbo_sentence | p07_me | Check Grafana for the ArgoCD on Keras. | Check Grafana for the ArgoCD on Alpha. (?) | check Grafana for the ArgoCD sync errors | wrong |
