#!/bin/bash

echo "== Creating the LZ deployment == "
echo ""


while (( "$#" )); do
  case "$1" in
    -f|--folder-id)
      PARENT_FOLDER_ID=$2
      shift 2
      ;;
    -b|--billing-account)
      BILLING_ID=$2
      shift 2
      ;;
    -r|--repo-branch )
      REPO_BRANCH=$2
      shift 2
      ;;
    -o|--org-id)
      ORG_ID=$2
      shift 2
      ;;
    -l|--labels)
      LABELS=$2
      shift 2
      ;;
    -nl|--no-labels)
      NO_LABELS=1
      shift 
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    --*=|-*) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # unsupported positional arguments
      echo "Error: Unsupported positional argument $1" >&2
      shift
      ;;
  esac
done

## ARG CHECKING

# we need on or the other
if [[ -z ${BILLING_ID} && -z ${PARENT_FOLDER_ID} ]] || [[ -z ${BILLING_ID} && -z ${ORG_ID} ]]; then
  #echo "ERROR: Invalid arguments."
  echo "Error: Either Organisation or Folder ID needs to be provided with a Billing Account"
  exit 1
fi

if [[ -n ${ORG_ID} && -n ${PARENT_FOLDER_ID} ]]; then
  #echo "ERROR: Invalid arguments."
  echo "Error: Either Organisation or Folder ID needs to be provided, not both"
  exit 1
fi

if [[ -z ${LABELS} && ${NO_LABELS} -eq 0 ]]; then
  echo "Error: Labels must either be provided or overriden with the --no-labels flag."
  exit 1
fi

if [[ ${NO_LABELS} -eq 0 ]]; then
  IFS=',' read -r -a array <<< "${LABELS}"

  for index in "${!array[@]}"
  do
      IFS='=' read -r -a array2 <<< "${array[index]}"
      costcode=$(( costcode + $( echo "${array2[0]}" | grep -c "cost-code") ))
      team=$(( team + $( echo "${array2[0]}" | grep -c "team") ))
  done

  if ! [ $costcode -eq 1 ] || ! [ $team -eq 1 ]; then
        if ! [ $costcode -eq 1 ]; then
          printf "%s\n" "Ensure you have a cost-code label and only one"
          printf "%s\n" "e.g. $ ./tb-config-creator -l cost-code=value,team=tranquility-base"
        fi
        if ! [ $team -eq 1 ]; then
          printf "%s\n" "Ensure you have a team label and only one"
          printf "%s\n" "e.g. $ ./tb-config-creator -l cost-code=value,team=tranquility-base"
        fi
        exit 1
  fi
fi

## ARG CHECKING

if [[ -z ${REPO_BRANCH}  ]]; then
  echo "no branch selected"
  echo "deploying from master"
  repo_branch="master"
fi


export FOLDER_ID=$PARENT_FOLDER_ID
export BILLING_ID=$BILLING_ID
export REPO_BRANCH=$REPO_BRANCH
export ORG_ID=$ORG_ID


echo ""
echo " FOLDER_ID: ${PARENT_FOLDER_ID}"
echo " BILLING_ID: ${BILLING_ID}"
echo " REPO_BRANCH: ${REPO_BRANCH}"
echo " ORG_ID: ${ORG_ID}"

main (){
  

  # ===== Git
  rm -rf tb-gcp
  git clone https://github.com/tranquilitybase-io/tb-gcp.git
  cd tb-gcp
  if [[ -z ${REPO_BRANCH} ]]; then
    REPO_BRANCH="master"
  fi
  git checkout ${REPO_BRANCH}

  # ===== Allocate rnd_id
  RND_ID="$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 8 | sed '/^[0-9]*$/d' | head -n 1)"
  export TB_ID=${RND_ID}
  expected_folder="Tranquility Base - "${RND_ID}
  echo ""
  echo " ================= "
  echo "   TB_ID: ${TB_ID}"
  echo " ================= "
  echo ""


  # ===== GCP bootstrap setup
  if [[ ${NO_LABELS} -eq 1 && -z ${ORG_ID} ]]; then

    tb-marketplace/tb-config-creator/tb-config-creator -r ${TB_ID} -f $PARENT_FOLDER_ID -b $BILLING_ID -nl

  elif [[ ${NO_LABELS} -eq 0 && -z ${PARENT_FOLDER_ID} ]]; then

    tb-marketplace/tb-config-creator/tb-config-creator -r ${TB_ID} -o $ORG_ID -b $BILLING_ID -l ${LABELS}
  
  elif [[ ${NO_LABELS} -eq 1 && -n ${ORG_ID} ]]; then
  
    tb-marketplace/tb-config-creator/tb-config-creator -r ${TB_ID} -o $ORG_ID -b $BILLING_ID -nl
  
  else 
    
    tb-marketplace/tb-config-creator/tb-config-creator -r ${TB_ID} -f $PARENT_FOLDER_ID -b $BILLING_ID -l ${LABELS}

  fi


  # ==== Get generated folder ID 
  export TB_FOLDER_ID=$(gcloud resource-manager folders list --folder=${PARENT_FOLDER_ID} --filter displayName:"${TB_ID}" --format='value(ID)')
  echo "Generated folder id: ${TB_FOLDER_ID}"

  # ==== Run deployment manager
  gcloud config set project bootstrap-${TB_ID}

  if [[ "$REPO_BRANCH" == "master" ]]; then
    sed -i "s/rootId:.*/rootId: '${TB_FOLDER_ID}'/; s/billingAccountId:.*/billingAccountId: '${BILLING_ID}'/" tb-marketplace/tb-dep-manager/test_config.yaml
    gcloud deployment-manager deployments create bootstrap-resources --config tb-marketplace/tb-dep-manager/test_config.yaml
  else
    sed -i "s@gft-group-public/global/images/tranquility-base-bootstrap-master@tb-marketplace-dev/global/images/tranquility-base-bootstrap-${REPO_BRANCH}@" tb-marketplace/tb-dep-manager/tranquility-base.jinja
    sed -i "s/rootId:.*/rootId: '${TB_FOLDER_ID}'/; s/billingAccountId:.*/billingAccountId: '${BILLING_ID}'/" tb-marketplace/tb-dep-manager/test_config.yaml
    gcloud deployment-manager deployments create $REPO_BRANCH --config tb-marketplace/tb-dep-manager/test_config.yaml
  fi

  ZONE=$(gcloud compute instances list --format "value(ZONE)" --limit=1)
  TF_SERVER_INTERNAL_IP=$(gcloud compute instances describe tf-server-${TB_ID} --zone=${ZONE} --format='get(networkInterfaces[0].networkIP)')
  # ===== SSH to bastion
  rm /tmp/sshkey
  ssh-keygen -b 2048 -t rsa -f /tmp/sshkey -q -N ""
  gcloud compute config-ssh
  gcloud compute --project "bootstrap-${TB_ID}" ssh tf-server-${TB_ID} --zone ${ZONE} --force-key-file-overwrite 2>/dev/nullrc=$? \ 
  --command="sudo /opt/tb/repo/tb-gcp-tr/landingZone/tb-welcome"
}

echo ""
echo "Runtime total:"
time main



