#!/bin/bash
# Phil Bendeck
########################################
# Version 1 | 02/01/22-02/08/22
# Includes support for CDM6
########################################
set -e
#set -x
###################################################################################################################################
# Log
log=$(readlink -f ./$(hostname)_gcp_orchestrator_"$(date +"%m_%d_%Y")".log)
exec > >(tee -a ./$(hostname)_gcp_orchestrator_"$(date +"%m_%d_%Y")".log)
timestamp="$(date +"%m-%d-%Y %H:%M:%S") | INFO |"

###################################################################################################################################
# User Defined Variables
## CDM6 URL
CDM6URL="https://storage.googleapis.com/rubrik-pb-bucket/rubrik-6-0-2-p2-13398-gcp-cloud-cluster.zip"
ZIPARCHIVE=$(echo $CDM6URL | cut -d "/" -f5)
CDMVERSION=$(echo $ZIPARCHIVE | sed  's/-gcp-cloud-cluster.zip//g')
###################################################################################################################################
# Functions
###################################################################################################################################
# List available project IDs
PROJECT_ID_ARRAY(){
array=( $(gcloud projects list --sort-by=projectId | grep -v "NAME\|PROJECT_NUMBER" | awk {'print $2'}) )
shopt -s dotglob
shopt -s nullglob
PS3="Select Project ID: "
echo "--> There are ${#array[@]} project IDs in GCP to select from:"; \
sleep 1
select project_id in "${array[@]}"; do echo "--> You selected Project ID: ${project_id}"; break; done
}
###################################################################################################################################
# List available Zone IDs
ZONE_ID_ARRAY(){
array=( $(gcloud compute zones list --sort-by=zone | grep -v "REGION\|STATUS\|NEXT_MAINTENANCE\|TURNDOWN_DATE" | awk {'print $2'}) )
shopt -s dotglob
shopt -s nullglob
PS3="Select the GCP Zone to place "[${instancesarray[@]}]" in: "
echo "--> There are ${#array[@]} zones in GCP to select from:"; \
sleep 1
select zone_id in "${array[@]}"; do echo "--> You selected zone: ${zone_id}"; break; done
}
###################################################################################################################################
# List available VPCs
VPC_ID_ARRAY(){
array=( $(gcloud compute networks list | grep -v "SUBNET_MODE\|BGP_ROUTING_MODE\|IPV4_RANGE\|GATEWAY_IPV4" | awk {'print $2'} ))
shopt -s dotglob
shopt -s nullglob
PS3="Select the VPC to network the "[${instancesarray[@]}]" in: "
echo "--> There are ${#array[@]} VPCs in GCP to select from:"; \
sleep 1
select vpc_id in "${array[@]}"; do echo "--> You selected zone: ${vpc_id}"; break; done
}
###################################################################################################################################
# List of Subnets
SUBNET_ID_ARRAY(){
array=( $(gcloud compute networks subnets list | grep -v "REGION\|NETWORK\|RANGE\|STACK_TYPE\|IPV6_ACCESS_TYPE\|IPV6_CIDR_RANGE\|EXTERNAL_IPV6_CIDR_RANGE" | awk {'print $2'} ))
shopt -s dotglob
shopt -s nullglob
PS3="Select the subnet to attach "[${instancesarray[@]}]" to: "
echo "--> There are ${#array[@]} subnets in GCP to select from:"; \
sleep 1
select subnet_id in "${array[@]}"; do echo "--> You selected zone: ${subnet_id}"; break; done
}
###################################################################################################################################
# Deploy function (downloads Rubrik CDM files, generates JSON key, and execute cluster creation in GCP)
#DEPLOY(){

# Temporary workaround for project ID
#PROJECT_ID_ARRAY

#}
###################################################################################################################################
# Direct Cloud Shell Deployment (Function must be called from the gcloud cloud-shell ssh)
GCPSHELL(){
while true
do
echo -e "$timestamp --> This function is designed to ONLY run in the GCP Cloud Shell Environment\n"
sleep .1
read -r -p "--> Would you like to deploy CDM6 via GCP $(hostname) [Yes or No]: " input

# Only if YES is inputted by the user; the script will continue
case $input in
[yY][eE][sS]|[yY])

# Ask the end-user a seriues of questions in order to create the following:
# 1. Create an IAM role
# 2. Add permissions to the role
# 3. Create a service account
# 4. Assign the IAM role to the service account
# 5. Create and retreive a JSON based key

