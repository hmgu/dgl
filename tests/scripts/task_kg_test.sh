#!/bin/bash
. /opt/conda/etc/profile.d/conda.sh
KG_DIR="./apps/kg/"

function fail {
    echo FAIL: $@
    exit -1
}

function usage {
    echo "Usage: $0 backend device"
}

# check arguments
if [ $# -ne 2 ]; then
    usage
    fail "Error: must specify device and bakend"
fi

if [ "$2" == "cpu" ]; then
    dev=-1
elif [ "$2" == "gpu" ]; then
    export CUDA_VISIBLE_DEVICES=0
    dev=0
else
    usage
    fail "Unknown device $2"
fi

export DGLBACKEND=$1
export DGL_LIBRARY_PATH=${PWD}/build
export PYTHONPATH=${PWD}/python:$KG_DIR:$PYTHONPATH
export DGL_DOWNLOAD_DIR=${PWD}
conda activate ${DGLBACKEND}-ci
# test

pushd $KG_DIR> /dev/null

python3 -m pytest tests/test_score.py || fail "run test_score.py on $1"

if [ "$2" == "cpu" ]; then
    # verify CPU training DistMult
    python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
        --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
        --batch_size_eval 16 --valid --test -adv --eval_interval 30 --eval_percent 0.01 \
        --save_emb DistMult_FB15k_emb --data_path /data/kg || fail "run DistMult on $2"

    # verify saving training result
    python3 eval.py --model_name DistMult --dataset FB15k --hidden_dim 100 \
        --gamma 500.0 --batch_size 16 --model_path DistMult_FB15k_emb/ \
        --eval_percent 0.01 --data_path /data/kg || fail "eval DistMult on $2"
elif [ "$2" == "gpu" ]; then
    # verify GPU training DistMult
    python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
        --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
        --batch_size_eval 16 --gpu 0 --valid --test -adv --eval_interval 30 --eval_percent 0.01 \
        --data_path /data/kg || fail "run DistMult on $2"

    # verify mixed CPU GPU training
    python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
        --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
        --batch_size_eval 16 --gpu 0 --valid --test -adv --mix_cpu_gpu --eval_percent 0.01 \
        --save_emb DistMult_FB15k_emb --data_path /data/kg || fail "run mix with async CPU/GPU DistMult"

    # verify saving training result
    python3 eval.py --model_name DistMult --dataset FB15k --hidden_dim 100 \
        --gamma 500.0 --batch_size 16 --gpu 0 --model_path DistMult_FB15k_emb/ \
        --eval_percent 0.01 --data_path /data/kg || fail "eval DistMult on $2"

    if [ "$1" == "pytorch" ]; then
        # verify mixed CPU GPU training with async_update
        python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
            --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
            --batch_size_eval 16 --gpu 0 --valid --test -adv --mix_cpu_gpu --eval_percent 0.01 \
            --async_update --data_path /data/kg || fail "run mix CPU/GPU DistMult"

        # verify mixed CPU GPU training with random partition
        python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
            --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
            --batch_size_eval 16 --num_proc 2 --gpu 0 --valid --test -adv --mix_cpu_gpu \
            --eval_percent 0.01 --async_update --force_sync_interval 100 \
            --data_path /data/kg || fail "run multiprocess async CPU/GPU DistMult"

        # verify mixed CPU GPU training with random partition async_update
        python3 train.py --model DistMult --dataset FB15k --batch_size 128 \
            --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
            --batch_size_eval 16 --num_proc 2 --gpu 0 --valid --test -adv --mix_cpu_gpu \
            --eval_percent 0.01 --rel_part --async_update --force_sync_interval 100 \
            --data_path /data/kg || fail "run multiprocess async CPU/GPU DistMult"

        # multi process training TransR
        python3 train.py --model TransR --dataset FB15k --batch_size 128 \
            --neg_sample_size 16 --hidden_dim 100 --gamma 500.0 --lr 0.1 --max_step 100 \
            --batch_size_eval 16 --num_proc 2 --gpu 0 --valid --test -adv --eval_interval 30 \
            --eval_percent 0.01 --data_path /data/kg --mix_cpu_gpu --rel_part --async_update \
            --save_emb TransR_FB15k_emb || fail "run multiprocess TransR on $2"

        python3 eval.py --model_name TransR --dataset FB15k --hidden_dim 100 \
            --gamma 500.0 --batch_size 16 --num_proc 2 --gpu 0 --model_path TransR_FB15k_emb/ \
            --eval_percent 0.01 --mix_cpu_gpu --data_path /data/kg || fail "eval multiprocess TransR on $2"
    fi
fi

popd > /dev/null
