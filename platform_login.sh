!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
CONJUR_PLATFORM="${CONJUR_PLATFORM:-gke}"
APP_PLATFORM="${APP_PLATFORM:-gke}"
GCLOUD_PROJECT_NAME="${GCLOUD_PROJECT_NAME:-gke}"
GCLOUD_ZONE="${GCLOUD_ZONE:-gke}"
GCLOUD_CLUSTER_NAME="${GCLOUD_CLUSTER_NAME:-gke}"
GCLOUD_SERVICE_KEY="${GCLOUD_SERVICE_KEY:-gke}"

OPENSHIFT_URL="${OPENSHIFT_URL:-}"
OPENSHIFT_USERNAME="${OPENSHIFT_USERNAME:-}"
OPENSHIFT_PASSWORD="${OPENSHIFT_PASSWORD:-}"
DOCKER_REGISTRY_PATH="${DOCKER_REGISTRY_PATH:-}"

print_usage() {
        echo "Usage:"
        echo "    This script will log into the various platforms"
        echo ""
        echo "Syntax:"
        echo "    $0 [Options]"
        echo "    Options:"
        echo "    -g                             GKE"
        echo "    -h                             Show help"
        echo "    -o                             OpenShift"
}

function main() {
        # Process command line options
        local OPTIND
        # use_summon=false
        use_summon=true
        while getopts ':ghos' flag; do
                case "${flag}" in
                g) CONJUR_PLATFORM="gke" ;;
                h)
                        print_usage
                        exit 0
                        ;;
                o)
                        CONJUR_PLATFORM="oc"
                        APP_PLATFORM="oc"
                        ;;
                s) use_summon=true ;;

                \
                        *)
                        echo "Invalid argument -${OPTARG}" >&2
                        echo
                        print_usage
                        exit 1
                        ;;
                esac
        done
        shift $((OPTIND - 1))

        if [[ "$CONJUR_PLATFORM" == "gke" || "$APP_PLATFORM" == "gke" ]]; then
                echo "GKE"
                gcloud auth activate-service-account \
                        --key-file "$GCLOUD_SERVICE_KEY"
                gcloud container clusters get-credentials "$GCLOUD_CLUSTER_NAME" \
                        --zone "$GCLOUD_ZONE" \
                        --project "$GCLOUD_PROJECT_NAME"
                docker login "$DOCKER_REGISTRY_URL" \
                        -u oauth2accesstoken \
                        -p "$(gcloud auth print-access-token)"
        elif [[ "$CONJUR_PLATFORM" == "oc" || "$APP_PLATFORM" == "oc" ]]; then
                echo "Openshift platform"
                if [ "$use_summon" = true ]; then
                        echo "Using Summon"
                        summon -p /usr/local/bin/summon-conjur --yaml="
        OPENSHIFT_URL: !var dev/openshift/current/api-url
        OPENSHIFT_USERNAME: !var dev/openshift/current/username
        OPENSHIFT_PASSWORD: !var dev/openshift/current/password
        " sh -c "
            oc login \$OPENSHIFT_URL \
            --username=\$OPENSHIFT_USERNAME \
            --password=\$OPENSHIFT_PASSWORD \
            --insecure-skip-tls-verify=true
        "
                        summon -p /usr/local/bin/summon-conjur --yaml="
        DOCKER_REGISTRY_PATH: !var dev/openshift/current/registry-url
        " sh -c "
          docker login \
            -u _ -p $(oc whoami -t) \
             \$DOCKER_REGISTRY_PATH
        "
                        summon -p /usr/local/bin/summon-conjur --yaml="
        REGISTRY_URL: !var dev/openshift/current/registry-url
        INTERNAL_REGISTRY_URL: !var dev/openshift/current/internal-registry-url 
        " sh -c "
cat << EOF > customize.env
export CONJUR_PLATFORM=oc
export PLATFORM=openshift
export DOCKER_REGISTRY_PATH=\$REGISTRY_URL
export DOCKER_REGISTRY_URL=\$REGISTRY_URL
export PULL_DOCKER_REGISTRY_URL=\$INTERNAL_REGISTRY_URL
export PULL_DOCKER_REGISTRY_PATH=\$INTERNAL_REGISTRY_URL

# Unset these to generate a new unique namespace and release name

unset CONJUR_NAMESPACE_NAME
unset HELM_RELEASE
unset CONJUR_APPLIANCE_URL

# This patch is required for Openshift 4.7 as there are two default storage classes
oc patch StorageClasses awsebs -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'
EOF
"
                else
                        oc login \$OPENSHIFT_URL \
                                --username=\$OPENSHIFT_USERNAME \
                                --password=\$OPENSHIFT_PASSWORD \
                                --insecure-skip-tls-verify=true

                        docker login \
                                -u _ -p "$(oc whoami -t)" \
                                "$DOCKER_REGISTRY_PATH"

                fi
        else
                echo "Unknown"
        fi
}

main "$@"