# Prompt the end-user to create a role
echo -e "$timestamp --> An IAM deployment role is required in order to deploy the Rubrik CDM cluster\n"
sleep .1
read -r -p "--> Enter the name of IAM Role [DeploymentRubrikRole]: " rolename
echo "$timestamp --> "$USER inputted role name = $rolename

# Prompt the end-user to assign the role to a project
echo "$timestamp --> The script will now scan GCP for the available GCP Project IDs:"

# Call the PROJECT_ID_ARRAY function
PROJECT_ID_ARRAY

# Output the permission roles that will be assigned the IAM role
echo "$timestamp --> The following permissions are required to be assigned to $rolename"
cat << EOF
accessapproval.requests.dismiss
compute.disks.create
compute.globalOperations.get
compute.images.create
compute.images.get
compute.images.getIamPolicy
compute.images.useReadOnly
compute.instances.create
compute.instances.get
compute.instances.getSerialPortOutput
compute.instances.setDeletionProtection
compute.subnetworks.get
compute.subnetworks.use
EOF

# Create role
gcloud iam roles create $rolename --project=$project_id --title=$rolename --description="GCP Deployment" --permissions=accessapproval.requests.dismiss,compute.disks.create,compute.globalOperations.get,compute.images.create,compute.images.get,compute.images.getIamPolicy,compute.images.useReadOnly,compute.instances.create,compute.instances.get,compute.instances.getSerialPortOutput,compute.instances.setDeletionProtection,compute.subnetworks.get,compute.subnetworks.use

# Display role creation
gcloud iam roles describe --project=$project_id $rolename

# Create service account
echo "$timestamp --> An IAM Service Account is required in order to deploy the Rubrik CDM Cluster"
sleep .1
read -r -p "--> Enter the name of the IAM Service Account [svc-deployment-role]: " svcaccount
echo "$timestamp --> "$USER inputted Service Account name = $svcaccount    
gcloud iam service-accounts create $svcaccount \
--description="Service Account with Deployment Role Assigned for Rubrik Cloud Cluster Deployment" \
--display-name="$svcaccount"

# Assign role to IAM Service Account
gcloud projects add-iam-policy-binding $project_id --member="serviceAccount:$svcaccount@$project_id.iam.gserviceaccount.com" --role="projects/$project_id/roles/$rolename"

# Make directory to store GCP files
echo "$timestamp --> Creating directory @ ${HOME}/cdm6"
mkdir -v ${HOME}/cdm6
cd ${HOME}/cdm6

# Create and generate JSON key for the service account
gcloud iam service-accounts keys create ${project_id}_$(date +"%m_%d_%Y").json --iam-account=$svcaccount@$project_id.iam.gserviceaccount.com
echo -e "$timestamp --> Key stored at path $HOME/cdm6/${project_id}_$(date +"%m_%d_%Y").json\n"
# temp
keyname=$(ls $HOME/cdm6/| grep json)

# Download and unzip GCP Rubrik files
echo -e "$timestamp --> Downloading CDM6 GCP files in order to orchestrate the cluster deployment @ ${HOME}/cdm6\n"
wget -q -P ${HOME}/cdm6 $CDM6URL
echo -e "$timestamp --> Extracting ${ZIPARCHIVE}"
unzip -j ${HOME}/cdm6/${ZIPARCHIVE}

# Customer details
echo -e "$timestamp --> The installer script will request the required parameters that will be saved as customer_details.yaml\n"

# Customer input node type
echo -e "$timestamp --> Choose standard or dense node type. Default = dense.\n"
while true; do
    echo -n "Enter the type of node [ standard | dense ]: " 
    read -r nodetype
    case $nodetype in
        standard* ) break;;
        dense* ) break;;
        * ) echo "Please answer standard or dense.";;
    esac
done
echo -e "$timestamp --> Node type = $nodetype\n"

# Customer input to enable deletation proection on the instance
echo -e "$timestamp --> Choose to configure the VM compute instances with deletion protection. Default = yes\n"
    while true; do
    echo -n "Enter yes or no to enable or disable deletion protection on the VM compute instances [ yes | no ]: " 
    read -r deletionprotection
    case $deletionprotection in
        [yes]* ) break;;
        [no]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done
echo -e "$timestamp --> Deletion proection will be set to $deletionprotection\n"

