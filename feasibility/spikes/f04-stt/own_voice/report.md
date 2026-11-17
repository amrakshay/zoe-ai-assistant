| Run | WER all | WER en-IN voices | WER en-US voices | WER excl. Fred | Tech terms right | First partial p50 / p90 (ms) | Final after last chunk p50 / p90 (ms) | Errors |
|---|---|---|---|---|---|---|---|---|
| dt_en-IN_ctx | 48.1% | 48.1% | 0.0% | 48.1% | 3/17 | 1136 / 2256 | 52 / 113 | 0 |
| dt_en-IN_none | 51.9% | 51.9% | 0.0% | 51.9% | 3/17 | 1137 / 2258 | 54 / 138 | 0 |
| dt_en-US_ctx | 48.1% | 48.1% | 0.0% | 48.1% | 6/17 | 1129 / 1994 | 60 / 164 | 0 |
| dt_en-US_none | 52.8% | 52.8% | 0.0% | 52.8% | 4/17 | 1137 / 1985 | 72 / 151 | 0 |
| st_en-IN_ctx | 33.0% | 33.0% | 0.0% | 33.0% | 6/17 | 1124 / 1661 | 62 / 69 | 0 |
| st_en-IN_none | 33.0% | 33.0% | 0.0% | 33.0% | 6/17 | 1124 / 1662 | 58 / 70 | 0 |
| st_en-US_ctx | 32.1% | 32.1% | 0.0% | 32.1% | 5/17 | 1124 / 2012 | 53 / 68 | 0 |
| st_en-US_none | 32.1% | 32.1% | 0.0% | 32.1% | 5/17 | 1123 / 2017 | 57 / 72 | 0 |
| whisper_large-v3-v20240930_turbo_632MB_none | 26.4% | 26.4% | 0.0% | 26.4% | 11/17 | nan / nan | 455 / 473 | 0 |
| whisper_large-v3-v20240930_turbo_632MB_sentence | 17.9% | 17.9% | 0.0% | 17.9% | 15/17 | nan / nan | 917 / 936 | 0 |
| whisper_large-v3-v20240930_turbo_none | 23.6% | 23.6% | 0.0% | 23.6% | 12/17 | nan / nan | 482 / 506 | 0 |
| whisper_large-v3-v20240930_turbo_prompt | 20.8% | 20.8% | 0.0% | 20.8% | 14/17 | nan / nan | 864 / 885 | 0 |
| whisper_large-v3-v20240930_turbo_sentence | 17.0% | 17.0% | 0.0% | 17.0% | 16/17 | nan / nan | 903 / 924 | 0 |

