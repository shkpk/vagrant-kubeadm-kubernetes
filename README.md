# Disclaimer
This repo is forked from https://github.com/techiescamp/vagrant-kubeadm-kubernetes, aimed to improve it for personal use.

# Improvements
1. Originally the code was for Ubuntu OS, however improvement is made to add support for CentOS.
2. Now you can use amd or arm based CentOS to make your Kubernetes cluster.
3. To use CentOS, you need to replace `box` in line number 33 of [settings.yaml](./settings.yaml) file to `shk/centos-stream-9`
4. To use CentOS, you need to replace `box` in line number 33 of [settings.yaml](./settings.yaml) file to `shk/ubuntu-22.04`
5. This code should work for `CentOS 8 Stream` and `Ubuntu 20.04`, but it is not yet tested.

# Change
1. Originally this code was for Vagrant + Virtual box, however now this is changed to `VMWare Workstation` on Linux, and `VMWare Fusion` on Mac OS(Intel+M1).

## Prerequisites

1. Working Vagrant setup
2. 8 Gig + RAM workstation as the Vms use 3 vCPUS and 4+ GB RAM

## Bring Up the Cluster

To provision the cluster, execute the following commands.

```shell
git clone https://github.com/shkpk/vagrant-kubeadm-kubernetes.git
cd vagrant-kubeadm-kubernetes
vagrant up
```
## Set Kubeconfig file variable

```shell
cd vagrant-kubeadm-kubernetes
cd configs
export KUBECONFIG=$(pwd)/config
```

or you can copy the config file to .kube directory.

```shell
cp config ~/.kube/
```

## Install Kubernetes Dashboard

The dashboard is automatically installed by default, but it can be skipped by commenting out the dashboard version in _[settings.yaml](./settings.yaml)_ before running `vagrant up`.

If you skip the dashboard installation, you can deploy it later by enabling it in _[settings.yaml](./settings.yaml)_ and running the following:
```shell
vagrant ssh -c "/vagrant/scripts/dashboard.sh" master
```

## Kubernetes Dashboard Access

To get the login token, copy it from _config/token_ or run the following command:
```shell
kubectl -n kubernetes-dashboard get secret/admin-user -o go-template="{{.data.token | base64decode}}"
```

Proxy the dashboard:
```shell
kubectl proxy
```

Open the site in your browser:
```shell
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/overview?namespace=kubernetes-dashboard
```

## To shutdown the cluster,

```shell
vagrant halt
```

## To restart the cluster,

```shell
vagrant up
```

## To destroy the cluster,

```shell
vagrant destroy -f
```

