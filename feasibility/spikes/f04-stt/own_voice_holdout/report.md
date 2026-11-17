| Run | WER all | WER en-IN voices | WER en-US voices | WER excl. Fred | Tech terms right | First partial p50 / p90 (ms) | Final after last chunk p50 / p90 (ms) | Errors |
|---|---|---|---|---|---|---|---|---|
| dt_en-IN_ctx | 43.2% | 43.2% | 0.0% | 43.2% | 5/17 | 1119 / 1495 | 68 / 115 | 0 |
| dt_en-IN_none | 43.2% | 43.2% | 0.0% | 43.2% | 4/17 | 1115 / 1507 | 88 / 137 | 0 |
| dt_en-US_ctx | 40.5% | 40.5% | 0.0% | 40.5% | 6/17 | 1144 / 1504 | 73 / 134 | 0 |
| dt_en-US_none | 41.4% | 41.4% | 0.0% | 41.4% | 3/17 | 1176 / 1536 | 76 / 147 | 0 |
| st_en-IN_ctx | 33.3% | 33.3% | 0.0% | 33.3% | 5/17 | 1126 / 1663 | 55 / 65 | 0 |
| st_en-IN_none | 33.3% | 33.3% | 0.0% | 33.3% | 5/17 | 1122 / 1662 | 62 / 74 | 0 |
| st_en-US_ctx | 37.8% | 37.8% | 0.0% | 37.8% | 3/17 | 1122 / 2014 | 56 / 62 | 0 |
| st_en-US_none | 37.8% | 37.8% | 0.0% | 37.8% | 3/17 | 1126 / 2018 | 58 / 77 | 0 |
| whisper_large-v3-v20240930_turbo_none | 18.9% | 18.9% | 0.0% | 18.9% | 8/17 | nan / nan | 489 / 508 | 0 |
| whisper_large-v3-v20240930_turbo_prompt | 14.4% | 14.4% | 0.0% | 14.4% | 11/17 | nan / nan | 867 / 888 | 0 |
| whisper_large-v3-v20240930_turbo_sentence | 17.1% | 17.1% | 0.0% | 17.1% | 11/17 | nan / nan | 903 / 931 | 0 |

