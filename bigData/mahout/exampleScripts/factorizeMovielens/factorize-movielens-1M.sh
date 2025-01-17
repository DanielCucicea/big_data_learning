#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Instructions:
#
# Before using this script, you have to download and extract the Movielens 1M dataset
# from http://www.grouplens.org/node/73
#
# To run:  change into the mahout directory and type:
#  examples/bin/factorize-movielens-1M.sh /path/to/ratings.dat
#
#
# Modified by : Zubair AHMED
#
# Assumptions:
# 1. Mahout Path in set in env variable : export PATH=$MAHOUT_HOME/bin:$PATH
# 2. Hadoop Home is set in env variable : export PATH=HADOOP_HOME/bin:$PATH
# 3. If you like to setup a SingleNodeCluster on Ubuntu user the script in /installScript directory
#
#

if [ "$1" = "--help" ] || [ "$1" = "--?" ]; then
  echo "This script runs the Alternating Least Squares Recommender on the Grouplens data set (size 1M)."
  echo "Download Dataset from http://www.grouplens.org/node/73"
  echo "Syntax: $0 /Local/Disk/path/to/ratings.dat\n"
  exit
fi

if [ $# -ne 1 ]
then
  echo -e "\nYou have to download the Movielens 1M dataset from http://www.grouplens.org/node/73 before"
  echo -e "you can run this example. After that extract it and supply the path to the ratings.dat file.\n"
  echo -e "Syntax: $0 /Local/Disk/path/to/ratings.dat\n"
  exit -1
fi

MAHOUT="mahout"

# Set WORK_DIR as per you setup
WORK_DIR=hdfs://localhost:54310/tmp/mahout-work-${USER}

# Temp Directory
WORK_DIR_LOCAL=/tmp/mahout-work-${USER}

echo "creating work directory at ${WORK_DIR}"
mkdir -p ${WORK_DIR_LOCAL}/movielens
hadoop fs -mkdir ${WORK_DIR}/movielens

echo "Converting ratings..."
cat $1 |sed -e s/::/,/g| cut -d, -f1,2,3 > ${WORK_DIR_LOCAL}/movielens/ratings.csv
hadoop fs -copyFromLocal ${WORK_DIR_LOCAL}/movielens/ratings.csv ${WORK_DIR}/movielens/

# create a 90% percent training set and a 10% probe set
$MAHOUT splitDataset --input ${WORK_DIR}/movielens/ratings.csv --output ${WORK_DIR}/dataset \
    --trainingPercentage 0.9 --probePercentage 0.1 --tempDir ${WORK_DIR}/dataset/tmp

# run distributed ALS-WR to factorize the rating matrix defined by the training set
$MAHOUT parallelALS --input ${WORK_DIR}/dataset/trainingSet/ --output ${WORK_DIR}/als/out \
    --tempDir ${WORK_DIR}/als/tmp --numFeatures 20 --numIterations 10 --lambda 0.065

# compute predictions against the probe set, measure the error
$MAHOUT evaluateFactorization --input ${WORK_DIR}/dataset/probeSet/ --output ${WORK_DIR}/als/rmse/ \
    --userFeatures ${WORK_DIR}/als/out/U/ --itemFeatures ${WORK_DIR}/als/out/M/ --tempDir ${WORK_DIR}/als/tmp

# compute recommendations
$MAHOUT recommendfactorized --input ${WORK_DIR}/als/out/userRatings/ --output ${WORK_DIR}/recommendations/ \
    --userFeatures ${WORK_DIR}/als/out/U/ --itemFeatures ${WORK_DIR}/als/out/M/ \
    --numRecommendations 6 --maxRating 5

# print the error
echo -e "\nRMSE is:\n"
hadoop fs -cat ${WORK_DIR}/als/rmse/rmse.txt
echo -e "\n"

echo -e "\nSample recommendations:\n"
hadoop fs -cat ${WORK_DIR}/recommendations/part-m-00000 |head
echo -e "\n\n"

echo "removing work directory"
rm -rf ${WORK_DIR_LOCAL}
hadoop fs -rmr ${WORK_DIR} 
