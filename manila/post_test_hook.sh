#!/bin/bash -xe
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# This script is executed inside post_test_hook function in devstack gate.
SCRIPT_IS_DEPRECATED="The pre_test_hook and post_test_hook scripts from
devstack-plugin-glusterfs are DEPRECATED. Please use alternate tools to
configure devstack's local.conf file or run tempest tests"

echo $SCRIPT_IS_DEPRECATED

# Backend configuration: singlebackend only, not used yet.
MANILA_BACKEND_TYPE=${1:?}

# Driver type: glusterfs, glusterfs-nfs, glusterfs-heketi,
# glusterfs-nfs-heketi, glusterfs-native
GLUSTERFS_MANILA_DRIVER_TYPE=${2:?}

# Test type: api or scenario
MANILA_TEST_TYPE=${3:?}

if [[ $MANILA_TEST_TYPE == 'api' ]]; then
    export MANILA_TESTS='manila_tempest_tests.tests.api'
    export MANILA_TEMPEST_CONCURRENCY=12
elif [[ $MANILA_TEST_TYPE == 'scenario' ]]; then
    export MANILA_TESTS='manila_tempest_tests.tests.scenario'
    export MANILA_TEMPEST_CONCURRENCY=8
else
    echo "Invalid MANILA_TEST_TYPE = ${MANILA_TEST_TYPE}"
    exit 1
fi

case "$GLUSTERFS_MANILA_DRIVER_TYPE" in
    glusterfs-native)
        BACKEND_NAME="GLUSTERNATIVE"
        ENABLE_PROTOCOLS="glusterfs"
        STORAGE_PROTOCOL="glusterfs"
        ENABLE_RO_ACCESS_LEVEL_FOR_PROTOCOLS=""
        ENABLE_IP_RULES_FOR_PROTOCOLS=""
        SHARE_ENABLE_CERT_RULES_FOR_PROTOCOLS="glusterfs"

        CAPABILITY_SNAPSHOT_SUPPORT=True
        CAPABILITY_CREATE_SHARE_FROM_SNAPSHOT_SUPPORT=True

        RUN_MANILA_SNAPSHOT_TESTS=True
        ;;
    glusterfs|glusterfs-nfs)
        BACKEND_NAME="GLUSTERFS"
        ENABLE_PROTOCOLS="nfs"
        STORAGE_PROTOCOL="NFS"
        ENABLE_RO_ACCESS_LEVEL_FOR_PROTOCOLS=""
        ENABLE_IP_RULES_FOR_PROTOCOLS="nfs"
        SHARE_ENABLE_CERT_RULES_FOR_PROTOCOLS=""

        RUN_MANILA_EXTEND_TESTS=True
        RUN_MANILA_SHRINK_TESTS=True
        ;;
    glusterfs-heketi|glusterfs-nfs-heketi)
        BACKEND_NAME="GLUSTERFSHEKETI"
        # TODO: enable glusterfs-heketi ci
        ;;
    *)
        echo "Invalid GLUSTERFS_MANILA_DRIVER_TYPE = \
            ${GLUSTERFS_MANILA_DRIVER_TYPE}"
        exit 1
esac

TEMPEST_CONFIG=$BASE/new/tempest/etc/tempest.conf

# Start setup Tempest
sudo chown -R $USER:stack $BASE/new/tempest
sudo chown -R $USER:stack $BASE/data/tempest
sudo chmod -R o+rx $BASE/new/devstack/files

# Import devstack functions 'iniset'
source $BASE/new/devstack/functions

