#!/bin/bash

default_benchbase_url='https://storage.yandexcloud.net/ydb-benchmark-builds/benchbase-ydb.tgz'
ssh_user="$USER"

usage() {
    echo "upload_benchbase.sh --hosts <hosts_file> [--package <benchbase-ydb>] [--package-url <url>] [--user <$ssh_user>]"
    echo "If you don't specify package and package-url, script will download benchbase from $benchbase_url"
}

unique_hosts=

cleanup() {
    if [ -n "$unique_hosts" ]; then
        rm -f $unique_hosts
    fi
}

if ! which parallel-ssh >/dev/null; then
    echo "parallel-ssh not found, you should install pssh"
    exit 1
fi

if ! which parallel-scp >/dev/null; then
    echo "parallel-ssh not found, you should install pssh"
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --package)
            shift
            package=$1
            ;;
        --package-url)
            shift
            benchbase_url=$1
            ;;
        --hosts)
            shift
            hosts=$1
            ;;
        --user)
            shift
            ssh_user=$1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$hosts" ]; then
    echo "Hosts file not specified"
    usage
    exit 1
fi

if [[ -n "$package" && -n "$benchbase_url" ]]; then
    echo "You can't specify both package and package-url"
    usage
    exit 1
fi

if [[ -z "$package" && -z "$benchbase_url" ]]; then
    benchbase_url=$default_benchbase_url
fi

if [ ! -f "$hosts" ]; then
    echo "Hosts file $hosts not found"
    exit 1
fi

unique_hosts=`mktemp`
sort -u $hosts > $unique_hosts

trap cleanup EXIT

# we need this hack to not force
# user accept manually cluster hosts
for host in `cat "$unique_hosts"`; do
    if [[ -n "$ssh_user" ]]; then
        host="$ssh_user@$host"
    fi
    ssh -o StrictHostKeyChecking=no $host &>/dev/null &
done

dst_home=$HOME
if [[ -n "$ssh_user" ]]; then
    host0=`head -n 1 $unique_hosts`
    dst_home="`ssh $ssh_user@$host0 'echo $HOME'`"
fi

if [[ -n "$package" ]]; then
    if [ ! -f "$package" ]; then
        echo "Package $package not found"
        exit 1
    fi

    parallel-scp --user $ssh_user -h $unique_hosts $package $dst_home
    if [ $? -ne 0 ]; then
        echo "Failed to upload package $package to hosts $hosts"
        exit 1
    fi
else
    package=`basename $benchbase_url`

    parallel-ssh --user $ssh_user -h $unique_hosts "wget -O $package $benchbase_url"
    if [ $? -ne 0 ]; then
        echo "Failed to download from $benchbase_url to hosts"
        exit 1
    fi
fi

parallel-ssh --user $ssh_user -h $unique_hosts "tar -xzf `basename $package`"
if [ $? -ne 0 ]; then
    echo "Failed to extract package $package on hosts $hosts"
    exit 1
fi