# Input the number of disks
echo -e "$timestamp --> Choose the number of disks to configure. Default = 3. (Maximum supported disks = 6)\n"
while true; do
echo -n "Enter the number of disks to configure: " 
read -r numberofdisks
if [ $numberofdisks -gt "2" -a $numberofdisks -lt "7" ]
then
    echo "The number disk ($numberofdisks) inputted meets the mininum requirements for the GCP orchestration"
    break
else
    echo "The number of disks ($numberofdisks) does not meet the mininum requirements for the GCP orchestration. Try again."
fi
done
echo -e "$timestamp --> The number of disks inputted = $numberofdisks\n"

# Warning about disk sizes
cat << EOF
####################### PLEASE READ #######################
# Enter disk size in GB. 1 TB = 1000 GB. Default = 2000   #
# Minimum disk size for standard nodes: 500 GB.           #
# Minimum disk size for dense nodes: 2000 GB.             #
# Total size for standard nodes: 1500 GB to 6000 GB.      #
# Total size for dense nodes: 6000 GB to 24000 GB.        #
# All disks will be the same size.                        #
###########################################################
EOF

# Customer input to create the size of the disks
echo -e "$timestamp --> Choose the size of the disk to configure for the VM compute instances. (Refer to the table above for details)\n"
while true; do
echo -n "Enter the size of the disk: " 
read -r disksize
if [ $disksize -gt "499" ]
then
    echo "The disk ($disksize)GB size inputted meets the mininum requirements for the GCP orchestration"
    break
else
    echo "The $disksize GB disk size does not meet the mininum requirements for the GCP orchestration. Try again."
fi
done
echo -e "$timestamp --> The disk size inputted = $disksize GB\n"

# Customer input the name of the nodes
while true; do
echo -n "Please enter the instance names for the VMs (seperated by a space): " 
read -r -a instancesarray
if [ "${#instancesarray[@]}" -ge "4" ]
then
    echo "$timestamp --> The "${#instancesarray[@]}" instance names entered, meets the GCP requirements."
    for instances in "${instancesarray[@]}"; do 
    echo "--> VM instance name: $instances";
    done
    break
else
    echo "The mininum number of GCP instances required = 4. Please enter (4) unique instance names."
fi
done

# Variable for YAML (customer_details.yaml)
yamlinstancelist=$(for instancelist in ${instancesarray[@]};do echo "  - $instancelist";done)

# Select GCP Zones
ZONE_ID_ARRAY

# Select VPC
VPC_ID_ARRAY

# Select Subnet
SUBNET_ID_ARRAY

# echo yaml file out
echo "$timestamp --> Generating the customer_details.yml file to deploy the Rubrik CDM cluster"
cat << EOF > ${HOME}/cdm6/customer_details.yml
cluster_details:
  node_type: ${nodetype}
  deletion_protection: ${deletionprotection}
  disks_per_node: ${numberofdisks}
  disk_size_gb: ${disksize}
  node_names:
${yamlinstancelist}
platform_details:
  platform: gcp
  base_node_image: ${CDMVERSION}
  credentials_file: ${keyname}
  project: ${project_id}
  zone: ${zone_id}
  vpc: ${vpc_id}
  subnet: ${subnet_id}
EOF

# Execute VM instance creation
cd ${HOME}/cdm6
chmod u+x deploy_rubrik_cluster.py 
./deploy_rubrik_cluster.py --deployment_details_file customer_details.yml

break
;;
    [nN][oO]|[nN])
echo "$timestamp --> No has been selected; exiting script."
exit
        ;;
    *)
echo "$timestamp --> Invalid input..."
;;
esac
done
echo -e "$timestamp --> Log file is saved at $log\n"
}

###################################
# Main Script Logic Starts Here   #
###################################
case "$1" in
    gcpdeploy)
            GCPSHELL
            ;;
    beta1)
            #BETA1
            ;;
    beta2)
            #BETA2
            ;;
    *)
            echo "Name $0"
            echo ""                
            echo "Usage: $0 [ gcpdeploy | beta1 | beta2 ]"
            echo ""
            echo "Parameter Descriptions:"
            echo "gcpdeploy         Executes the orchestration process to create Rubrik CDM cluster on GCP."
            echo "beta1             Placeholder"
            echo "beta2             Placeholder"
            echo
esac
