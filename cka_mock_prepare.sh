#!/bin/bash
set -e

CLUSTER_MASTERS=('cluster1-master1' 'cluster2-master1' 'cluster3-master1') 
CLUSTER_WORKERS=('cluster1-worker1' 'cluster1-worker2' 'cluster2-worker1' 'cluster3-worker1' 'cluster3-worker2')

MASTER_IMAGE='roclv/k8s-master'
WORKER_IMAGE='roclv/k8s'

stop_container () {
  if [  "$(docker ps -q -f name=$1)" ]; then
    echo Stoping $1
    docker stop $1
  fi

  if [ "$(docker ps -aq -f status=exited -f name=$1)" ]; then
    echo Removing $1
    docker rm $1
  fi
}

create_container () {
  stop_container $1

  echo Starting $1

  docker run -d --name $1 --privileged $2
}

get_join_token () {
  docker exec $1 kubeadm token create --print-join-command
}

join_cluster () {
  docker exec $1 $(docker exec $2 kubeadm token create --print-join-command)
}

test_master_initialized () {
  docker exec $1 kubectl get nodes
  return $?
}

for cluster in "${CLUSTER_MASTERS[@]}"
do
  echo Creating $cluster
  create_container $1-$cluster $MASTER_IMAGE
done

for worker in "${CLUSTER_WORKERS[@]}"
do
  echo Creating $worker
  create_container $1-$worker $WORKER_IMAGE
done

MASTER1=$1-cluster1-master1
C1WORKER1=$1-cluster1-worker1
C1WORKER2=$1-cluster1-worker2

echo $C1WORKER1 joining in master $MASTER1
until docker exec $MASTER1 kubectl get nodes &> /dev/null
do
  sleep 1
  echo -n ...
done
join_cluster $C1WORKER1 $MASTER1
join_cluster $C1WORKER2 $MASTER1
 
 
MASTER2=$1-cluster2-master1
C2WORKER1=$1-cluster2-worker1
 
echo $C1WORKER1 joining in master $MASTER1
until docker exec $MASTER2 kubectl get nodes &> /dev/null
do
  sleep 1
  echo -n ...
done
join_cluster $C2WORKER1 $MASTER2

MASTER3=$1-cluster3-master1
C3WORKER1=$1-cluster3-worker1
C3WORKER2=$1-cluster3-worker2

echo $C3WORKER1 joining in master $MASTER3
until docker exec $MASTER1 kubectl get nodes &> /dev/null
do
  sleep 1
  echo -n ...
done
join_cluster $C3WORKER1 $MASTER3
join_cluster $C3WORKER2 $MASTER3

# Merge 3 clusters config
docker exec $MASTER1 cp -L /root/.kube/config /root/config
docker exec $MASTER1 cp -L /root/.kube/config /root/.kube/k8s-c1-H-config
rm -f k8s-c2-AC-config
rm -f k8s-c3-CCC-config
docker cp -L $MASTER2:/root/.kube/config k8s-c2-AC-config && docker cp k8s-c2-AC-config $MASTER1:/root/.kube/k8s-c2-AC-config
docker cp -L $MASTER3:/root/.kube/config k8s-c3-CCC-config && docker cp k8s-c3-CCC-config $MASTER1:/root/.kube/k8s-c3-CCC-config

KUBECONFIG=""
CONTEXTS=('k8s-c1-H' 'k8s-c2-AC' 'k8s-c3-CCC')

for context in "${CONTEXTS[@]}"
do
  docker exec $MASTER1 sed -i -e "s/name: kubernetes$/name: $context/g"       /root/.kube/$context-config
  docker exec $MASTER1 sed -i -e "s/name: kubernetes-admin$/name: $context/g"       /root/.kube/$context-config
  docker exec $MASTER1 sed -i -e "s/cluster: kubernetes$/cluster: $context/g" /root/.kube/$context-config
  docker exec $MASTER1 sed -i -e "s/user: kubernetes-admin$/user: $context/g" /root/.kube/$context-config
  docker exec $MASTER1 sed -i -e "s/kubernetes-admin@kubernetes$/$context/g"  /root/.kube/$context-config
  KUBECONFIG=$KUBECONFIG:/root/.kube/$context-config
done
KUBECONFIG="${KUBECONFIG:1}"

docker exec $MASTER1 sh -c "export KUBECONFIG=$KUBECONFIG && kubectl config view --flatten > /tmp/config && mv -f /tmp/config ~/.kube/config"