| Run | Id | Errors | Reference | Hypothesis |
|---|---|---|---|---|
| dt_en-IN_ctx | p02_me | 1 | show my open Jira tickets | Show my open zero tickets |
| dt_en-IN_ctx | p03_me | 6 | run the local review on the collector branch | Randhawa on connector branch |
| dt_en-IN_ctx | p04_me | 3 | is PRJ-21499 merged | Please, Digi 21499 |
| dt_en-IN_ctx | p05_me | 2 | open the MR for bulk push batching in GitLab | Open the MR for bulk push batching |
| dt_en-IN_ctx | p06_me | 3 | tell hash collector dev the build is green | Tell hash collector dev the name |
| dt_en-IN_ctx | p07_me | 7 | check Grafana for the ArgoCD sync errors | Kerala |
| dt_en-IN_ctx | p08_me | 5 | what's the status of the Databricks workspace collector | What is the status of data workspace, collective? |
| dt_en-IN_ctx | p09_me | 5 | create a merge request for the Kubernetes fix | Create multi for the community pics |
| dt_en-IN_ctx | p10_me | 2 | when is the next CCB meeting | When the next meeting |
| dt_en-IN_ctx | p11_me | 2 | summarise my unread Slack messages | Summarise my messages |
| dt_en-IN_ctx | p12_me | 7 | restart the ArgoCD sync for the beta environment | Beta |
| dt_en-IN_ctx | p13_me | 3 | list the failing pipelines in GitLab | List the failing pipeline |
| dt_en-IN_ctx | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five |
| dt_en-IN_ctx | p15_me | 4 | how many pods are crashing in the Kubernetes cluster | How many parts of passing in the cluster? |
| dt_en-IN_none | p02_me | 1 | show my open Jira tickets | Show my open zero tickets |
| dt_en-IN_none | p03_me | 6 | run the local review on the collector branch | Randhawa on connector branch |
| dt_en-IN_none | p04_me | 3 | is PRJ-21499 merged | Please, Digi 21499 |
| dt_en-IN_none | p05_me | 5 | open the MR for bulk push batching in GitLab | Open the MR for bulb, Kush Batla |
| dt_en-IN_none | p06_me | 4 | tell hash collector dev the build is green | Tell has collector, Dev the builder name |
| dt_en-IN_none | p07_me | 7 | check Grafana for the ArgoCD sync errors | Kerala |
| dt_en-IN_none | p08_me | 5 | what's the status of the Databricks workspace collector | What is the status of data workspace, collective? |
| dt_en-IN_none | p09_me | 5 | create a merge request for the Kubernetes fix | Create multi for the community pics |
| dt_en-IN_none | p10_me | 2 | when is the next CCB meeting | When the next meeting |
| dt_en-IN_none | p11_me | 2 | summarise my unread Slack messages | Summarise my messages |
| dt_en-IN_none | p12_me | 7 | restart the ArgoCD sync for the beta environment | Beta |
| dt_en-IN_none | p13_me | 3 | list the failing pipelines in GitLab | List the failing pipeline |
| dt_en-IN_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five |
| dt_en-IN_none | p15_me | 4 | how many pods are crashing in the Kubernetes cluster | How many parts of passing in the cluster? |
| dt_en-US_ctx | p02_me | 1 | show my open Jira tickets | Show my open tickets |
| dt_en-US_ctx | p03_me | 5 | run the local review on the collector branch | On the collector |
| dt_en-US_ctx | p04_me | 4 | is PRJ-21499 merged | Please D21499 |
| dt_en-US_ctx | p06_me | 3 | tell hash collector dev the build is green | Tell hash collector dev the building |
| dt_en-US_ctx | p07_me | 7 | check Grafana for the ArgoCD sync errors |  |
| dt_en-US_ctx | p08_me | 5 | what's the status of the Databricks workspace collector | What is the status of data collector? |
| dt_en-US_ctx | p09_me | 6 | create a merge request for the Kubernetes fix | Eight for the pics |
| dt_en-US_ctx | p10_me | 2 | when is the next CCB meeting | When the next meeting |
| dt_en-US_ctx | p11_me | 2 | summarise my unread Slack messages | Summarize my messages |
| dt_en-US_ctx | p12_me | 7 | restart the ArgoCD sync for the beta environment | Beta |
| dt_en-US_ctx | p13_me | 6 | list the failing pipelines in GitLab | Listing by |
| dt_en-US_ctx | p14_me | 1 | remind me to review the merge request at five | Remind me to review merge request at five |
| dt_en-US_ctx | p15_me | 2 | how many pods are crashing in the Kubernetes cluster | How many points are crashing in the cluster? |
| dt_en-US_none | p02_me | 1 | show my open Jira tickets | Show my open tickets |
| dt_en-US_none | p03_me | 5 | run the local review on the collector branch | On the connector branch |
| dt_en-US_none | p04_me | 4 | is PRJ-21499 merged | Please D21499 |
| dt_en-US_none | p05_me | 4 | open the MR for bulk push batching in GitLab | Open the MR for bulk Kubala |
| dt_en-US_none | p06_me | 4 | tell hash collector dev the build is green | Tell has collector Dev the building |
| dt_en-US_none | p07_me | 7 | check Grafana for the ArgoCD sync errors |  |
| dt_en-US_none | p08_me | 5 | what's the status of the Databricks workspace collector | What is the status of data collector? |
| dt_en-US_none | p09_me | 6 | create a merge request for the Kubernetes fix | Eight for the pics |
| dt_en-US_none | p10_me | 2 | when is the next CCB meeting | When the next meeting |
| dt_en-US_none | p11_me | 2 | summarise my unread Slack messages | Summarize my messages |
| dt_en-US_none | p12_me | 7 | restart the ArgoCD sync for the beta environment | Beta |
| dt_en-US_none | p13_me | 6 | list the failing pipelines in GitLab | Listing by |
| dt_en-US_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five |
| dt_en-US_none | p15_me | 2 | how many pods are crashing in the Kubernetes cluster | How many points are crashing in the cluster? |
| st_en-IN_ctx | p03_me | 1 | run the local review on the collector branch | Run the local review on the collective branch. |
| st_en-IN_ctx | p04_me | 3 | is PRJ-21499 merged | Please, BG 21499 merge. |
| st_en-IN_ctx | p05_me | 2 | open the MR for bulk push batching in GitLab | Open the MR for Balpush batching in Gitlab. |
| st_en-IN_ctx | p06_me | 3 | tell hash collector dev the build is green | Tell hash collector, Dev, the building screen. |
| st_en-IN_ctx | p07_me | 4 | check Grafana for the ArgoCD sync errors | Check Grapana for the AlpuCD in Keras. |
| st_en-IN_ctx | p08_me | 3 | what's the status of the Databricks workspace collector | What's the status of database versus collector? |
| st_en-IN_ctx | p09_me | 3 | create a merge request for the Kubernetes fix | Create my request for the community fix. |
| st_en-IN_ctx | p10_me | 2 | when is the next CCB meeting | When the next SCB meeting? |
| st_en-IN_ctx | p11_me | 1 | summarise my unread Slack messages | Summarise my unread select messages. |
| st_en-IN_ctx | p12_me | 3 | restart the ArgoCD sync for the beta environment | Restart the Angus Siri sync for beta environment. |
| st_en-IN_ctx | p13_me | 6 | list the failing pipelines in GitLab | This is the fending pipelines and get lab. |
| st_en-IN_ctx | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five. |
| st_en-IN_ctx | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are crashing on the Cubanitis cluster? |
| st_en-IN_none | p03_me | 1 | run the local review on the collector branch | Run the local review on the collective branch. |
| st_en-IN_none | p04_me | 3 | is PRJ-21499 merged | Please, BG 21499 merge. |
| st_en-IN_none | p05_me | 2 | open the MR for bulk push batching in GitLab | Open the MR for Balpush batching in Gitlab. |
| st_en-IN_none | p06_me | 3 | tell hash collector dev the build is green | Tell hash collector, Dev, the building screen. |
| st_en-IN_none | p07_me | 4 | check Grafana for the ArgoCD sync errors | Check Grapana for the AlpuCD in Keras. |
| st_en-IN_none | p08_me | 3 | what's the status of the Databricks workspace collector | What's the status of database versus collector? |
| st_en-IN_none | p09_me | 3 | create a merge request for the Kubernetes fix | Create my request for the community fix. |
| st_en-IN_none | p10_me | 2 | when is the next CCB meeting | When the next SCB meeting? |
| st_en-IN_none | p11_me | 1 | summarise my unread Slack messages | Summarise my unread select messages. |
| st_en-IN_none | p12_me | 3 | restart the ArgoCD sync for the beta environment | Restart the Angus Siri sync for beta environment. |
| st_en-IN_none | p13_me | 6 | list the failing pipelines in GitLab | This is the fending pipelines and get lab. |
| st_en-IN_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five. |
| st_en-IN_none | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are crashing on the Cubanitis cluster? |
| st_en-US_ctx | p03_me | 1 | run the local review on the collector branch | Run the local review on the collective branch. |
| st_en-US_ctx | p04_me | 2 | is PRJ-21499 merged | Is BG 21499 merch? |
| st_en-US_ctx | p05_me | 2 | open the MR for bulk push batching in GitLab | Open the MR for Balpush batching in Gitlab. |
| st_en-US_ctx | p06_me | 2 | tell hash collector dev the build is green | Tell hash collector, Dave, the build is clean. |
| st_en-US_ctx | p07_me | 5 | check Grafana for the ArgoCD sync errors | Check Rapana for the Alco cities in Keras. |
| st_en-US_ctx | p08_me | 4 | what's the status of the Databricks workspace collector | What's the status of database versus collected? |
| st_en-US_ctx | p09_me | 3 | create a merge request for the Kubernetes fix | Create my request for the community fix. |
| st_en-US_ctx | p10_me | 2 | when is the next CCB meeting | When the next SUV meeting? |
| st_en-US_ctx | p11_me | 1 | summarise my unread Slack messages | Summarize my unread select messages. |
| st_en-US_ctx | p12_me | 3 | restart the ArgoCD sync for the beta environment | Restart the anniversary thing for beta environment. |
| st_en-US_ctx | p13_me | 5 | list the failing pipelines in GitLab | This is the fending pipelines and get... |
| st_en-US_ctx | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five. |
| st_en-US_ctx | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are crashing on the Cubanitis cluster? |
| st_en-US_none | p03_me | 1 | run the local review on the collector branch | Run the local review on the collective branch. |
| st_en-US_none | p04_me | 2 | is PRJ-21499 merged | Is BG 21499 merch? |
| st_en-US_none | p05_me | 2 | open the MR for bulk push batching in GitLab | Open the MR for Balpush batching in Gitlab. |
| st_en-US_none | p06_me | 2 | tell hash collector dev the build is green | Tell hash collector, Dave, the build is clean. |
| st_en-US_none | p07_me | 5 | check Grafana for the ArgoCD sync errors | Check Rapana for the Alco cities in Keras. |
| st_en-US_none | p08_me | 4 | what's the status of the Databricks workspace collector | What's the status of database versus collected? |
| st_en-US_none | p09_me | 3 | create a merge request for the Kubernetes fix | Create my request for the community fix. |
| st_en-US_none | p10_me | 2 | when is the next CCB meeting | When the next SUV meeting? |
| st_en-US_none | p11_me | 1 | summarise my unread Slack messages | Summarize my unread select messages. |
| st_en-US_none | p12_me | 3 | restart the ArgoCD sync for the beta environment | Restart the anniversary thing for beta environment. |
| st_en-US_none | p13_me | 5 | list the failing pipelines in GitLab | This is the fending pipelines and get... |
| st_en-US_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at five. |
| st_en-US_none | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are crashing on the Cubanitis cluster? |
| whisper_large-v3-v20240930_turbo_632MB_none | p04_me | 2 | is PRJ-21499 merged | is PRJ 214.19 merged |
| whisper_large-v3-v20240930_turbo_632MB_none | p06_me | 2 | tell hash collector dev the build is green | Tell hash collector dev the build screen |
| whisper_large-v3-v20240930_turbo_632MB_none | p07_me | 3 | check Grafana for the ArgoCD sync errors | Check Grafana for the Arco City Sync Carers |
| whisper_large-v3-v20240930_turbo_632MB_none | p08_me | 4 | what's the status of the Databricks workspace collector | What is the status of database workspace collector? |
| whisper_large-v3-v20240930_turbo_632MB_none | p09_me | 1 | create a merge request for the Kubernetes fix | Create merge request for the Kubernetes fix. |
| whisper_large-v3-v20240930_turbo_632MB_none | p10_me | 2 | when is the next CCB meeting | When the next DCC meeting? |
| whisper_large-v3-v20240930_turbo_632MB_none | p11_me | 2 | summarise my unread Slack messages | Summarize my angry select messages. |
| whisper_large-v3-v20240930_turbo_632MB_none | p12_me | 4 | restart the ArgoCD sync for the beta environment | Restart the Argo City Sink for Beta Environment. |
| whisper_large-v3-v20240930_turbo_632MB_none | p13_me | 6 | list the failing pipelines in GitLab | - |
| whisper_large-v3-v20240930_turbo_632MB_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at 5. |
| whisper_large-v3-v20240930_turbo_632MB_none | p15_me | 1 | how many pods are crashing in the Kubernetes cluster | How many parts are crashing in the Kubernetes cluster? |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p02_me | 3 | show my open Jira tickets | So my OpenJira tickets. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p04_me | 1 | is PRJ-21499 merged | This is PRJ-21499 merged. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p06_me | 1 | tell hash collector dev the build is green | Tell hash collector dev, the build is clean. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p07_me | 2 | check Grafana for the ArgoCD sync errors | Check Grafana for the ArgoCD on Keras. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p08_me | 4 | what's the status of the Databricks workspace collector | What is the status of database workspace collector? |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p09_me | 1 | create a merge request for the Kubernetes fix | Create merge request for the Kubernetes fix. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p10_me | 1 | when is the next CCB meeting | When the next CCB meeting? |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p11_me | 1 | summarise my unread Slack messages | Summarize my Android Slack messages. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p12_me | 2 | restart the ArgoCD sync for the beta environment | Restart the ArgoCD sink for beta environment. |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p13_me | 2 | list the failing pipelines in GitLab | "Ligital failing pipelines in GitLab." |
| whisper_large-v3-v20240930_turbo_632MB_sentence | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at 5. |
| whisper_large-v3-v20240930_turbo_none | p04_me | 2 | is PRJ-21499 merged | is PRJ21419 merged |
| whisper_large-v3-v20240930_turbo_none | p07_me | 4 | check Grafana for the ArgoCD sync errors | Check Grafana for the Arco City's Inc. Carers. |
| whisper_large-v3-v20240930_turbo_none | p08_me | 4 | what's the status of the Databricks workspace collector | What is the status of database workspace collector? |
| whisper_large-v3-v20240930_turbo_none | p09_me | 1 | create a merge request for the Kubernetes fix | Create merge request for the Kubernetes fix. |
| whisper_large-v3-v20240930_turbo_none | p10_me | 4 | when is the next CCB meeting | When the next DC will be meeting? |
| whisper_large-v3-v20240930_turbo_none | p11_me | 1 | summarise my unread Slack messages | Summarize my angry slack messages. |
| whisper_large-v3-v20240930_turbo_none | p12_me | 2 | restart the ArgoCD sync for the beta environment | Restart the Arbocity Sync for Beta Environment. |
| whisper_large-v3-v20240930_turbo_none | p13_me | 3 | list the failing pipelines in GitLab | Digital fending pipelines in GitLab |
| whisper_large-v3-v20240930_turbo_none | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at 5. |
| whisper_large-v3-v20240930_turbo_none | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are caching on the Kubernetes cluster? |
| whisper_large-v3-v20240930_turbo_prompt | p04_me | 1 | is PRJ-21499 merged | This is PRJ-21499, merged. |
| whisper_large-v3-v20240930_turbo_prompt | p07_me | 7 | check Grafana for the ArgoCD sync errors | Jira, MR, merge, PRJ-21499, GitLab, |
| whisper_large-v3-v20240930_turbo_prompt | p08_me | 4 | what's the status of the Databricks workspace collector | What is the status of database workspace collector? |
| whisper_large-v3-v20240930_turbo_prompt | p09_me | 1 | create a merge request for the Kubernetes fix | Create merge request for the Kubernetes fix. |
| whisper_large-v3-v20240930_turbo_prompt | p10_me | 1 | when is the next CCB meeting | When the next CCB meeting? |
| whisper_large-v3-v20240930_turbo_prompt | p11_me | 1 | summarise my unread Slack messages | Summarize my angry Slack messages. |
| whisper_large-v3-v20240930_turbo_prompt | p12_me | 1 | restart the ArgoCD sync for the beta environment | Restart the ArgoCD sync for beta environment. |
| whisper_large-v3-v20240930_turbo_prompt | p13_me | 2 | list the failing pipelines in GitLab | Digital failing pipelines in GitLab. |
| whisper_large-v3-v20240930_turbo_prompt | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at 5. |
| whisper_large-v3-v20240930_turbo_prompt | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are caching on the Kubernetes cluster? |
| whisper_large-v3-v20240930_turbo_sentence | p02_me | 1 | show my open Jira tickets | So my open Jira tickets. |
| whisper_large-v3-v20240930_turbo_sentence | p04_me | 1 | is PRJ-21499 merged | This is PRJ-21499 merged. |
| whisper_large-v3-v20240930_turbo_sentence | p07_me | 2 | check Grafana for the ArgoCD sync errors | Check Grafana for the ArgoCD on Keras. |
| whisper_large-v3-v20240930_turbo_sentence | p08_me | 4 | what's the status of the Databricks workspace collector | What is the status of database workspace collector? |
| whisper_large-v3-v20240930_turbo_sentence | p09_me | 1 | create a merge request for the Kubernetes fix | Create merge request for the Kubernetes fix. |
| whisper_large-v3-v20240930_turbo_sentence | p10_me | 1 | when is the next CCB meeting | When the next CCB meeting? |
| whisper_large-v3-v20240930_turbo_sentence | p11_me | 1 | summarise my unread Slack messages | Summarize my Android Slack messages. |
| whisper_large-v3-v20240930_turbo_sentence | p13_me | 3 | list the failing pipelines in GitLab | Digital fending pipelines in GitLab. |
| whisper_large-v3-v20240930_turbo_sentence | p14_me | 1 | remind me to review the merge request at five | Remind me to review and merge request at 5. |
| whisper_large-v3-v20240930_turbo_sentence | p15_me | 3 | how many pods are crashing in the Kubernetes cluster | How many parts are caching on the Kubernetes cluster? |
