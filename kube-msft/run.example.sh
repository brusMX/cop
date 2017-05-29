#!/bin/bash

# Create the connection to the registry
kubectl delete secret coscale-registry

kubectl create secret docker-registry coscale-registry \
    --docker-server=docker.coscale.com \
    --docker-username='...' \
    --docker-password='...' \
    --docker-email='...' \
    --namespace=default

# Label the nodes
kubectl label nodes fkube001 coscale/workload.db=true
kubectl label nodes fkube002 coscale/workload.worker=true
kubectl label nodes fkube003 coscale/workload.interactive=true
kubectl label nodes fkube004 coscale/workload.data=true

kubectl get nodes --show-labels

# Start the data services
for service in rabbitmq cassandra memcached postgresql elasticsearch; do
    kubectl apply -f ${service}.yaml
done

CASSANDRA1=`kubectl get pods -l app=cs-cassandra -o name | head -n 1 | awk -F/ '{ print $2; }'`
echo "create keyspace coscale with replication = { 'class' : 'SimpleStrategy', 'replication_factor' : 1 };" | kubectl exec -i $CASSANDRA1 /usr/bin/cqlsh

# Create the config map
kubectl apply -f conf.yaml

# Start and initialise the api
kubectl apply -f api.yaml

##### TODO Wait for the api to be started

API1=`kubectl get pods -l app=cs-api -o name | head -n 1 | awk -F/ '{ print $2; }'`
kubectl exec $API1 python /opt/coscale/api/gen-superuser.py
kubectl exec $API1 /opt/coscale/agent-builder/agent-builder-standalone

# Start and initialise the datastore
kubectl apply -f prealloc.yaml

##### TODO Wait for the prealloc to be done (the job doesn't exit properly, watch the log)
kubectl delete job cs-prealloc

# Start the other services
for service in datastore anomalydetectorservice alerter analysismanager app cron mailer pageminer reporter roller anomalymatcher triggermatcher haproxy; do
    kubectl apply -f ${service}.yaml
done
