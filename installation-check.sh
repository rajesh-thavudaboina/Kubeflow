#!/bin/bash
echo "############################"
docker --version
echo "############################"
docker ps
echo "############################"
kind --version
echo "############################"
kubectl version --client
echo "############################"
helm version --short
echo "############################"
kustomize version
echo "############################"
kind get clusters
echo "############################"
kubectl get nodes
echo "############################"
kubectl get pods -A
echo "############################"