# Import env vars defined in CI job.
for env_var in ${DEVSTACK_LOCAL_CONFIG// / }; do
    export $env_var;
done

# When testing a stable branch, we need to ensure we're testing with
# supported API micro-versions; so set the versions from code if we're
# not testing the master branch. If we're testing master, we'll allow
# manila-tempest-plugin (which is branchless) tell us what versions it
# wants to test. Grab the supported API micro-versions from the code
_API_VERSION_REQUEST_PATH=$BASE/new/manila/manila/api/openstack/api_version_request.py
_DEFAULT_MIN_VERSION=$(awk '$0 ~ /_MIN_API_VERSION = /{print $3}' $_API_VERSION_REQUEST_PATH)
_DEFAULT_MAX_VERSION=$(awk '$0 ~ /_MAX_API_VERSION = /{print $3}' $_API_VERSION_REQUEST_PATH)
# Override the *_api_microversion tempest options if present
MANILA_TEMPEST_MIN_API_MICROVERSION=${MANILA_TEMPEST_MIN_API_MICROVERSION:-$_DEFAULT_MIN_VERSION}
MANILA_TEMPEST_MAX_API_MICROVERSION=${MANILA_TEMPEST_MAX_API_MICROVERSION:-$_DEFAULT_MAX_VERSION}
# Set these options in tempest.conf
iniset $TEMPEST_CONFIG share min_api_microversion $MANILA_TEMPEST_MIN_API_MICROVERSION
iniset $TEMPEST_CONFIG share max_api_microversion $MANILA_TEMPEST_MAX_API_MICROVERSION

iniset $TEMPEST_CONFIG share backend_names ${BACKEND_NAME:?}
iniset $TEMPEST_CONFIG share enable_protocols ${ENABLE_PROTOCOLS:?}
iniset $TEMPEST_CONFIG share storage_protocol ${STORAGE_PROTOCOL:?}
iniset $TEMPEST_CONFIG share enable_ro_access_level_for_protocols \
    ${ENABLE_RO_ACCESS_LEVEL_FOR_PROTOCOLS?}
iniset $TEMPEST_CONFIG share enable_ip_rules_for_protocols \
    ${ENABLE_IP_RULES_FOR_PROTOCOLS?}
iniset $TEMPEST_CONFIG share enable_cert_rules_for_protocols \
    ${SHARE_ENABLE_CERT_RULES_FOR_PROTOCOLS?}

iniset $TEMPEST_CONFIG share capability_snapshot_support \
    ${CAPABILITY_SNAPSHOT_SUPPORT:-False}
iniset $TEMPEST_CONFIG share capability_create_share_from_snapshot_support \
    ${CAPABILITY_CREATE_SHARE_FROM_SNAPSHOT_SUPPORT:-False}

iniset $TEMPEST_CONFIG share run_snapshot_tests \
    ${RUN_MANILA_SNAPSHOT_TESTS:-False}
iniset $TEMPEST_CONFIG share run_extend_tests ${RUN_MANILA_EXTEND_TESTS:-False}
iniset $TEMPEST_CONFIG share run_shrink_tests ${RUN_MANILA_SHRINK_TESTS:-False}
iniset $TEMPEST_CONFIG share run_manage_unmanage_tests False
iniset $TEMPEST_CONFIG share multitenancy_enabled False
iniset $TEMPEST_CONFIG share run_consistency_group_tests False

iniset $TEMPEST_CONFIG share share_creation_retry_number 2
iniset $TEMPEST_CONFIG share suppress_errors_in_cleanup True
iniset $TEMPEST_CONFIG share multi_backend False

# Workaround for Tempest architectural changes (only for Liberty and lower releases)
# See bugs:
# 1) https://bugs.launchpad.net/manila/+bug/1531049
# 2) https://bugs.launchpad.net/tempest/+bug/1524717
ADMIN_TENANT_NAME=${ADMIN_TENANT_NAME:-"admin"}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"secretadmin"}
iniset $TEMPEST_CONFIG auth admin_username ${ADMIN_USERNAME:-"admin"}
iniset $TEMPEST_CONFIG auth admin_password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG auth admin_tenant_name $ADMIN_TENANT_NAME
iniset $TEMPEST_CONFIG auth admin_domain_name ${ADMIN_DOMAIN_NAME:-"Default"}
iniset $TEMPEST_CONFIG identity username ${TEMPEST_USERNAME:-"demo"}
iniset $TEMPEST_CONFIG identity password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG identity tenant_name ${TEMPEST_TENANT_NAME:-"demo"}
iniset $TEMPEST_CONFIG identity alt_username ${ALT_USERNAME:-"alt_demo"}
iniset $TEMPEST_CONFIG identity alt_password $ADMIN_PASSWORD
iniset $TEMPEST_CONFIG identity alt_tenant_name ${ALT_TENANT_NAME:-"alt_demo"}
iniset $TEMPEST_CONFIG validation ip_version_for_ssh 4
iniset $TEMPEST_CONFIG validation ssh_timeout $BUILD_TIMEOUT
iniset $TEMPEST_CONFIG validation network_for_ssh\
    ${PRIVATE_NETWORK_NAME:-"private"}

# let us control if we die or not
set +o errexit

# check if tempest plugin was installed correctly
echo 'import pkg_resources; print list(pkg_resources.\
    iter_entry_points("tempest.test_plugins"))' | python

echo "Running tempest manila test suites"
cd $BASE/new/tempest
sudo -H -u $USER tempest list-plugins
sudo -H -u $USER tempest run -r $MANILA_TESTS\
    --concurrency=$MANILA_TEMPEST_CONCURRENCY

_retval=$?

# This is a hack to work around EPERM issue upon
# uploading log files: we ensure that the logs
# shall land in a VFAT mount, whereby POSIX file
# permissions are not implemented (everything is
# world readable).
install_package dosfstools
truncate -s 3g /tmp/fat.img
mkdosfs /tmp/fat.img
sudo mkdir "$WORKSPACE/logs/glusterfs"
sudo mount /tmp/fat.img "$WORKSPACE/logs/glusterfs"

(exit $_retval)
