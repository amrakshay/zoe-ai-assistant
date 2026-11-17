| Run | Same | Partial | Wrong |
|---|---|---|---|
| st_en-IN_none | 6/15 | 5/15 | 4/15 |
| whisper_large-v3-v20240930_turbo_none | 12/15 | 1/15 | 2/15 |
| whisper_large-v3-v20240930_turbo_prompt | 11/15 | 4/15 | 0/15 |
| whisper_large-v3-v20240930_turbo_sentence | 10/15 | 4/15 | 1/15 |

| Run | Id | Transcript | Claude's reading | Reference | Grade |
|---|---|---|---|---|---|
| st_en-IN_none | h01_me | Move DJ 216042 in review. | Move PRJ-216042 to In Review. | move PRJ-21604 to in review | partial |
| st_en-IN_none | h02_me | What did you say in slack about the collector? | What did I say in Slack about the collector? | what did Priya say in Slack about the collector | wrong |
| st_en-IN_none | h04_me | Arani, cobonative spot, restarting on arrest. | Are the Kubernetes pods restarting on Gamma? (?) | are any Kubernetes pods restarting on alpha | partial |
| st_en-IN_none | h06_me | Check if the MCR change is in the Rigi's Bunch. | Check if the MR change is in the release branch. (?) | check if the Helm chart change is in the release branch | partial |
| st_en-IN_none | h09_me | Search conference for the Albu Siri, Randu. | Search Confluence for the ADR about runtime. (?) | search Confluence for the ArgoCD runbook | wrong |
| st_en-IN_none | h11_me | Start a local video before I finish. | Start a local review before I finish. (?) | start a local review before I push | partial |
| st_en-IN_none | h12_me | Dr replies, saying, I'll join the CCB. | Draft a reply saying I'll join the CCB. | draft a reply saying I'll join the CCB late | partial |
| st_en-IN_none | h13_me | How much is is left on the poster calling? | How much is left on the pull request pipeline? (?) | how much disk is left on the Postgres volume | wrong |
| st_en-IN_none | h15_me | What's blocking the page, please? | What's blocking the pipeline, please? (?) | what's blocking the ATLAS release | wrong |
| whisper_large-v3-v20240930_turbo_none | h04_me | Are any Kubernetes powered restarting on average? | Are any Kubernetes pods restarting on average? (?) | are any Kubernetes pods restarting on alpha | wrong |
| whisper_large-v3-v20240930_turbo_none | h05_me | Summarize the last three commands on the multiquest | Summarize the last three commands on the multi-quest (?) | summarise the last three comments on the merge request | wrong |
| whisper_large-v3-v20240930_turbo_none | h12_me | After reply saying, "I'll join the CC balloon." | Draft a reply saying, "I'll join the CCB call." (?) | draft a reply saying I'll join the CCB late | partial |
| whisper_large-v3-v20240930_turbo_prompt | h01_me | Move PRJ-216042 in review. | Move PRJ-21642 to In Review. | move PRJ-21604 to in review | partial |
| whisper_large-v3-v20240930_turbo_prompt | h04_me | Are any Kubernetes powered restarting on average? | Are any Kubernetes pods restarting unusually? | are any Kubernetes pods restarting on alpha | partial |
| whisper_large-v3-v20240930_turbo_prompt | h12_me | After reply saying, I'll join the CCB route. | Draft a reply saying I'll join the CCB meeting. (?) | draft a reply saying I'll join the CCB late | partial |
| whisper_large-v3-v20240930_turbo_prompt | h15_me | What's blocking the page release? | What's blocking the next release? (?) | what's blocking the ATLAS release | partial |
| whisper_large-v3-v20240930_turbo_sentence | h01_me | Move PRJ-216042 in review. | Move PRJ-216042 to In Review. | move PRJ-21604 to in review | partial |
| whisper_large-v3-v20240930_turbo_sentence | h04_me | Are any Kubernetes pods restarting on average? | Are any Kubernetes pods restarting unusually (?) | are any Kubernetes pods restarting on alpha | partial |
| whisper_large-v3-v20240930_turbo_sentence | h05_me | Summarize the last three commands on the multiquest. | Summarize the last three commands on the multi-quest (?) | summarise the last three comments on the merge request | wrong |
| whisper_large-v3-v20240930_turbo_sentence | h12_me | After reply saying I will join the CCB meeting. | Draft a reply saying I will join the CCB meeting. | draft a reply saying I'll join the CCB late | partial |
| whisper_large-v3-v20240930_turbo_sentence | h15_me | What's blocking the page release? | What's blocking the next release? (?) | what's blocking the ATLAS release | partial |
