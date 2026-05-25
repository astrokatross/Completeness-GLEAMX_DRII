#!/usr/bin/env bash

# A simple helper script to string together the completeness tasks that need to be run.
flux=-3,-0.5,0.1
nfiles=6
sep_min=5
regstr="HerA"

if [[ $regstr == "HydA" ]]
then
    region=100,195,-90,30
    echo "Region set to Hydra A. Region string is ${regstr}. Region is ${region}"
    outdir="/data/curtin_gleam/DR3/GX_DR4_${regstr}/completeness/"
    imageset='GX_DR4_${regstr}_170-231MHz'
    imageset_dir="/data/curtin_gleam/DR3/GX_DR4_${regstr}/completeness/"
    nsrc=98210
elif [[ $regstr == "HerA" ]]
then
    region=195,310,-90,30
    echo "Region set to Hercules A. Region string is ${regstr}. Region is ${region}"
    outdir="/data/curtin_gleam/DR3/${regstr}/GX_DR4_${regstr}/completeness/"
    imageset='GX_DR4_${regstr}_170-231MHz'
    imageset_dir="/data/curtin_gleam/DR3/${regstr}/GX_DR4_${regstr}/completeness/"
    nsrc=120030
else
    echo "Region string ${regstr} not recognised. Exiting. "
    return 1
fi
export GLEAMX="${outdir}"
export MYCODE=/data/curtin_gleam/sw/Completeness-GLEAMX_DRII
export NCPUS=38
export CONTAINER=$GXCONTAINER


if [[ -z ${MYCODE} ]]
then
    echo "Error. Completeness code directory not set. Exiting. "
    return 1
fi

if [[ ! -d $outdir ]]
then
    echo "Making directory ${outdir}"
    mkdir -p "${outdir}"
fi

mkdir "${GLEAMX}/input_images"

# TODO: See how well this works with symlinks. Need to be sure the container can follow them.
for suffix in "" "_bkg" "_rms" "_psf" "_comp"
do
    if [[ -e "${imageset_dir}/${imageset}${suffix}.fits" ]]
    then
        cp -v "${imageset_dir}/${imageset}${suffix}.fits" "${GLEAMX}/input_images"
    else
        echo "Could not find ${imageset_dir}/${imageset}${suffix}.fits. Exiting. "
        return 1
    fi
done


# DONT NEED NEXT BIT SINCE IT RUNS IN TEH GENERATE FLUXES ANYWAY! 
# msg=($(sbatch --time=06:00:00 --ntasks-per-node=1 $MYCODE/generate_pos.sh ${nsrc} ${region} 5 $GLEAMX/source_pos))
# jobid=${msg[3]}

if [[ ! -f ${GLEAMX}/fluxes/flux_list1.txt ]]
then
    "$MYCODE/generate_fluxes.sh" \
    $nsrc \
    $region \
    $sep_min \
    $flux \
    $nfiles \
    "$outdir/"
fi 


if [[ $? -ne 0 ]]
then
    echo "Completeness simulation set up failed. Aborting."
    exit 1
fi
# set +x 

# We will be blocking until we are finished
msg="sbatch \
--array 1-$nfiles \
--time 24:00:00 \
--ntasks-per-node 1 \
--cpus-per-task 38 \
--export ALL \
--mem 350G \
--constraint=clx \
-p curtin_gleam \
-o "${MYCODE}/logs/inject_source_${regstr}.o%A_%a" \
-e "${MYCODE}/logs/inject_source_${regstr}.e%A_%a" \
"$MYCODE/inject_sources.sh" \
"${GLEAMX}/input_images" \
"${GLEAMX}/source_pos/source_pos.txt" \
"${GLEAMX}/fluxes" \
4.0 \
"${GLEAMX}/inject" \
"${imageset}" \
"${GLEAMX}/completeness"

echo "Submit injecting sources via:" 

echo "$msg"

# jobid=${msg[3]}
# echo "$msg"
# id=$(echo "$msg" | cut -d ' ' -f3)

msg="sbatch \
--time 7:00:00 \
--ntasks-per-node 1 \
--cpus-per-task $NCPUS \
--dependency "afterok:$jobid" \
--export ALL \
--mem 150G \
--constraint="clx" \
--partition="curtin_gleam" \
-o "${MYCODE}/logs/cmp_map_${regstr}.o%A" \
-e "${MYCODE}/logs/cmp_map_${regstr}.e%A" \
"$MYCODE"/make_cmp_map.sh \
"${GLEAMX}/source_pos/source_pos.txt" \
"${GLEAMX}/inject" \
"$flux" \
"${GLEAMX}/input_images/${imageset}_psf.fits" \
"${region}" \
6 \
"${GLEAMX}/results""


echo "Submit make final map via:" 

echo "$msg"
# echo "$msg"
