#!/usr/bin/env bash

# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

KUBE_ROOT=$(dirname "${BASH_SOURCE[0]}")/../../../kubernetes

# start the cache mutation detector by default so that cache mutators will be found
KUBE_CACHE_MUTATION_DETECTOR="${KUBE_CACHE_MUTATION_DETECTOR:-true}"
export KUBE_CACHE_MUTATION_DETECTOR

# panic the server on watch decode errors since they are considered coder mistakes
KUBE_PANIC_WATCH_DECODE_ERROR="${KUBE_PANIC_WATCH_DECODE_ERROR:-true}"
export KUBE_PANIC_WATCH_DECODE_ERROR

focus=${FOCUS:-""}
skip=${SKIP-"\[Flaky\]|\[Slow\]|\[Serial\]"}
# The number of tests that can run in parallel depends on what tests
# are running and on the size of the node. Too many, and tests will
# fail due to resource contention. 8 is a reasonable default for a
# n1-standard-1 node.
# Currently, parallelism only affects when REMOTE=true. For local test,
# ginkgo default parallelism (cores - 1) is used.
parallelism=${PARALLELISM:-8}
artifacts="${ARTIFACTS:-"/tmp/_artifacts/$(date +%y%m%dT%H%M%S)"}"
container_runtime_endpoint=${CONTAINER_RUNTIME_ENDPOINT:-"unix:///run/containerd/containerd.sock"}
image_service_endpoint=${IMAGE_SERVICE_ENDPOINT:-""}
run_until_failure=${RUN_UNTIL_FAILURE:-"false"}
test_args=${TEST_ARGS:-""}
timeout_arg=""
system_spec_name=${SYSTEM_SPEC_NAME:-}
extra_envs=${EXTRA_ENVS:-}
runtime_config=${RUNTIME_CONFIG:-}
ssh_user=${SSH_USER:-"${USER}"}
ssh_key=${SSH_KEY:-}
ssh_options=${SSH_OPTIONS:-}
kubelet_config_file=${KUBELET_CONFIG_FILE:-"test/e2e_node/jenkins/default-kubelet-config.yaml"}

# Parse the flags to pass to ginkgo
ginkgoflags="-timeout=24h"
if [[ ${parallelism} -gt 1 ]]; then
  ginkgoflags="${ginkgoflags} -nodes=${parallelism} "
fi

if [[ ${focus} != "" ]]; then
  ginkgoflags="${ginkgoflags} -focus=\"${focus}\" "
fi

if [[ ${skip} != "" ]]; then
  ginkgoflags="${ginkgoflags} -skip=\"${skip}\" "
fi

if [[ ${run_until_failure} != "" ]]; then
  ginkgoflags="${ginkgoflags} -untilItFails=${run_until_failure} "
fi

# Setup the directory to copy test artifacts (logs, junit.xml, etc) from remote host to local host
if [ ! -d "${artifacts}" ]; then
  echo "Creating artifacts directory at ${artifacts}"
  mkdir -p "${artifacts}"
fi
echo "Test artifacts will be written to ${artifacts}"

if [[ -n ${container_runtime_endpoint} ]] ; then
  test_args="--container-runtime-endpoint=${container_runtime_endpoint} ${test_args}"
fi
if [[ -n ${image_service_endpoint} ]] ; then
  test_args="--image-service-endpoint=${image_service_endpoint} ${test_args}"
fi

metadata=${INSTANCE_METADATA:-""}
hosts=${HOSTS:-""}
images=${IMAGES:-""}
image_config_file=${IMAGE_CONFIG_FILE:-""}
image_config_dir=${IMAGE_CONFIG_DIR:-""}
runtime_config=${RUNTIME_CONFIG:-""}
gubernator=${GUBERNATOR:-"false"}
instance_prefix=${INSTANCE_PREFIX:-"test"}
cleanup=${CLEANUP:-"true"}
delete_instances=${DELETE_INSTANCES:-"false"}
instance_profile=${INSTANCE_PROFILE:-""}
user_data_file=${USER_DATA_FILE:-""}
test_suite=${TEST_SUITE:-"default"}
if [[ -n "${TIMEOUT:-}" ]] ; then
  timeout_arg="--test-timeout=${TIMEOUT}"
fi

# get the account ID
account=$(aws sts get-caller-identity --query Account --output text)
if [[ ${account} == "" ]]; then
  echo "Could not find AWS account ID"
  exit 1
fi

# Use cluster.local as default dns-domain
test_args='--dns-domain="'${KUBE_DNS_DOMAIN:-cluster.local}'" '${test_args}
test_args='--kubelet-flags="--cluster-domain='${KUBE_DNS_DOMAIN:-cluster.local}'" '${test_args}

region=${AWS_REGION:-$(aws configure get region)}
if [[ ${region} == "" ]]; then
    echo "Could not find AWS region specified"
    exit 1
fi
# Output the configuration we will try to run
echo "Running tests remotely using"
echo "Account: ${account}"
echo "Region: ${region}"
echo "Images: ${images}"
echo "Hosts: ${hosts}"
echo "SSH User: ${ssh_user}"
echo "SSH Key: ${ssh_key}"
echo "SSH Options: ${ssh_options}"
echo "Ginkgo Flags: ${ginkgoflags}"
echo "Instance Metadata: ${metadata}"
echo "Image Config File: ${image_config_file}"
echo "Kubelet Config File: ${kubelet_config_file}"
echo "Kubernetes directory: ${KUBE_ROOT}"

# Invoke the runner
go run test/e2e_node/runner/remote/run_remote.go  --mode="aws" --vmodule=*=4 \
  --ssh-env="aws" --ssh-key="${ssh_key}" --ssh-options="${ssh_options}" --ssh-user="${ssh_user}" \
  --gubernator="${gubernator}" --instance-profile="${instance_profile}" \
  --hosts="${hosts}" --images="${images}" --cleanup="${cleanup}" \
  --results-dir="${artifacts}" --ginkgo-flags="${ginkgoflags}" --runtime-config="${runtime_config}" \
  --instance-name-prefix="${instance_prefix}" --user-data-file="${user_data_file}" \
  --delete-instances="${delete_instances}" --test_args="${test_args}" \
  --image-config-file="${image_config_file}" --system-spec-name="${system_spec_name}" \
  --runtime-config="${runtime_config}" \
  --image-config-dir="${image_config_dir}" --region="${region}" \
  --extra-envs="${extra_envs}" --kubelet-config-file="${kubelet_config_file}"  --test-suite="${test_suite}" \
  "${timeout_arg}" \
  2>&1 | tee -i "${artifacts}/build-log.txt"
