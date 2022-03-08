#!/bin/sh
set -e

#TODO Add removing of old backups - probably should be configurable
#TODO Add readme for this image - remember to add description of tests
#TODO Add comments inside code
#TODO Add support for volume backups
#TODO Investigate if visible password for ETCD access could stay (probably yes)
#TODO Investigate if it is really required to check ETCD certificate (probably no)
#TODO Add compression for etcd backups - search if it is possible to do by pipe like in postgres case

GetContainerLabel() {
    CONTAINER_ID=$1
    LABEL=$2
    docker inspect --format="{{index .Config.Labels \"$LABEL\"}}" $CONTAINER_ID
}

GetComposeService() {
    CONTAINER_ID=$1
    docker inspect --format='{{index .Config.Labels "com.docker.compose.service"}}' $CONTAINER_ID
}

GetContainerEnv() {
    CONTAINER_ID=$1
    ENV=$2
    docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' $CONTAINER_ID | grep $ENV | sed 's/^.*=//'
}

GetBackupLabeledContainers() {
    TYPE=$1
    docker container ls --filter "label=backup.type=$TYPE" --format='{{json .ID}}' | tr -d '"'
}

GetDatabasesToBackup() {
    psql -l -t | cut -d '|' -f 1 | tr -d '[[:blank:]]' | grep -v -E "postgres|template0|template1" | sed '/^$/d'
}

DumpDatabase() {
    SERVICE=$1
    DATABASE=$2
    mkdir -p /backup/postgres/
    pg_dump $DATABASE | zstd > /backup/postgres/$SERVICE.$DATABASE.$DATE.zst
}

export DATE=$(date +%F-%T)

for CONTAINER_ID in $(GetBackupLabeledContainers postgres); do
    SERVICE=$(GetComposeService $CONTAINER_ID)
    POSTGRES_USER=$(GetContainerEnv $CONTAINER_ID POSTGRES_USER)
    POSTGRES_PASSWORD=$(GetContainerEnv $CONTAINER_ID POSTGRES_PASSWORD)

    export PGUSER=$POSTGRES_USER
    export PGPASSWORD=$POSTGRES_PASSWORD
    export PGHOST=$CONTAINER_ID

    for DATABASE in $(GetDatabasesToBackup); do
        DumpDatabase $SERVICE $DATABASE
    done
done

for CONTAINER_ID in $(GetBackupLabeledContainers etcd); do
    SERVICE=$(GetComposeService $CONTAINER_ID)
    ETCD_USER=$(GetContainerLabel $CONTAINER_ID backup.user)
    ETCD_PASSWORD=$(GetContainerLabel $CONTAINER_ID backup.password)
    ETCD_ENCRYPTED=$(GetContainerLabel $CONTAINER_ID backup.encrypted)

    ETCD_FLAGS=""
    if [ "$ETCD_USER" != "" ] && [ "$ETCD_PASSWORD" != "" ]; then
        ETCD_FLAGS="--user=$ETCD_USER --password=$ETCD_PASSWORD"
    fi

    if [ "$ETCD_ENCRYPTED" == "true" ]; then
        ETCD_FLAGS="$ETCD_FLAGS --endpoints=https://$SERVICE:2379 --insecure-transport=false --insecure-skip-tls-verify"
    else
        ETCD_FLAGS="$ETCD_FLAGS --endpoints=http://$SERVICE:2379"
    fi

    mkdir -p /backup/etcd/
    etcdctl snapshot save /backup/etcd/$SERVICE.etcd.$DATE $ETCD_FLAGS
done