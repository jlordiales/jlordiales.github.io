---
author: jlordiales
comments: true
share: true
date: 2015-01-20
layout: post
title: Discovering your Docker containers
categories:
- Devops
- Microservices
tags:
- Docker
- Consul
- Service discovery
---
In the [previous post]({% post_url 2014-12-07-aws-docker %}) I talked a bit
about Docker and the main benefits you can get from running your applications as
isolated, loosely coupled containers. We then saw how to "dockerize" a small
python web service and how to run this container in AWS, first manually and then
using Elastic Beanstalk to quickly deploy changes to it. 
This was really good from an introduction to Docker point of view but in real
life one single container running on a host will not cut it.  You will need a
set of related containers running together and collaborating, each with the
ability to be deployed independently. This also means that you need a way to
know which container is running what and where.  In this post I wanted to talk a
bit about service discovery. Particularly, I'm going to show how you can use
Consul running as a container to achieve this goal in a robust and scalable way.

# Consul
Consul came out of [Hashicorp](https://hashicorp.com/), the same company behind
popular tools like Vagrant and Packer. They are pretty good at creating Devops
friendly tools so I take some time to play around with anything they come up
with. Consul has several components that provide different functionalities but
in a nutshell is a highly distributed and highly available tool for service
discovery. Clients can register new services with Consul, specifying a name and
additional information in the form of tags and then query Consul for services
that match their criteria using either HTTP or DNS. We'll see an example later
on.

In addition to clients specifying the services they want to register they can
also specify any number of health checks. The health check can be made against
your application (e.g., the REST endpoint is listening to connections on port X)
or on the physical node itself (e.g., the CPU utilization is above 90%). Consul
will use these health checks to know which nodes it should exclude when a client
queries for a specific service.

Finally, Consul also provides a highly scalable and fault tolerant Key/Value
store, which your services can use for anything they want: dynamic
configuration, feature flags, etc.

So how does it work? The main thing you need is a Consul agent running as a
server. This Consul server is responsible for storing data and replicating it to
other servers. You can have a fully functioning Consul system with just 1 server
but that is usually a bad idea for a production deployment. Your server becomes
your [single point of
failure](http://en.wikipedia.org/wiki/Single_point_of_failure) and you can not
discover your services if that server goes down. The Consul documentation
recommends setting up a cluster with 3 or 5 Consul servers running to avoid data
loss. More than that and the communication starts to suffer from progressively
increasing overhead. In addition to running as a server, an agent can also run
in client mode. These agents have a lot less responsibilities than servers and
are pretty much stateless components. 

Usually, nodes wanting to register services running on them with Consul do so by
registering them with their local running Consul agent. However, you can also
register [external services](http://www.consul.io/docs/guides/external.html) so
you don't need to run a Consul agent on every node that is hosting your
services.

Queries can be made against any type of Consul
agent, either running as a server or as a client. Unlike servers, you can have
thousands or tens of of thousands of Consul clients without any significant
impact on performance or network overhead.  
I would strongly suggest taking a look at its
[documentation](https://www.consul.io/docs/index.html) to get a more detailed
explanation of how all of this works.

And now, the fun part! Lets see how we can bootstrap a Consul cluster using
Docker containers. We'll first run a Consul cluster consisting of a single
server to see how it works. We'll use the amazing image built by
[Jeff Lindsay](https://github.com/progrium/docker-consul):

{% highlight bash %}
$ docker run -p 8400:8400 -p 8500:8500 -p 8600:53/udp \
-h node1 progrium/consul -server -bootstrap
{% endhighlight %}

You should see something like:

{% highlight text %}
==> WARNING: Bootstrap mode enabled! Do not enable unless necessary
==> WARNING: It is highly recommended to set GOMAXPROCS higher than 1
==> Starting Consul agent...
==> Starting Consul agent RPC...
==> Consul agent running!
         Node name: 'node1'
        Datacenter: 'dc1'
            Server: true (bootstrap: true)
       Client Addr: 0.0.0.0 (HTTP: 8500, DNS: 53, RPC: 8400)
      Cluster Addr: 172.17.0.66 (LAN: 8301, WAN: 8302)
    Gossip encrypt: false, RPC-TLS: false, TLS-Incoming: false

==> Log data will now stream in as it occurs:

    2014/12/04 19:33:30 [INFO] serf: EventMemberJoin: node1 172.17.0.66
    2014/12/04 19:33:30 [INFO] serf: EventMemberJoin: node1.dc1 172.17.0.66
    2014/12/04 19:33:30 [INFO] raft: Node at 172.17.0.66:8300 [Follower] entering Follower state
    2014/12/04 19:33:30 [INFO] consul: adding server node1 (Addr: 172.17.0.66:8300) (DC: dc1)
    2014/12/04 19:33:30 [INFO] consul: adding server node1.dc1 (Addr: 172.17.0.66:8300) (DC: dc1)
    2014/12/04 19:33:30 [ERR] agent: failed to sync remote state: No cluster leader
    2014/12/04 19:33:31 [WARN] raft: Heartbeat timeout reached, starting election
    2014/12/04 19:33:31 [INFO] raft: Node at 172.17.0.66:8300 [Candidate] entering Candidate state
    2014/12/04 19:33:31 [INFO] raft: Election won. Tally: 1
    2014/12/04 19:33:31 [INFO] raft: Node at 172.17.0.66:8300 [Leader] entering Leader state
    2014/12/04 19:33:31 [INFO] consul: cluster leadership acquired
    2014/12/04 19:33:31 [INFO] consul: New leader elected: node1
    2014/12/04 19:33:31 [INFO] raft: Disabling EnableSingleNode (bootstrap)
    2014/12/04 19:33:31 [INFO] consul: member 'node1' joined, marking health alive
    2014/12/04 19:33:33 [INFO] agent: Synced service 'consul'
{% endhighlight %}

The `-server -bootstrap` tells Consul to start this agent in server mode and not
wait for any other instances to join. Notice how Consul actually warns you about
this when you start the server.

We can now query Consul through its REST API, Since I'm running
[boot2docker](http://boot2docker.io/) I need to get the VM IP first:

{% highlight bash %}
$ export DOCKER_IP=$(boot2docker ip)
$ curl $DOCKER_IP:8500/v1/catalog/nodes

[{"Node":"node1","Address":"172.17.0.66"}]
{% endhighlight %}

You get a JSON response specifying the nodes that are currently part of the
Consul cluster, which in our case so far is just one. You can also go to
http://192.168.59.103:8500/ (replace the IP by whatever your Docker host IP is)
in your browser to see a nice UI with information about the currently registered
services and nodes.

Lets now add a new service. We'll start by adding an external service, following
the example given in the documentation:

{% highlight bash %}
$ curl -X PUT -d \
'{"Datacenter": "dc1", "Node": "google", "Address": "www.google.com", "Service": {"Service": "search", "Port": 80}}' \
http://$DOCKER_IP:8500/v1/catalog/register
{% endhighlight %}

Here we registered the "google" node as offering the "search" service.  We can
now query Consul through its HTTP API to see all the services that are currently
registered with it:

{% highlight bash %}
$ curl $DOCKER_IP:8500/v1/catalog/services

{"consul":[],"search":[]}
{% endhighlight %}

We can see that the "search" service that we added before is registered. We can
also use the DNS interface to query for services:

{% highlight bash %}
$ dig @$DOCKER_IP -p 8600 search.service.consul.

; <<>> DiG 9.8.3-P1 <<>> @192.168.59.103 -p 8600 search.service.consul.
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 29403
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 4, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;search.service.consul.         IN      A

;; ANSWER SECTION:
search.service.consul.  0       IN      CNAME   www.google.com.
www.google.com.         77      IN      A       64.233.186.147
www.google.com.         77      IN      A       64.233.186.105
www.google.com.         77      IN      A       64.233.186.104

;; Query time: 35 msec
;; SERVER: 192.168.59.103#8600(192.168.59.103)
;; WHEN: Wed Dec 10 18:13:53 2014
;; MSG SIZE  rcvd: 178
{% endhighlight %}

## Running a Consul cluster
Ok, so we were able to run a single Consul agent in server mode and register an
external service. But, as I mentioned before, this is usually a very bad idea
for availability reasons. So lets see how we could run a cluster with 3 servers,
all of them running locally on different Docker containers.

We'll start the first node similarly to the way we did it before:
{% highlight bash %}
$ docker run --name node1 -h node1 progrium/consul -server -bootstrap-expect 3

==> WARNING: Expect Mode enabled, expecting 3 servers
==> WARNING: It is highly recommended to set GOMAXPROCS higher than 1
==> Starting Consul agent...
==> Starting Consul agent RPC...
==> Consul agent running!
         Node name: 'node1'
        Datacenter: 'dc1'
            Server: true (bootstrap: false)
       Client Addr: 0.0.0.0 (HTTP: 8500, DNS: 53, RPC: 8400)
      Cluster Addr: 172.17.0.75 (LAN: 8301, WAN: 8302)
    Gossip encrypt: false, RPC-TLS: false, TLS-Incoming: false
{% endhighlight %}

Note here that instead of passing the `-bootstrap` flag we are passing a
`-bootstrap-expect 3` flag, which tells Consul that it should wait until 3
servers join to actually start the cluster.
In order to join the 2 remaining nodes, we will need the IP of the first one
(the only node we know of so far). We can get this IP using `docker inspect` and
looking for the `IPAddress` field. Or you can just export that to an environment
variable with:

{% highlight bash %}
{% raw  %}
$ JOIN_IP="$(docker inspect -f '{{.NetworkSettings.IPAddress}}' node1)"
{% endraw %}
{% endhighlight %}

We can now start our 2 remaining servers and join them with the first one:

{% highlight bash %}
$ docker run -d --name node2 -h node2 progrium/consul -server -join $JOIN_IP
$ docker run -d --name node3 -h node3 progrium/consul -server -join $JOIN_IP
{% endhighlight %}

After doing that you should see something like this on the `node1` logs:

{% highlight bash %}
2014/12/06 08:15:54 [INFO] serf: EventMemberJoin: node2 172.17.0.76
2014/12/06 08:15:54 [INFO] consul: adding server node2 (Addr: 172.17.0.76:8300) (DC: dc1)
2014/12/06 08:15:58 [ERR] agent: failed to sync remote state: No cluster leader
2014/12/06 08:16:15 [INFO] serf: EventMemberJoin: node3 172.17.0.77
2014/12/06 08:16:15 [INFO] consul: adding server node3 (Addr: 172.17.0.77:8300) (DC: dc1)
2014/12/06 08:16:15 [INFO] consul: Attempting bootstrap with nodes: [172.17.0.75:8300 172.17.0.76:8300 172.17.0.77:8300]
2014/12/06 08:16:16 [WARN] raft: Heartbeat timeout reached, starting election
2014/12/06 08:16:16 [INFO] raft: Node at 172.17.0.75:8300 [Candidate] entering Candidate state
2014/12/06 08:16:16 [WARN] raft: Remote peer 172.17.0.77:8300 does not have local node 172.17.0.75:8300 as a peer
2014/12/06 08:16:16 [INFO] raft: Election won. Tally: 2
2014/12/06 08:16:16 [INFO] raft: Node at 172.17.0.75:8300 [Leader] entering Leader state
2014/12/06 08:16:16 [INFO] consul: cluster leadership acquired
2014/12/06 08:16:16 [INFO] raft: pipelining replication to peer 172.17.0.77:8300
2014/12/06 08:16:16 [INFO] consul: New leader elected: node1
2014/12/06 08:16:16 [WARN] raft: Remote peer 172.17.0.76:8300 does not have local node 172.17.0.75:8300 as a peer
2014/12/06 08:16:16 [INFO] raft: pipelining replication to peer 172.17.0.76:8300
2014/12/06 08:16:16 [INFO] consul: member 'node3' joined, marking health alive
2014/12/06 08:16:16 [INFO] consul: member 'node1' joined, marking health alive
2014/12/06 08:16:16 [INFO] consul: member 'node2' joined, marking health alive
2014/12/06 08:16:18 [INFO] agent: Synced service 'consul'
{% endhighlight %}

Basically, after joining the second node Consul tells us that it can not yet
start the cluster. But after joining the third node, it tries to bootstrap the
cluster, elects a [leader
node](https://www.consul.io/docs/internals/architecture.html) and marks the 3
nodes as healthy.

So now we have our 3 servers cluster up and running. Note however, that we did
not specify any port mapping information on any of the three nodes. This means
that we would have no way of accessing the cluster from outside.
Luckily this is not a problem because with our cluster running we can now join
any number of nodes in client mode and interact with the cluster through those
clients. Lets join the first client node with:

{% highlight bash %}
$ docker run -d -p 8400:8400 -p 8500:8500 -p 8600:53/udp \
--name node4 -h node4 progrium/consul -join $JOIN_IP
{% endhighlight %}

We can now interact with the cluster through our client node. We could, for
instance, use the REST API to see all the nodes that are currently part of the
cluster:

{% highlight bash %}
$ curl $DOCKER_IP:8500/v1/catalog/nodes

[
  {"Node":"node1","Address":"172.17.0.7"},
  {"Node":"node2","Address":"172.17.0.8"},
  {"Node":"node3","Address":"172.17.0.9"},
  {"Node":"node4","Address":"172.17.0.10"}
]
{% endhighlight %}

It is important to understand that we only need to know the address of 1 of the
nodes (either server or client) to join. Until now we have used the `JOIN_IP`
variable which contains the IP of __node1__ but we could just as easily add a
new node using the IP of __node4__ for instance, which is a client:

{% highlight bash %}
$ docker run -d -p 8401:8400 -p 8501:8500 -p 8601:53/udp \
--name node5 -h node5 progrium/consul -join 172.17.0.10
{% endhighlight %}

Similarly, we can send our queries to any node in the cluster and the answer
will be always the same thanks to Consul's replication algorithms. Here we'll
use port 8501, which is the port exposed by the last client we joined:

{% highlight bash %}
$ curl $DOCKER_IP:8501/v1/catalog/nodes

[
  {"Node":"node1","Address":"172.17.0.7"},
  {"Node":"node2","Address":"172.17.0.8"},
  {"Node":"node3","Address":"172.17.0.9"},
  {"Node":"node4","Address":"172.17.0.10"},
  {"Node":"node5","Address":"172.17.0.11"}
] 
{% endhighlight %}

This combined with the fact that we can have thousands of clients in the cluster
without any performance impact makes Consul an extremely highly available
service discovery solution.

## Key/Value store
In addition to its service discovery and health check capabilities, Consul
offers a key/value store for whatever you may need. We can easily access it
through its REST API. We'll keep using the 5 node cluster we got running before.
First, lets make sure that there is nothing currently saved there:

{% highlight bash %}
$ curl -v  $DOCKER_IP:8500/v1/kv/key1

 About to connect() to 192.168.59.103 port 8500 (#0)
   Trying 192.168.59.103...
 Adding handle: conn: 0x7fa72b811a00
 Adding handle: send: 0
 Adding handle: recv: 0
 Curl_addHandleToPipeline: length: 1
 - Conn 0 (0x7fa72b811a00) send_pipe: 1, recv_pipe: 0
 Connected to 192.168.59.103 (192.168.59.103) port 8500 (#0)
> GET /v1/kv/key1 HTTP/1.1
> User-Agent: curl/7.30.0
> Host: 192.168.59.103:8500
> Accept: */*
>
< HTTP/1.1 404 Not Found
< X-Consul-Index: 50
< X-Consul-Knownleader: true
< X-Consul-Lastcontact: 0
< Date: Tue, 20 Jan 2015 06:25:07 GMT
< Content-Length: 0
< Content-Type: text/plain; charset=utf-8
<
 Connection #0 to host 192.168.59.103 left intact
{% endhighlight %}

We got back a 404 because the key doesn't exist yet, great! Let's now add a
value for __key1__ and query again:

{% highlight bash %}
$ curl -X PUT -d 'test' http://$DOCKER_IP:8500/v1/kv/key1

$ curl -v  $DOCKER_IP:8500/v1/kv/key1

 About to connect() to 192.168.59.103 port 8500 (#0)
   Trying 192.168.59.103...
 Adding handle: conn: 0x7fb9a3817e00
 Adding handle: send: 0
 Adding handle: recv: 0
 Curl_addHandleToPipeline: length: 1
 - Conn 0 (0x7fb9a3817e00) send_pipe: 1, recv_pipe: 0
 Connected to 192.168.59.103 (192.168.59.103) port 8500 (#0)
> GET /v1/kv/key1 HTTP/1.1
> User-Agent: curl/7.30.0
> Host: 192.168.59.103:8500
> Accept: */*
>
< HTTP/1.1 200 OK
< Content-Type: application/json
< X-Consul-Index: 55
< X-Consul-Knownleader: true
< X-Consul-Lastcontact: 0
< Date: Tue, 20 Jan 2015 06:28:31 GMT
< Content-Length: 93
<
 Connection #0 to host 192.168.59.103 left intact
[{"CreateIndex":50,"ModifyIndex":55,"LockIndex":0,"Key":"key1","Flags":0,"Value":"dGVzdA=="}]%
{% endhighlight %}

Note that the `Value` field is base64 encoded. According to the
[documentation](http://www.consul.io/intro/getting-started/kv.html) this is to
allow non UTF-8 characters.

Before we saw that we could query any node in the cluster for registered
services or a list of nodes and the answer would be the same. 
It's no surprise that this also applies to the key/value store. We can add a key
and query for one from any node. In our example, we could use `curl -v
$DOCKER_IP:8501/v1/kv/key1` (changing the port to 8501 to query a different node
that the one we used on the PUT) and we would get exactly the same answer from
Consul.

## Conclusion
In the [previous post]({% post_url 2014-12-07-aws-docker %}) I talked a bit

