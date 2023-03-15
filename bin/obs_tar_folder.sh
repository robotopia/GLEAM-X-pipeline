#! /bin/bash

endpoint='146.118.69.100' #HOST is already used as a keyword in other script
user='ubuntu'
remote='/mnt/dav/GLEAM-X/Archived_Obsids'

usage()
{
echo "obs_tar_folder.sh [-d dep] [-p project] [-a account] [-u user] [-t] obsnum

Tars an entire obsid folder and its contents in order to reduce the number of individual files being tracked by a file system. Useful for cases where filesystems have quota limits.

By default the obsid folder will be tarred (no compression) and then removed. The reverse operation is supported. 

  -d dep      : job number for dependency (afterok)
  -p project  : project, (must be specified, no default)
  -u          : un-tar the previously tarred observation folder (default: False)
  -t          : test. Don't submit job, just make the batch file
                and then return the submission command
  obsnum      : the obsid to process, or a text file of obsids (newline separated). 
               A job-array task will be submitted to process the collection of obsids. " 1>&2;
exit 1;
}

pipeuser="${GXUSER}"

#initial variables
dep=
tst=
mode='c'

# parse args and set options
while getopts ':td:a:p:u' OPTION
do
    case "$OPTION" in
	d)
	    dep=${OPTARG}
	    ;;
    a)
        account=${OPTARG}
        ;;
    p)
        project=${OPTARG}
        ;;
	t)
	    tst=1
	    ;;
	u)
	    mode='d'
	    ;;
	? | : | h)
	    usage
	    ;;
  esac
done
# set the obsid to be the first non option
shift  "$(($OPTIND -1))"
obsnum=$1

queue="-p ${GXSTANDARDQ}"
base="${GXSCRATCH}/${project}"

# if obsid is empty then just print help

if [[ -z ${obsnum} ]] || [[ -z $project ]] || [[ ! -d ${base} ]]
then
    usage
fi

if [[ ! -z ${dep} ]]
then
    if [[ -f ${obsnum} ]]
    then
        depend="--dependency=aftercorr:${dep}"
    else
        depend="--dependency=afterok:${dep}"
    fi
fi

if [[ ! -z ${GXACCOUNT} ]]
then
    account="--account=${GXACCOUNT}"
fi

# Establish job array options
if [[ -f ${obsnum} ]]
then
    numfiles=$(wc -l "${obsnum}" | awk '{print $1}')
    jobarray="--array=1-${numfiles}"
else
    numfiles=1
    jobarray=''
fi

# start the real program
script="${GXSCRIPT}/tar_folder_${obsnum}.sh"
cat "${GXBASE}/templates/tar_folder.tmpl" | sed -e "s:OBSNUM:${obsnum}:g" \
                                 -e "s:BASEDIR:${base}:g" \
                                 -e "s:TARMODE:${mode}:g" \
                                 -e "s:PIPEUSER:${pipeuser}:g"  > "${script}"

output="${GXLOG}/tar_folder_${obsnum}.o%A"
error="${GXLOG}/tar_folder_${obsnum}.e%A"

if [[ -f ${obsnum} ]]
then
   output="${output}_%a"
   error="${error}_%a"
fi


chmod 755 "${script}"

# sbatch submissions need to start with a shebang
echo '#!/bin/bash' > ${script}.sbatch
echo "srun --cpus-per-task=1 --ntasks=1 --ntasks-per-node=1 singularity run ${GXCONTAINER} ${script}" >> ${script}.sbatch

if [ ! -z ${GXNCPULINE} ]
then
    # zip_ms only needs a single CPU core
    GXNCPULINE="--ntasks-per-node=1"
fi

sub="sbatch --begin=now+5minutes  --export=ALL --time=04:00:00 --mem=24G -M ${GXCOMPUTER} --output=${output} --error=${error} "
sub="${sub}  ${GXNCPULINE} ${account} ${GXTASKLINE} ${jobarray} ${depend} ${queue} ${script}.sbatch"

if [[ ! -z ${tst} ]]
then
    echo "script is ${script}"
    echo "submit via:"
    echo "${sub}"
    exit 0
fi
    
# submit job
jobid=($(${sub}))
jobid=${jobid[3]}

echo "Submitted ${script} as ${jobid} . Follow progress here:"

for taskid in $(seq ${numfiles})
    do
    # rename the err/output files as we now know the jobid
    obserror=$(echo "${error}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")
    obsoutput=$(echo "${output}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")

    if [[ -f ${obsnum} ]]
    then
        obs=$(sed -n -e "${taskid}p" "${obsnum}")
    else
        obs="${obsnum}"
    fi

    if [ "${GXTRACK}" = "track" ]
    then
    # record submission
    ${GXCONTAINER} track_task.py queue --jobid="${jobid}" --taskid="${taskid}" --task='tar_folder' --submission_time="$(date +%s)" --batch_file="${script}" \
                        --obs_id="${obs}" --stderr="${obserror}" --stdout="${obsoutput}"
    fi

    echo "${obsoutput}"
    echo "${obserror}"
done
