---
author: jlordiales
comments: true
share: true
date: 2015-04-23
layout: post
title: Resilient container discovery in CoreOS with Consul and Registrator
categories:
- Devops
- Microservices
tags:
- Docker
- CoreOS
- Fleet
- etcd
- Consul
- Registrator
---
A few [posts back]({% post_url 2015-02-03-registrator %}) I talked about Consul
and Registrator and how you can combine them to get some pretty nice and
transparent service discovery for your docker containers.
In that same post we saw how this setup would work on a CoreOS cluster with 3
nodes. However, there we manually setup each host instead of making use of CoreOS
pretty powerful clustering tools, namely
[Fleet](https://coreos.com/using-coreos/clustering/) and
[etcd](https://coreos.com/etcd/).
In this post I want to explore how you would use these tools on a real
production-like CoreOS cluster in order to get a resilient and self-healing
service discovery mechanism using Consul and Registrator.

# Introduction

# Why would you want to run Consul if you have etcd?
At first glance, etcd and Consul look pretty similar. Both provide a
distributed, strongly consistent key/value store that implements the Raft
consensus algorithm.
So if you are running your containers on CoreOS which already comes with etcd
installed, configured and ready to use out of the box, why would you go through
the trouble of running a Consul cluster inside CoreOS?
You can certainly use etcd as a [service discovery
mechanism](http://jasonwilder.com/blog/2014/07/15/docker-service-discovery/).
Registrator even has built-in [support for
etcd](https://github.com/gliderlabs/registrator#etcd-key-value-store)

The answer is that, while both tools provide a general purpose key/value store,
Consul was designed from the start with service discovery as a first class
citizen. Things like a built-in DNS server that serves SRV records and service and
nodes health-checks are things that you don't get with etcd and would have to
re-implement your self.

This is not to say that etcd is not useful or that you shouldn't use it. In
fact, as we'll see in this post, we will rely heavily on etcd in order to get
our Consul cluster running properly in CoreOS.

# Starting your CoreOS cluster

{% highlight yaml %}
#cloud-config
coreos:
  etcd2:
    #generate a new token for each unique cluster from https://discovery.etcd.io/new
    discovery: https://discovery.etcd.io/488ce6e911ea91bd0ea96ac5c28eb749
    # multi-region and multi-cloud deployments need to use $public_ipv4
    advertise-client-urls: http://$public_ipv4:2379
    initial-advertise-peer-urls: http://$private_ipv4:2380
    # listen on both the official ports and the legacy ports
    # legacy ports can be omitted if your application doesn't depend on them
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$private_ipv4:2380,http://$private_ipv4:7001
  fleet:
    public-ip: $public_ipv4
  flannel:
    interface: $public_ipv4
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
    - name: docker-tcp.socket
      command: start
      enable: true
      content: |
        [Unit]
        Description=Docker Socket for the API

        [Socket]
        ListenStream=2375
        Service=docker.service
        BindIPv6Only=both

        [Install]
        WantedBy=sockets.target
write_files:
  - path: /tmp/start_consul.sh
    owner: root:root
    permissions: 0744
    content: |
      #!/bin/sh
      AGENT_NUMBER=$1
      EXPECTED_CONSUL_SERVERS=3
      DOCKER_BRIDGE_IP=$(ifconfig docker0 | grep 'inet ' | awk '{print $2}')
      CONSUL_CMD="/usr/bin/docker run --name consul -h $HOSTNAME \
                  -p $COREOS_PRIVATE_IPV4:8300:8300  \
                  -p $COREOS_PRIVATE_IPV4:8301:8301  \
                  -p $COREOS_PRIVATE_IPV4:8301:8301/udp  \
                  -p $COREOS_PRIVATE_IPV4:8302:8302  \
                  -p $COREOS_PRIVATE_IPV4:8302:8302/udp  \
                  -p $COREOS_PRIVATE_IPV4:8400:8400  \
                  -p $COREOS_PRIVATE_IPV4:8500:8500  \
                  -p $DOCKER_BRIDGE_IP:53:53/udp \
                  -e SERVICE_IGNORE=true \
                  progrium/consul -advertise $COREOS_PRIVATE_IPV4"

      if [ $AGENT_NUMBER -le $EXPECTED_CONSUL_SERVERS ]; then 
        CONSUL_CMD="$CONSUL_CMD -bootstrap-expect $EXPECTED_CONSUL_SERVERS -server"
      fi
      eval "$CONSUL_CMD"
{% endhighlight %}
