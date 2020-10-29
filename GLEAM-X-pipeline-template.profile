#! /bin/bash -l

echo "loading profile"
module load singularity

cluster=                        # System-wide name of cluster

GXUSER=$(whoami)
export GXUSER
export GXBASE=                  # Path to base of GLEAM-X Pipeline
export GXSCRATCH=               # Path to scratch space used for processing
export GXCONTAINER=             # Absolute path to the GLEAM-X singularity container
export GXCOMPUTER=${cluster}    # Maintained for compatability
export GXCLUSTER=${cluster}     # Maintained for compatability
export GXSTANDARDQ=             # Slurm queue to submit tasks to
export GXABSMEM=60              # Absolute memory a machine should be considered to have 
export GXMEMORY=50              # Typical memory a job should request
export GXNCPUS=48               # Number of CPUs of each machine, to be phased out
export GXNLCPUS=48              # Number of logical CPUs of each machine (i.e. hyper-threaded)
export GXNPCPUS=48              # Number of physical CPUs of each machine
export GXTASKLINE=              # Reserved space for additional slurm sbatch options, if needed
export GXLOG=                   # Path to output task logs, i.e. ${GXBASE}/queue/logs
export GXSCRIPT=                # Path to place generated template scripts. i.e. "${GXBASE}/queue"
export GXFMODELS=               # Directory path containing bright source models for peeling. NOTE: Not yet implemented 
export GXTRACK='no-track'       # Directive to inform task tracking for meta-database. 'track' will track task progression. Anything else will disable tracking. 
export GXSSH=                   # Path to SSH keys to be used for archiving. Keys names should follow a 'gx_${GXUSER}' convention, i.e. "${GXBASE}/ssh_keys/gx_${GXUSER}"
                                # Ensure restricted folder/file permissions, i.e. cmod -R 700 "${GXBASE}/ssh_keys"
                                # Keys can be generated with: ssh-keygen -t rsa -f "${GXBASE}/ssh_keys/gx_${GXUSER}"
                                # This is used only in the archiving script, as on Magnus it appears singularity can not bind to $HOME correctly
export GXNCPULINE=""            # Informs the SLURM request how many CPUs should be allocated. If unset the SLURM 
                                # default will be used. This may be configured with: "--ntasks-per-node=${GXNCPUS}"
                                # For tasks that are not parallelisable (apply_cal, uvflag), this option will be 
                                # overwritten to ensure a single core is used. 
export GXMWAPB="${GXBASE}/data/mwa_pb"  # The calibrate program requires the FEE model of the MWA primary beam.
                                        # This describes the path that containers the file mwa_full_embedded_element_pattern.h5
                                        # and can be downloaded from http://cerberus.mwa128t.org/mwa_full_embedded_element_pattern.h5
export GXMWALOOKUP="${GXBASE}/data/pb"  # The MWA PB lookup HDF5's used by lookup_beam.py and lookup_jones.py. 
                                        # This is currently not used, as the container currently maintains a copy. 

export GXVERSION='3.1.0'        # Version number of the pipeline
export HOST_CLUSTER=$GXCLUSTER  # Maintained for compatability. Will be removed soon. 
export PATH="${PATH}:${GXBASE}/bin" # Adds the obs_* script to the searchable path. 

# Creates directories as needed below
if [[ ! -d "${GXLOG}" ]]
then
    mkdir -p "${GXLOG}"
fi

if [[ ! -d "${GXSCRIPT}" ]]
then
    mkdir -p "${GXSCRIPT}"
fi

if [[ -d ${GXBASE} ]]
then
    if [[ ! -d ${GXMWAPB} ]]
    then
        echo "Creating ${GXMWAPB} and caching FEE hdf5 file"
        mkdir -p ${GXMWAPB} \
            && wget -P ${GXMWAPB} http://cerberus.mwa128t.org/mwa_full_embedded_element_pattern.h5
    fi

    if [[ ! -d ${GXMWALOOKUP} ]]
    then
        echo "Creating ${GXMWALOOKUP} and caching hdf5 lookup files"
        mkdir -p ${GXMWALOOKUP} \
            && wget -O pb_lookup.tar.gz -P ${GXMWALOOKUP} https://cloudstor.aarnet.edu.au/plus/s/77FRhCpXFqiTq1H/download \
            && tar -xzvf pb_lookup.tar.gz -C ${GXMWALOOKUP} \
            && rm pb_lookup.tar.gz

    fi
fi

# Loads a file that contains secrets used throughout the pipeline. These include
# - MWA_ASVO_API_KEY
# - GXDBHOST
# - GXDBPORT
# - GXDBUSER
# - GXDBPASS
# This GXSECRETS file is expected to export each of the variables above. 
# This file SHOULD NOT be git tracked! 
GXSECRETS=
if [[ -f ${GXSECRETS} ]]
then
    source "${GXSECRETS}"
fi

