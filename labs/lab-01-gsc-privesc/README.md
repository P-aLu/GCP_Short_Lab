DEPLOYMENT_UID = [random-uid]

## 1 - Initial Access

Let's say that you ve stolen a GCP Private Access Key of the user "training-start@$DEPLOYMENT_UID-deployments-palu.serviceaccount.google.com, you can't do anything except :
	- Listing Storage
	- Get Storage `[random-uid]-deployments`
	- Get items into storage `[random-uid]-deployments`

There are a lot of `deployment-[random_aa/mm/dd_dates].log` and deployment-[random_aa/mm/dd_dates].txt but there is also one `$DEPLOYMENT_UID-deployment.tfstate` file containing:
	- all the previous data
	- GCP `[random-uid]-deployments-sql-compute` compute instance deployment with SSH private key within
	- firewall that blocks the access to SQL Database Instance `[random-uid]-deployments-sql` that only accept access from the compute instance `[random-uid]-deployments-sql-compute`
	- SQL Database Instance `[random-uid]-deployments-sql` with a table `Web APIs` that contains user, password and url for a given Cloudfunction into another project (check ## 2)
