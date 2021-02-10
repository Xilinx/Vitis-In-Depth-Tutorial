#!/bin/bash

##
##* © Copyright (C) 2016-2020 Xilinx, Inc
##*
##* Licensed under the Apache License, Version 2.0 (the "License"). You may
##* not use this file except in compliance with the License. A copy of the
##* License is located at
##*
##*     http://www.apache.org/licenses/LICENSE-2.0
##*
##* Unless required by applicable law or agreed to in writing, software
##* distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
##* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
##* License for the specific language governing permissions and limitations
##* under the License.
##*/

# *******************************************************************************

CNN=alexnetBNnoLRN


: '
#dos2unix conversion
for file in $(find $PWD -name "*.sh"); do
    sed -i 's/\r//g' ${file}
    echo  ${file}
    # make all *.sh scripts to be executable
    chmod +x ${file}
done
'

conda activate vitis-ai-caffe

# set the project environmental variables
source caffe/set_prj_env_variables.sh

# set the proejct directories
python set_the_CATSvsDOGS_prj.py -i $ML_DIR

# train the CNN and make predictions
source caffe/caffe_flow_AlexNet.sh             2>&1 | tee log/logfile_caffe_${CNN}.txt

# quantize the CNN
source deploy/${CNN}/quantiz/vaiq_${CNN}.sh    2>&1 | tee log/logfile_vaiq_${CNN}.txt

# generate ELF file for ZCU102 board
source deploy/${CNN}/quantiz/vaic_${CNN}.sh    2>&1 | tee log/logfile_vaic_${CNN}.txt

# create test images for ZCU102 board
cd input/jpg/
tar -cvf test_images.tar ./test
mv test_images.tar ../../deploy/${CNN}/zcu102/
cd ../../

conda deactivate


# Pruning with Vitis AI Optimizer
conda activate vitis-ai-optimizer_caffe
source pruning/alexnetBNnoLRN/pruning_flow.sh 2>&1 | tee log/logfile_run_pruning_${CNN}.txt
conda deactivate

# quantize the Optimized CNN
conda activate vitis-ai-caffe
source deploy/${CNN}/pruned/vaiq_pruned_${CNN}.sh  2>&1 | tee log/logfile_vaiq_pruned_${CNN}.txt

# generate ELF file for ZCU102 board
source deploy/${CNN}/pruned/vaic_pruned_${CNN}.sh 2>&1 | tee log/logfile_vaic_pruned_${CNN}.txt

conda deactivate
exit #from docker environment


cd ..
# prepare a final tar archive to be copied on the ZCu102 board
tar -cvf ${CNN}_zcu102.tar ./zcu102


##create unified log file
#cat LICENSE.txt ./log/logfile_run_all_alexNet.txt ./log/logfile_vaiq_alexnetBNnoLRN.txt  ./log/logfile_vaic_alexnetBNnoLRN.txt > logfile_baseline_alexnet_host.txt
#cat LICENSE.txt ./log/logfile_run_pruning_alexnetBNnoLRN.txt ./log/logfile_vaiq_pruned_alexnetBNnoLRN.txt  ./log/logfile_vaic_pruned_alexnetBNnoLRN.txt > logfile_pruned_alexnet_host.txt
#cat LICENSE.txt deploy/alexnetBNnoLRN/zcu102/rpt/summary_baseline*.txt  deploy/alexnetBNnoLRN/zcu102/rpt/summary_pruned*.txt  deploy/alexnetBNnoLRN/zcu102/rpt/summary_fps.txt > logfile_summary_target.txt
#rm log/logfile*.txt
#rm deploy/alexnetBNnoLRN/zcu102/rpt/summary*.txt
#mv logfile*.txt ./log
