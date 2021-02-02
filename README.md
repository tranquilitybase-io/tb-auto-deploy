# tb-auto-deploy
Code for the auto deployment of Tranquility Base
Auto-deploy Script

A wrapper for the deployment process, simplifies deployment of tb.

Can be used to deploy under the org or the folder.

There is some duplication of logic so that config-creator can be run independently.
Labels can still be added with the –l flag, or overridden with -nl

Limitations:
	Random_id cannot be passed to auto_deploy

USAGE

auto_deploy.sh --folder-id <FOLDER_ID> --billing-account <BILLING_ACCOUNT> -nl

auto_deploy.sh –-org-id <ORG_ID> --billing-account <BILLING_ACCOUNT> -nl

auto_deploy.sh –-repo-branch <REPO_BRANCH_NAME> --folder-id <FOLDER_ID> --billing-account <BILLING_ACCOUNT> -nl

auto_deploy.sh –-repo-branch <REPO_BRANCH_NAME> --org-id <ORG_ID> --billing-account <BILLING_ACCOUNT> -nl



