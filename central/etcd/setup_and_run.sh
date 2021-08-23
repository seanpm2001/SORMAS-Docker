#!/bin/bash

# fork to background
/usr/local/bin/etcd --listen-client-urls=http://0.0.0.0:2379 --advertise-client-urls=http://etcd:2379 &

echo "starting import"
sleep 3

if [ ! -f /srv/fixtures/import.txt ]; then
    echo "File not found!"
fi


# see https://mywiki.wooledge.org/BashFAQ/089
while read -r line <&3; do
  key=$(echo "${line}" |  cut -d' ' -f1)
  value=$(echo "${line}" |  cut -d' ' -f2)
  etcdctl put "$key" "$value" || exit 0
done 3</srv/fixtures/import.txt


echo "import done"

echo "setup root"
etcdctl role add root
etcdctl user add root --new-user-password="${ROOT_PWD}"
etcdctl user grant-role root root

echo "setting up s2s"
etcdctl role add s2s-client-role
etcdctl user add s2s-client --new-user-password="${S2S_CLIENT_PWD}"
etcdctl role grant-permission s2s-client-role --prefix=true read /s2s/
etcdctl user grant-role s2s-client s2s-client-role

etcdctl auth enable

echo  "terminating"
ps aux  |  grep -i etcd  |  awk '{print $2}'  |  xargs kill -15

sleep 3

/usr/local/bin/etcd --config-file /etc/etcd/etcd.yml