| Run | Id | Errors | Reference | Hypothesis |
|---|---|---|---|---|
| dt_en-IN_ctx | h01_me | 3 | move PRJ-21604 to in review | Move to 1642 review |
| dt_en-IN_ctx | h02_me | 3 | what did Priya say in Slack about the collector | What did he say in Slack collector? |
| dt_en-IN_ctx | h03_me | 2 | open the Grafana dashboard for runtime manager | Open the Grafana Di code for runtime manager |
| dt_en-IN_ctx | h04_me | 5 | are any Kubernetes pods restarting on alpha | Arani ku spot restarting Mount Alpha |
| dt_en-IN_ctx | h05_me | 3 | summarise the last three comments on the merge request | The last three comments on the |
| dt_en-IN_ctx | h06_me | 3 | check if the Helm chart change is in the release branch | Check if the HR change is in the branch |
| dt_en-IN_ctx | h07_me | 7 | add a Jira comment saying the fix is deployed | Add Zira command, say the fixed card |
| dt_en-IN_ctx | h08_me | 4 | is the Databricks job still running | Still running |
| dt_en-IN_ctx | h09_me | 3 | search Confluence for the ArgoCD runbook | Search conference for the |
| dt_en-IN_ctx | h10_me | 3 | who is on call in PagerDuty today | Who is on a call in Teja duty today? |
| dt_en-IN_ctx | h11_me | 3 | start a local review before I push | Start a video before I finish |
| dt_en-IN_ctx | h12_me | 4 | draft a reply saying I'll join the CCB late | Reply saying, I'll join the |
| dt_en-IN_ctx | h13_me | 3 | how much disk is left on the Postgres volume | How much is left on the post? |
| dt_en-IN_ctx | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page? |
| dt_en-IN_none | h01_me | 3 | move PRJ-21604 to in review | Move to 1642 review |
| dt_en-IN_none | h02_me | 3 | what did Priya say in Slack about the collector | What did he say in Slack collector? |
| dt_en-IN_none | h03_me | 2 | open the Grafana dashboard for runtime manager | Open the code for runtime manager |
| dt_en-IN_none | h04_me | 5 | are any Kubernetes pods restarting on alpha | Arani ku spot restarting Mount Alpha |
| dt_en-IN_none | h05_me | 3 | summarise the last three comments on the merge request | The last three comments on the |
| dt_en-IN_none | h06_me | 3 | check if the Helm chart change is in the release branch | Check if the HR change is in the branch |
| dt_en-IN_none | h07_me | 7 | add a Jira comment saying the fix is deployed | Add Zira command, say the fixed card |
| dt_en-IN_none | h08_me | 4 | is the Databricks job still running | Still running |
| dt_en-IN_none | h09_me | 3 | search Confluence for the ArgoCD runbook | Search conference for the |
| dt_en-IN_none | h10_me | 3 | who is on call in PagerDuty today | Who is on a call in Teja duty today? |
| dt_en-IN_none | h11_me | 3 | start a local review before I push | Start a video before I finish |
| dt_en-IN_none | h12_me | 4 | draft a reply saying I'll join the CCB late | Reply saying, I'll join the |
| dt_en-IN_none | h13_me | 3 | how much disk is left on the Postgres volume | How much is left on the post? |
| dt_en-IN_none | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page? |
| dt_en-US_ctx | h01_me | 3 | move PRJ-21604 to in review | Move G216042 in review |
| dt_en-US_ctx | h02_me | 3 | what did Priya say in Slack about the collector | What did you say in Slack water collector |
| dt_en-US_ctx | h03_me | 1 | open the Grafana dashboard for runtime manager | Open the Grafana Dio for runtime manager |
| dt_en-US_ctx | h04_me | 4 | are any Kubernetes pods restarting on alpha | Restarting on Alpha |
| dt_en-US_ctx | h05_me | 2 | summarise the last three comments on the merge request | Summarize the last three comments on the quest |
| dt_en-US_ctx | h06_me | 3 | check if the Helm chart change is in the release branch | Check if the change is in the branch |
| dt_en-US_ctx | h07_me | 6 | add a Jira comment saying the fix is deployed | Add Jira send the fixes card |
| dt_en-US_ctx | h08_me | 4 | is the Databricks job still running | Data of still running |
| dt_en-US_ctx | h09_me | 4 | search Confluence for the ArgoCD runbook | Search for |
| dt_en-US_ctx | h10_me | 2 | who is on call in PagerDuty today | Who is on the call in PT today? |
| dt_en-US_ctx | h11_me | 3 | start a local review before I push | Start a video before I finish |
| dt_en-US_ctx | h12_me | 5 | draft a reply saying I'll join the CCB late | Reply I'll join the accessibility |
| dt_en-US_ctx | h13_me | 3 | how much disk is left on the Postgres volume | How much is left on the poster? |
| dt_en-US_ctx | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page? |
| dt_en-US_none | h01_me | 3 | move PRJ-21604 to in review | Move G216042 in review |
| dt_en-US_none | h02_me | 3 | what did Priya say in Slack about the collector | What did you say in Slack water collector? |
| dt_en-US_none | h03_me | 3 | open the Grafana dashboard for runtime manager | Open the Dio for manager |
| dt_en-US_none | h04_me | 4 | are any Kubernetes pods restarting on alpha | Restarting on Alpha |
| dt_en-US_none | h05_me | 2 | summarise the last three comments on the merge request | Summarize the last three comments on the quest |
| dt_en-US_none | h06_me | 3 | check if the Helm chart change is in the release branch | Check if the change is in the branch |
| dt_en-US_none | h07_me | 5 | add a Jira comment saying the fix is deployed | Add a comment in the fixes card |
| dt_en-US_none | h08_me | 4 | is the Databricks job still running | Data of still running |
| dt_en-US_none | h09_me | 4 | search Confluence for the ArgoCD runbook | Search for |
| dt_en-US_none | h10_me | 2 | who is on call in PagerDuty today | Who is on the call in PT today? |
| dt_en-US_none | h11_me | 3 | start a local review before I push | Start a video before I finish |
| dt_en-US_none | h12_me | 5 | draft a reply saying I'll join the CCB late | Reply I'll join the accessibility |
| dt_en-US_none | h13_me | 3 | how much disk is left on the Postgres volume | How much is left on the poster? |
| dt_en-US_none | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page? |
| st_en-IN_ctx | h01_me | 3 | move PRJ-21604 to in review | Move DJ 216042 in review. |
| st_en-IN_ctx | h02_me | 1 | what did Priya say in Slack about the collector | What did you say in slack about the collector? |
| st_en-IN_ctx | h03_me | 1 | open the Grafana dashboard for runtime manager | Open the Griffana dashboard for runtime manager. |
| st_en-IN_ctx | h04_me | 5 | are any Kubernetes pods restarting on alpha | Arani, cobonative spot, restarting on arrest. |
| st_en-IN_ctx | h05_me | 2 | summarise the last three comments on the merge request | Summarise the last three comments on the multi best. |
| st_en-IN_ctx | h06_me | 4 | check if the Helm chart change is in the release branch | Check if the MCR change is in the Rigi's Bunch. |
| st_en-IN_ctx | h07_me | 3 | add a Jira comment saying the fix is deployed | Had a Jira command, saying the fix is declared. |
| st_en-IN_ctx | h08_me | 1 | is the Databricks job still running | Is the database job still running? |
| st_en-IN_ctx | h09_me | 4 | search Confluence for the ArgoCD runbook | Search conference for the Albu Siri, Randu. |
| st_en-IN_ctx | h10_me | 2 | who is on call in PagerDuty today | Who is on a call in Pejarity today? |
| st_en-IN_ctx | h11_me | 2 | start a local review before I push | Start a local video before I finish. |
| st_en-IN_ctx | h12_me | 4 | draft a reply saying I'll join the CCB late | Dr replies, saying, I'll join the CCB. |
| st_en-IN_ctx | h13_me | 3 | how much disk is left on the Postgres volume | How much is is left on the poster calling? |
| st_en-IN_ctx | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page, please? |
| st_en-IN_none | h01_me | 3 | move PRJ-21604 to in review | Move DJ 216042 in review. |
| st_en-IN_none | h02_me | 1 | what did Priya say in Slack about the collector | What did you say in slack about the collector? |
| st_en-IN_none | h03_me | 1 | open the Grafana dashboard for runtime manager | Open the Griffana dashboard for runtime manager. |
| st_en-IN_none | h04_me | 5 | are any Kubernetes pods restarting on alpha | Arani, cobonative spot, restarting on arrest. |
| st_en-IN_none | h05_me | 2 | summarise the last three comments on the merge request | Summarise the last three comments on the multi best. |
| st_en-IN_none | h06_me | 4 | check if the Helm chart change is in the release branch | Check if the MCR change is in the Rigi's Bunch. |
| st_en-IN_none | h07_me | 3 | add a Jira comment saying the fix is deployed | Had a Jira command, saying the fix is declared. |
| st_en-IN_none | h08_me | 1 | is the Databricks job still running | Is the database job still running? |
| st_en-IN_none | h09_me | 4 | search Confluence for the ArgoCD runbook | Search conference for the Albu Siri, Randu. |
| st_en-IN_none | h10_me | 2 | who is on call in PagerDuty today | Who is on a call in Pejarity today? |
| st_en-IN_none | h11_me | 2 | start a local review before I push | Start a local video before I finish. |
| st_en-IN_none | h12_me | 4 | draft a reply saying I'll join the CCB late | Dr replies, saying, I'll join the CCB. |
| st_en-IN_none | h13_me | 3 | how much disk is left on the Postgres volume | How much is is left on the poster calling? |
| st_en-IN_none | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page, please? |
| st_en-US_ctx | h01_me | 3 | move PRJ-21604 to in review | Move DJ 216042 in review. |
| st_en-US_ctx | h02_me | 2 | what did Priya say in Slack about the collector | What did you say? You slack about the collector? |
| st_en-US_ctx | h03_me | 3 | open the Grafana dashboard for runtime manager | Open the Griffana diceboard for Untime Manager. |
| st_en-US_ctx | h04_me | 5 | are any Kubernetes pods restarting on alpha | Are any combinative sport, starting on a rest? |
| st_en-US_ctx | h05_me | 2 | summarise the last three comments on the merge request | Summarize the last three comments on the multi best. |
| st_en-US_ctx | h06_me | 4 | check if the Helm chart change is in the release branch | Check if the MCR change is in the reduce bunch. |
| st_en-US_ctx | h07_me | 4 | add a Jira comment saying the fix is deployed | Had a Gina command saying the fix is declared. |
| st_en-US_ctx | h08_me | 1 | is the Databricks job still running | Is the database job still running? |
| st_en-US_ctx | h09_me | 5 | search Confluence for the ArgoCD runbook | Such conflicts for the Algo City Randu. |
| st_en-US_ctx | h10_me | 2 | who is on call in PagerDuty today | Who is on a call in pejability today? |
| st_en-US_ctx | h11_me | 2 | start a local review before I push | Start a local video before I finish. |
| st_en-US_ctx | h12_me | 4 | draft a reply saying I'll join the CCB late | Doctor replies, saying, I'll join the CCB. |
| st_en-US_ctx | h13_me | 3 | how much disk is left on the Postgres volume | How much is is left on the poster calling? |
| st_en-US_ctx | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page please? |
| st_en-US_none | h01_me | 3 | move PRJ-21604 to in review | Move DJ 216042 in review. |
| st_en-US_none | h02_me | 2 | what did Priya say in Slack about the collector | What did you say? You slack about the collector? |
| st_en-US_none | h03_me | 3 | open the Grafana dashboard for runtime manager | Open the Griffana diceboard for Untime Manager. |
| st_en-US_none | h04_me | 5 | are any Kubernetes pods restarting on alpha | Are any combinative sport, starting on a rest? |
| st_en-US_none | h05_me | 2 | summarise the last three comments on the merge request | Summarize the last three comments on the multi best. |
| st_en-US_none | h06_me | 4 | check if the Helm chart change is in the release branch | Check if the MCR change is in the reduce bunch. |
| st_en-US_none | h07_me | 4 | add a Jira comment saying the fix is deployed | Had a Gina command saying the fix is declared. |
| st_en-US_none | h08_me | 1 | is the Databricks job still running | Is the database job still running? |
| st_en-US_none | h09_me | 5 | search Confluence for the ArgoCD runbook | Such conflicts for the Algo City Randu. |
| st_en-US_none | h10_me | 2 | who is on call in PagerDuty today | Who is on a call in pejability today? |
| st_en-US_none | h11_me | 2 | start a local review before I push | Start a local video before I finish. |
| st_en-US_none | h12_me | 4 | draft a reply saying I'll join the CCB late | Doctor replies, saying, I'll join the CCB. |
| st_en-US_none | h13_me | 3 | how much disk is left on the Postgres volume | How much is is left on the poster calling? |
| st_en-US_none | h15_me | 2 | what's blocking the ATLAS release | What's blocking the page please? |
| whisper_large-v3-v20240930_turbo_none | h04_me | 2 | are any Kubernetes pods restarting on alpha | Are any Kubernetes powered restarting on average? |
| whisper_large-v3-v20240930_turbo_none | h05_me | 3 | summarise the last three comments on the merge request | Summarize the last three commands on the multiquest |
| whisper_large-v3-v20240930_turbo_none | h07_me | 3 | add a Jira comment saying the fix is deployed | I had a Jira comment saying the fix is declared |
| whisper_large-v3-v20240930_turbo_none | h08_me | 1 | is the Databricks job still running | Is the database job still running? |
| whisper_large-v3-v20240930_turbo_none | h09_me | 4 | search Confluence for the ArgoCD runbook | Search conference for the Argo Chidi Ranbuk |
| whisper_large-v3-v20240930_turbo_none | h10_me | 1 | who is on call in PagerDuty today | Who is on call in Pajabuki today? |
| whisper_large-v3-v20240930_turbo_none | h11_me | 1 | start a local review before I push | Start a local review before I hit. |
| whisper_large-v3-v20240930_turbo_none | h12_me | 4 | draft a reply saying I'll join the CCB late | After reply saying, "I'll join the CC balloon." |
| whisper_large-v3-v20240930_turbo_none | h13_me | 1 | how much disk is left on the Postgres volume | How much disk is left on the postgrade volume? |
| whisper_large-v3-v20240930_turbo_none | h15_me | 1 | what's blocking the ATLAS release | what's blocking the page release. |
| whisper_large-v3-v20240930_turbo_prompt | h01_me | 2 | move PRJ-21604 to in review | Move PRJ-216042 in review. |
| whisper_large-v3-v20240930_turbo_prompt | h04_me | 2 | are any Kubernetes pods restarting on alpha | Are any Kubernetes powered restarting on average? |
| whisper_large-v3-v20240930_turbo_prompt | h05_me | 1 | summarise the last three comments on the merge request | Summarize the last three commands on the merge request. |
| whisper_large-v3-v20240930_turbo_prompt | h07_me | 3 | add a Jira comment saying the fix is deployed | I had a Jira comment saying the fix is declared. |
| whisper_large-v3-v20240930_turbo_prompt | h09_me | 2 | search Confluence for the ArgoCD runbook | Search conference for the ArgoCD, Rangu. |
| whisper_large-v3-v20240930_turbo_prompt | h10_me | 1 | who is on call in PagerDuty today | Who is on call in Pajabuki today? |
| whisper_large-v3-v20240930_turbo_prompt | h12_me | 3 | draft a reply saying I'll join the CCB late | After reply saying, I'll join the CCB route. |
| whisper_large-v3-v20240930_turbo_prompt | h13_me | 1 | how much disk is left on the Postgres volume | How much disk is left on the postgrade volume? |
| whisper_large-v3-v20240930_turbo_prompt | h15_me | 1 | what's blocking the ATLAS release | What's blocking the page release? |
| whisper_large-v3-v20240930_turbo_sentence | h01_me | 2 | move PRJ-21604 to in review | Move PRJ-216042 in review. |
| whisper_large-v3-v20240930_turbo_sentence | h04_me | 1 | are any Kubernetes pods restarting on alpha | Are any Kubernetes pods restarting on average? |
| whisper_large-v3-v20240930_turbo_sentence | h05_me | 3 | summarise the last three comments on the merge request | Summarize the last three commands on the multiquest. |
| whisper_large-v3-v20240930_turbo_sentence | h07_me | 3 | add a Jira comment saying the fix is deployed | I had a Jira comment saying the fix is declared. |
| whisper_large-v3-v20240930_turbo_sentence | h09_me | 1 | search Confluence for the ArgoCD runbook | Search Confluence for the ArgoCD Rangu. |
| whisper_large-v3-v20240930_turbo_sentence | h10_me | 1 | who is on call in PagerDuty today | Who is on call in Pajabuki today? |
| whisper_large-v3-v20240930_turbo_sentence | h11_me | 1 | start a local review before I push | Start a local review before I hit. |
| whisper_large-v3-v20240930_turbo_sentence | h12_me | 5 | draft a reply saying I'll join the CCB late | After reply saying I will join the CCB meeting. |
| whisper_large-v3-v20240930_turbo_sentence | h13_me | 1 | how much disk is left on the Postgres volume | How much disk is left on the Postgre volume? |
| whisper_large-v3-v20240930_turbo_sentence | h15_me | 1 | what's blocking the ATLAS release | What's blocking the page release? |
