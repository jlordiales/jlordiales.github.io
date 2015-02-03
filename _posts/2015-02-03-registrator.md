---
author: jlordiales
comments: true
share: true
date: 2015-02-03
layout: post
title: Automatic container registration with Consul and Registrator
categories:
- Devops
- Microservices
tags:
- Docker
- Consul
- Registrator
---
In the [previous post]({% post_url 2015-01-23-docker-consul %}) we talked about
Consul and how it can help us towards a highly available and efficient service
discovery. We saw how to run a Consul cluster, register services, query through
its HTTP API as well as its DNS interface and use the distributed key/value
store.  One thing we missed though was how to register the different services we
run as docker containers with the Cluster. In this post I'm going to talk about
[Registrator](https://github.com/progrium/registrator), an amazing tool that we
can run as a docker container whose responsibility is to make sure that new
containers are registered and deregistered automatically from our service
discovery tool.

# Introduction
We've seen how to run a Consul cluster and we've also seen how to register
services in that cluster. With this in place we could, in principle, start
running other Docker containers with our services and register those containers
with Consul.
However, who should be responsible for registering those new containers? 

You could let each container know how to register itself. There are some
problems with this approach. First, you give up one of the main benefits of
using containers: portability. If the logic of how the container needs to join
the cluster is inside of it then suddenly you can not run that same container if
you decide to use a different service discovery mechanism or if you decide to
use no service discovery at all.  Another potential issue is that containers are
supposed to do just one thing and do that well. The container that runs your
user service should not care about how that service will be discovered by
others.  The last problem is that you will not always be in control of all the
containers you use. One of the strong points of Docker is the huge amount of
already dockerized applications and services available in their
[registry](https://hub.docker.com/). Those containers will have no idea about
your Consul cluster.

# Registrator
To solve these problems meet
[registrator](https://github.com/progrium/registrator). It is designed to be run
as an independent Docker container. It will sit there quietly, watching for new
containers that are started on the same host where it is currently running,
extracting information from them and then registering those containers with your
service discovery solution. It will also watch for containers that are stopped
(or simply die) and will deregister them.
Additionally, it supports pluggable service discovery mechanisms so you are not
restricted to any particular solution. 

Lets quickly see how we can run registrator together with our Consul cluster. 

## Setting up our hosts
So far we have always run our Consul cluster and all our services in just one
host (the boot2docker VM). In this post I'll try to simulate a more
"production-like" environment were we might have several hosts, each running one
or more docker containers with our services and each running a Consul agent.

In order to do this, we'll use Vagrant to create 3 CoreOS VMS running
locally.
The Vagrantfile will look like this:

{% highlight ruby %}
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "yungsang/coreos"
  config.vm.network "private_network", type: "dhcp"

  number_of_instances = 3
  (1..number_of_instances).each do |instance_number|
    config.vm.define "host-#{instance_number}" do |host|
      host.vm.hostname = "host-#{instance_number}"
    end
  end
end
{% endhighlight %}

After you save the Vagrantfile you can start the 3 VMs with `vagrant up`.  It
might take a while the first time while it downloads the CoreOS image. At this
point you should be able to see the 3 VMs running:

{% highlight bash %}
$ vagrant status

Current machine states:

host-1             running (virtualbox)
host-2             running (virtualbox)
host-3             running (virtualbox)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run vagrant status NAME.
{% endhighlight %}

We'll now ssh into the first host and check that docker is installed and running
(which happens by default when you use the CoreOS image):

{% highlight bash %}
$ vagrant ssh host-1

host-1$ docker info
Containers: 0
Images: 0
Storage Driver: btrfs
Execution Driver: native-0.2
Kernel Version: 3.17.2
Operating System: CoreOS 494.5.0
{% endhighlight %}

Similarly for the second host:

{% highlight bash %}
$ vagrant ssh host-2

host-2$ docker info
Containers: 0
Images: 0
Storage Driver: btrfs
Execution Driver: native-0.2
Kernel Version: 3.17.2
Operating System: CoreOS 494.5.0
{% endhighlight %}

And the third:

{% highlight bash %}
$ vagrant ssh host-3

host-3$ docker info
Containers: 0
Images: 0
Storage Driver: btrfs
Execution Driver: native-0.2
Kernel Version: 3.17.2
Operating System: CoreOS 494.5.0
{% endhighlight %}

Now, before we start running all our different containers I wanted to show how
our hosts look like from a networking point of view. Notice that we specified a
"private_network" interface for our VMs in our Vagrantfile. This basically means
that our VMs will be able to communicate with each other as if they were inside
the same local network. We can see this if we check the network configuration on
each one:

{% highlight bash %}
host-1$ ifconfig enp0s8 | grep 'inet ' | awk '{ print $2 }'

172.28.128.3
{% endhighlight %}

{% highlight bash %}
host-2$ ifconfig enp0s8 | grep 'inet ' | awk '{ print $2 }'

172.28.128.4
{% endhighlight %}

{% highlight bash %}
host-3$ ifconfig enp0s8 | grep 'inet ' | awk '{ print $2 }'

172.28.128.5
{% endhighlight %}

Each VM has other network adapters, but for now we'll focus on this particular
one. We can see that all 3 machines are part of the 172.28.128.0/24 network. On
a production setup the different machines are probably not going to be on the
same private network but we can still achieve this using virtual networks most
of the time (VPC on AWS for instance). This is usually a very good idea because
the public facing IP shoud be firewalled but we don't need that while we
communicate between our internal services.

## Starting the Consul cluster
The first thing we'll do is to start our Consul cluster. We are going to use a 3
node cluster, similarly to how we did it in our [previous post]({% post_url 2015-01-23-docker-consul %}).
I'll show the full docker run commands here, but don't run those yet. I'll show
a more concise form later on:

{% highlight bash %}
host-1$ docker run -d -h node1 -v /mnt:/data \
-p 172.28.128.3:8300:8300 \
-p 172.28.128.3:8301:8301 \
-p 172.28.128.3:8301:8301/udp \
-p 172.28.128.3:8302:8302 \
-p 172.28.128.3:8302:8302/udp \
-p 172.28.128.3:8400:8400 \
-p 172.28.128.3:8500:8500 \
-p 172.17.42.1:53:53/udp \
progrium/consul -server -advertise 172.28.128.3 -bootstrap-expect 3
{% endhighlight %}

In this docker run command, we are binding all Consul's internal ports to the
private IP address of our first host, except for the DNS port (53) which is
exposed only on the `docker0` interface (172.17.42.1 by default).
The reason why we use the docker bridge interface for the DNS server is that we
want all the containers running on the same host to query this DNS interface,
but we don't need anyone from outside doing the same. Since each host will be
running a Consul agent, each container can query its own host.
We also added the `-advertise` flag to tell Consul that it should use the
host's IP instead of the docker container's IP.

On the second host, we'd run the same thing, but passing a `-join` to the first
node's IP:

{% highlight bash %}
host-2$ docker run -d -h node2 -v /mnt:/data \
-p 172.28.128.4:8300:8300 \
-p 172.28.128.4:8301:8301 \
-p 172.28.128.4:8301:8301/udp \
-p 172.28.128.4:8302:8302 \
-p 172.28.128.4:8302:8302/udp \
-p 172.28.128.4:8400:8400 \
-p 172.28.128.4:8500:8500 \
-p 172.17.42.1:53:53/udp \
progrium/consul -server -advertise 172.28.128.4 -join 172.28.128.3
{% endhighlight %}

Same for the third one:

{% highlight bash %}
host-3$ docker run -d -h node3 -v /mnt:/data \
-p 172.28.128.5:8300:8300 \
-p 172.28.128.5:8301:8301 \
-p 172.28.128.5:8301:8301/udp \
-p 172.28.128.5:8302:8302 \
-p 172.28.128.5:8302:8302/udp \
-p 172.28.128.5:8400:8400 \
-p 172.28.128.5:8500:8500 \
-p 172.17.42.1:53:53/udp \
progrium/consul -server -advertise 172.28.128.5 -join 172.28.128.3
{% endhighlight %}

Since the docker run command for each host can be quite large and error prone to
type in manually, the __progrium/consul__ image comes with a convenient command
to generate this for you. You can try this on any of the 3 hosts:

{% highlight bash %}
$ docker run --rm progrium/consul cmd:run 172.28.128.3 -d -v /mnt:/data

eval docker run --name consul -h $HOSTNAME  \
-p 172.28.128.3:8300:8300   \
-p 172.28.128.3:8301:8301   \
-p 172.28.128.3:8301:8301/udp \
-p 172.28.128.3:8302:8302 \
-p 172.28.128.3:8302:8302/udp       \
-p 172.28.128.3:8400:8400  \
-p 172.28.128.3:8500:8500\
-p 172.17.42.1:53:53/udp \
-d -v /mnt:/data  progrium/consul -server -advertise 172.28.128.3 -bootstrap-expect 3
{% endhighlight %}

Note that this is the exact command we ran on our first host to bootstrap the
cluster. You can also try the following:

{% highlight bash %}
$ docker run --rm progrium/consul cmd:run 172.28.128.4:172.28.128.3 -d -v /mnt:/data

eval docker run --name consul -h $HOSTNAME      \
-p 172.28.128.4:8300:8300 \
-p 172.28.128.4:8301:8301       \
-p 172.28.128.4:8301:8301/udp   \
-p 172.28.128.4:8302:8302      \
-p 172.28.128.4:8302:8302/udp   \
-p 172.28.128.4:8400:8400       \
-p 172.28.128.4:8500:8500       \
-p 172.17.42.1:53:53/udp      \
-d -v /mnt:/data progrium/consul -server -advertise 172.28.128.4 -join 172.28.128.3
{% endhighlight %}

Here we passed 2 IPs to the cmd:run command, first the node's own address (the
one that will be used for the `-advertise`) and the second the IP of one of the
nodes that is already in the cluster (the IP in the `-join` part).
Note also that by specifying a second IP the cmd:run command now removed the
`-bootstrap-expect` parameter, which makes sense because otherwise each node
would start a different cluster.

We can use the 2 forms of the "cmd:run" command above to bootstrap our cluster with a
lot less typing. First, stop and remove all running containers on each host with
the following command:

{% highlight bash %}
$ docker rm -f $(docker ps -aq)
{% endhighlight %}

Now, on the first host:

{% highlight bash %}
host-1$ $(docker run --rm progrium/consul cmd:run 172.28.128.3 -d -v /mnt:/data) 
{% endhighlight %}

For the second node:

{% highlight bash %}
host-2$ $(docker run --rm progrium/consul cmd:run 172.28.128.4:172.28.128.3 -d -v /mnt:/data) 
{% endhighlight %}

And the third node:

{% highlight bash %}
host-3$ $(docker run --rm progrium/consul cmd:run 172.28.128.5:172.28.128.3 -d -v /mnt:/data) 
{% endhighlight %}

If you take a look at the logs in host-1 with `docker logs consul` you would see
both nodes joining and finally Consul starting the cluster and setting the 3
nodes as healthy.

## Working with Registrator

Now that we have our Consul cluster up and running we can start the registrator container with:

{% highlight bash %}
host-1$  export HOST_IP=$(ifconfig enp0s8 | grep 'inet ' | awk '{ print $2  }')
host-1$  docker run -d \
-v /var/run/docker.sock:/tmp/docker.sock \
--name registrator -h registrator \
progrium/registrator:latest consul://$HOST_IP:8500
{% endhighlight %}

Notice that we are mounting our "/var/run/docker.sock" file to the container.
This file is a [Unix socket](http://en.wikipedia.org/wiki/Unix_domain_socket),
where the docker daemon listens for events. This is actually how the docker
client (the docker command that you usually use) and the docker daemon
communicate, through a REST API accessible from this socket. If you want to
learn more about how you can interact with the docker daemon through this socket
take a look
[here](http://blog.trifork.com/2013/12/24/docker-from-a-distance-the-remote-api/).
The important thing to know is that by listening on the same port as Docker,
Registrator is able to know everything that happens with Docker on that host.

If you check the logs of the "registrator" container you'll see a bunch of stuff
and a message in the end indicating that it is waiting for new events. You
should run the same commands on the other 2 containers to start registrator on
those.

To summarize what we have done so far, we have 3 different hosts each running a
Consul agent and a registrator container. The registrator instance on each host
watches for changes in docker containers for that host and talks to the local
Consul agent.

## Starting our containers
Let's see what happens when we run our python service from 
[the first post]({% post_url 2014-12-07-aws-docker %}) in this Docker series. 
You can do this following the step by step guide on that post, getting the code
from [this repo](https://github.com/jlordiales/docker-python-service) and
building the docker image yourself or using the image that is already on the
public registry `jlordiales/python-micro-service`. I will go with the latter
option here. 
We'll first run our python container on host-1:

{% highlight bash %}
host-1$ docker run -d --name service1 -P jlordiales/python-micro-service
{% endhighlight %}

Lets see what happened in our registrator container:

{% highlight bash %}
host-1$ docker logs registrator

2015/02/02 18:05:26 registrator: added: a8dc2b849d99 registrator:service1:5000
{% endhighlight %}

Registrator saw that a new container (service1) was started, exposing port 5000
and it registered it with our Consul cluster. 
We'll query our cluster now to see if the service was really added there:

{% highlight bash %}
host-1$ curl 172.28.128.3:8500/v1/catalog/services

{
  "consul":[],
  "consul-53":["udp"],
  "consul-8300":[],
  "consul-8301":["udp"],
  "consul-8302":["udp"],
  "consul-8400":[],
  "consul-8500":[],
  "python-micro-service":[]
}
{% endhighlight %}

There it is! Lets get some more details about it:

{% highlight bash %}
host-1$ curl 172.28.128.3:8500/v1/catalog/service/python-micro-service

[
  {
    "Node":"host-1",
    "Address":"172.28.128.3",
    "ServiceID":"registrator:service1:5000",
    "ServiceName":"python-micro-service",
    "ServiceTags":null,
    "ServicePort":49154
  }
]
{% endhighlight %}

One important thing to notice here, as it caused a lot of
[frustration](https://github.com/progrium/registrator/issues/68) to people
before. You can see that Registrator used the IP of the host as the service IP
rather than the IP address of the container. The reason for that is explained in
[this](https://github.com/bryanlarsen/registrator/commit/0182dd4bdb4cc6b98aa2b80103fd591f65132f46) 
pull request to update the FAQ (which should be merged IMHO).

In a nutshell, registrator will always use the IP you specified when you run
your consul agent with the `-advertise` flag. At first, this seems wrong, 
but it is usually what you want.
A service in a Docker based production cluster typically has 3 IP addresses.
The service itself is running in a Docker container, which has an IP address
assigned by Docker. The host that it's running on will have 3 IP addresses:
one for the Docker network, an internal private IP address for all hosts in the
cluster, and a public address on the Internet. Unless you've bridged your
docker networks, the IP address of the service container is not accessible from
other hosts in the cluster. Instead you use the "-P" or "-p" option to Docker
to map the service port onto the host.  You then advertise a Host IP as the
service IP. The public IP address should be firewalled, so you want the
internal private IP to be advertised.

Going back to the output of our last curl, we get the private IP of our "host-1"
which is where our docker container is running with an exposed port (49154 in
this case). With that information we could call our service from any other node
in any host, as long as they are able to reach "host-1" through its private IP
that is.

So what would happen now if we run a second "python-micro-service" container
from our second host?

{% highlight bash %}
host-2$ docker run -d --name service2 -P jlordiales/python-micro-service
{% endhighlight %}

As we saw on the [last post]({% post_url 2015-01-23-docker-consul %}), whenever
we have a Consul cluster running we can query any node (client or server) and
the response should always be the same.  Since we are running our containers in
host-1 and host-2, lets query the Consul node on host-3:

{% highlight bash %}
host-3$ curl 172.28.128.5:8500/v1/catalog/service/python-micro-service

[
  {
    "Node":"host-1",
    "Address":"172.28.128.3",
    "ServiceID":"registrator:service1:5000",
    "ServiceName":"python-micro-service",
    "ServiceTags":null,
    "ServicePort":49154
  },
  {
    "Node":"host-2",
    "Address":"172.28.128.4",
    "ServiceID":"registrator:service2:5000",
    "ServiceName":"python-micro-service",
    "ServiceTags":null,
    "ServicePort":49153
  }
]
{% endhighlight %}

We now have two containers offering the same service. Using this information we
could call either one from host-3:

{% highlight bash %}
host-3$ curl 172.28.128.3:49154

Hello World from a8dc2b849d99

host-3$ curl 172.28.128.4:49153

Hello World from c9ca6addfdb0
{% endhighlight %}

## Integrating our containers with Consul's DNS
Lets try one more thing: using Consul's DNS interface from a different container
to ping our service. We'll run a simple busybox container in host-3:

{% highlight bash %}
host-3$  docker run --dns 172.17.42.1 --dns 8.8.8.8 --dns-search service.consul
--rm --name ping_test -it busybox 
{% endhighlight %}

The "--dns" parameter allows us to use a custom DNS server for our container. By
default the container will use the same DNS servers as its host. In our case we
want it to use the docker bridge interface (172.17.42.1) first and then, if it
can not find the host there go to Google's DNS (8.8.8.8).
Finally, the "dns-search" option makes it easier to query for our services. For
instance, instead of querying for "python-micro-service.service.consul" we can
just query for "python-micro-service".
Let's try to ping our service from the new busybox container:

{% highlight bash %}
$ ping -qc 1 python-micro-service

PING python-micro-service (172.28.128.4): 56 data bytes

--- python-micro-service ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 2.391/2.391/2.391 ms
{% endhighlight %}

It effectively resolved our service name to one of the hosts where it is
currently running. If we keep running the same "ping" command multiple times we
will eventually see that it will resolve the hostname to 172.28.128.3, which is
the other host where our service is running.
This is well explained in the documentation but Consul will load balance between
all nodes running the same service as long as they are healthy. 

Of course, if we stop a running container Registrator will notice it and also
remove the service from Consul. We can see that if we stop the container running
in host-1:

{% highlight bash %}
host-1$ docker stop service1
{% endhighlight %}

And then query again from host-3 like we did before (you can do the same from
host-1, it doesn't matter):

{% highlight bash %}
host-3$ curl 172.28.128.5:8500/v1/catalog/service/python-micro-service

[
  {
    "Node":"host-2",
    "Address":"172.28.128.4",
    "ServiceID":"registrator:service2:5000",
    "ServiceName":"python-micro-service",
    "ServiceTags":null,
    "ServicePort":49153
  }
]
{% endhighlight %}

# Conclusion
In this post we have seen an approach that allows to have our containers
registered with the service discovery solution of our choice without the need to
couple both. Instead, an intermediary tool called Registrator manages this for
all the containers running on a particular host.

We used Vagrant to create 3 different virtual hosts all under the same private
network. We started our 3 nodes Consul cluster, one consul container running on
each host. We did the same thing for Registrator, one container running on each
host pointing to its local consul container.
Then we ran the container with our python endpoint. This container had no idea
about Consul or registrator. We used exactly the same `docker run` command that
we would've used if we were running that container alone.
And yet registrator was notified about this new container and automatically
registered it with the correct IP and port information on Consul. Moreover, when
we ran another container in another host from the same docker image Consul saw
that it was the same service and started to load balance between them.
When we stopped our container registrator also saw that and automatically
deregistered it from the cluster.

This is amazing because we can keep our containers completely ignorant about how
they will be discovered or any other piece of infrastructure information. We can
keep them portable and we move the logic of registration to a separate component
running in a separate container.

The capability to run multiple containers of the same service and have Consul
automatically load balancing between them, together with its health-checks and
its DNS interface allow us to deploy and run really complex configurations of
services in an extremely transparent and simplified way.
