---
author: jlordiales
comments: true
share: true
date: 2015-04-01
layout: post
title: Consul Template for transparent load balancing of containers
categories:
- Devops
- Microservices
tags:
- Docker
- Consul
- Registrator
- Consul Template
---
In the [previous post]({% post_url 2015-02-03-registrator %}) we talked about
Registrator and how, combined with a service discovery backend like Consul, it
allows us to have transparent discovery for our containers while still keeping
their portability.
One thing we didn't talk about though is how are we supposed to access those
services registered in Consul from our consumer applications, which could be
running as containers themselves.

As an example, imagine we have a service exposing a REST API. To provide
horizontal scalability we decide to run 3 instances of that service, all
registered in Consul. 
Each container will be listening on a random port assigned by Docker, so how do
we know where to connect to from our consumers?
We can use Consul's own DNS capabilities, as we saw on the last post, but even
though Consul offers the possibility of asking for SRV records (which include
the port information as well as the IP) most client libraries in modern
programming languages don't care about this information and only use the IP
address, leaving the task of specifying the port to the developer.
We could always use Consul's REST API to query for the services we are
interested in and parse the IP and Port from there. But this approach seems
rather complex and it would couple our consumer app to Consul's specific API.

In this post I want to explore one possible approach to solve this problem in a
portable and transparent way, both from the point of view of our services as
from the point of view of our consumers.
It is certainly not the only possible approach nor the best but it is something
that I have seen working quite successfully in the past.

# Introduction
Lets think about our current problem again. We have 2 or more containers that
expose a REST API and we want to consume that API from another application.
We are using Consul as a service discovery mechanism and Registrator to
transparently register our containers there.
We know that we can get the IP of our service by using Consul's DNS interface
but we don't know which port on that IP to use.
For the purposes of this post, our service container will be the Python service
that we have been using so far (available in the Docker hub as
jlodiales/python-micro-service). 
In turn, our consumer will simply be the `curl` command line tool.

It would be great if there was a proxy running on a well known port that we
could send requests to. That proxy would then pass the request to the correct
service and transmit the response back to us. This sounds a lot like something
that Nginx or HAProxy could do.
But now we have just moved the problem one step further. That is, how does our
proxy know which port our containers are running on? 
Luckily for us, the guys from [HashiCorp](https://hashicorp.com/) have developed
a little standalone tool to do just this: [Consul
Template](https://hashicorp.com/blog/introducing-consul-template.html).

# Consul Template
From the project's [Github repo](https://github.com/hashicorp/consul-template):

> This project provides a convenient way to populate values from Consul into the
filesystem using the consul-template daemon.
The daemon consul-template queries a Consul instance and updates any number of
specified templates on the filesystem. As an added bonus, consul-template can
optionally run arbitrary commands when the update process completes.

We'll see how this works with a simple example. First, we'll run our Consul
cluster. For simplicity we'll run just one node but exactly the same would apply
on a multi-node setup.

{% highlight bash %}
$ docker run -p 8400:8400 -p 8500:8500 -p 8600:53/udp \
-h consul --name consul \
progrium/consul -server -advertise $DOCKER_IP -bootstrap
{% endhighlight %}

Notice that we are advertising the $DOCKER_IP as Consul's IP. The reason for
that is that Registrator will always register new containers as accessible in
Consul's advertise IP. We discussed this in the 
[previous post](http://jlordiales.me/2015/02/03/registrator#advertise). Also, as a
remainder, the DOCKER_IP variable is simply boot2docker's IP 
(`export DOCKER_IP=$(boot2docker ip 2> /dev/null)`). If you are running on
native Linux then that would be `localhost`.


Now that we have Consul running, we'll do the same for Registrator:

{% highlight bash %}
$ docker run -d \
-v /var/run/docker.sock:/tmp/docker.sock \
--name registrator -h registrator \
gliderlabs/registrator:latest consul://$DOCKER_IP:8500
{% endhighlight %}

And finally our Python service. As we said before, lets imagine we want to run 3
instances of it:
{% highlight bash %}
$ docker run -d -P --name node1 -h node1 jlordiales/python-micro-service:latest
$ docker run -d -P --name node2 -h node2 jlordiales/python-micro-service:latest
$ docker run -d -P --name node3 -h node3 jlordiales/python-micro-service:latest
{% endhighlight %}

We can query consul to make sure that our new containers are running:

{% highlight bash %}
$ curl $DOCKER_IP:8500/v1/catalog/service/python-micro-service

[
  {
    "Address": "192.168.59.103",
    "Node": "node1",
    "ServiceAddress": "",
    "ServiceID": "registrator:node1:5000",
    "ServiceName": "python-micro-service",
    "ServicePort": 49162,
    "ServiceTags": null
  },
  {
    "Address": "192.168.59.103",
    "Node": "node1",
    "ServiceAddress": "",
    "ServiceID": "registrator:node2:5000",
    "ServiceName": "python-micro-service",
    "ServicePort": 49163,
    "ServiceTags": null
  },
  {
    "Address": "192.168.59.103",
    "Node": "node1",
    "ServiceAddress": "",
    "ServiceID": "registrator:node3:5000",
    "ServiceName": "python-micro-service",
    "ServicePort": 49164,
    "ServiceTags": null
  }
]
{% endhighlight %}

Now for the fun part. We'll install Consul Template and see what happens when we
run it against our current setup. We can get the latest release from
[here](https://github.com/hashicorp/consul-template/releases) for whatever
architecture we are running on. In my case I'm running on a Mac so:

{% highlight bash %}
$ wget https://github.com/hashicorp/consul-template/releases/download/v0.7.0/consul-template_0.7.0_darwin_amd64.tar.gz -O /tmp/consul-template.tar.gz
$ tar -xvzf /tmp/consul-template.tar.gz -C /tmp --strip-components=1
{% endhighlight %}

Next, we'll write a simple template and run consul-template to parse it and
generate the result. You can read all about the templates syntax and provided
functions at the project's
[documentation](https://github.com/hashicorp/consul-template#templating-language):

{% highlight bash %}
$ echo '{% raw %}{{range service "python-micro-service"}}{% endraw %}\nserver {% raw %}{{.Address}}:{{.Port}}{{end}}{% endraw %}' > /tmp/consul.ctmpl
$ /tmp/consul-template -consul $DOCKER_IP:8500 -template /tmp/consul.ctmpl:/tmp/consul.result -dry -once

> /tmp/consul.result

server 192.168.59.103:49162
server 192.168.59.103:49163
server 192.168.59.103:49164
{% endhighlight %}

By specifying the `-dry` parameter we tell consul-template to send the output to
stdout instead of the file specified on the command (_/tmp/consul.result_ in this
case). The `-once` parameter tells Consul Template to query Consul and generate
the output just once. If we don't do this then the app will keep running in the
foreground polling Consul at regular intervals (which is what we would want in a
typical scenario).  You can see that the result includes the 3 instances of the
service with their respective ports.

To see what happens when we change the information registered in Consul, we are
going to run consul-template again but this time we won't specify the `-once`
parameter in order to leave the daemon running:

{% highlight bash %}
$ /tmp/consul-template -consul $DOCKER_IP:8500 -template /tmp/consul.ctmpl:/tmp/consul.result -dry
{% endhighlight %}

With that running, we'll go to a new terminal and stop one of the running python
containers:

{% highlight bash %}
$ docker stop node3
{% endhighlight %}

You should almost instantly see the refreshed output in the terminal running
consul-template that now only shows 2 entries. Conversely, if we run a new
container:

{% highlight bash %}
$ docker run -d -P --name node4 -h node4 jlordiales/python-micro-service:latest
{% endhighlight %}

The consul-template output gets updated again with the new service.

# Combining Consul Template and a reverse proxy
So we saw that we can use Consul Template to parse a template file and produce a
new file with the information read from Consul. How can we use this from our
consumer applications in order to have transparent service location and load
balance?
Well, one option is to front our services with Nginx or HAProxy, creating the
config files for these with Consul Template.
We'll how this would work for Nginx. All the files that I'll describe in the
following section can be found [in this
repo](https://github.com/jlordiales/docker-nginx-consul) if you just want to
clone from it.

I'll first show the Dockerfile that we'll use for the Nginx image and then
explain each section of it:

{% highlight docker %}

FROM nginx:latest

ENTRYPOINT ["/bin/start.sh"]
EXPOSE 80
VOLUME /templates
ENV CONSUL_URL consul:8500

ADD start.sh /bin/start.sh
RUN rm -v /etc/nginx/conf.d/\*.conf

ADD https://github.com/hashicorp/consul-template/releases/download/v0.7.0/consul-template_0.7.0_linux_amd64.tar.gz /usr/bin/
RUN tar -C /usr/local/bin --strip-components 1 -zxf /usr/bin/consul-template_0.7.0_linux_amd64.tar.gz
{% endhighlight %}

We are basing our image from the official Nginx image, available
[here](https://registry.hub.docker.com/_/nginx/).
This gives us a ready to use, default Nginx installation. Then we say that the
entrypoint will be the /bin/start.sh (will see that one in a bit) and that our
container will expose port 80, where Nginx will be listening for new
connections.
Next we define a volume */templates*, which is where we will mount our template
files from the host. This way we can reuse the same image for different services
and templates.
In the following step we define and environment variable with the location of
our Consul cluster. By default, it will try to resolve to *consul:8500* which
would be the behavior if we have Consul running as a container in the same host
and we link it to this Nginx container (with the alias consul, of course). But
this environment variable can also be overridden when we run the container if we
want to point somewhere else.
We then add the start up script (which is used as the entrypoint to our
containers) and remove all default configurations from Nginx.
On the last 2 lines we download the latest version of Consul Template
(0.7.0 at the time of writing this) and we put it on /usr/local/bin.

The start.sh script is very simple:

{% highlight bash %}
#!/bin/bash
service nginx start
consul-template -consul=$CONSUL_URL -template="/templates/service.ctmpl:/etc/nginx/conf.d/service.conf:service nginx reload"
{% endhighlight %}

We just start the nginx service and then leave consul-template running on the
foreground. Here we use the CONSUL_URL environment variable that we defined
before. Consul template expects to find a `service.ctmpl` file in `/templates`.
This is the template that we would mount as a volume from our host. The result
is then placed in `/etc/nginx/conf.d/service.conf` where Nginx will be able to
read from. Finally, every time the template is re-rendered we do a `service
nginx reload` in order to read the new configuration.

Time to see this in action. If you still have the Consul, Registrator and Python
containers running from the first part of this post then you only need to run
the Nginx container (otherwise start them again).

The only thing you'll need is a template file like the following, save it as
`/tmp/service.ctmpl` for convenience:

{% highlight text %}

upstream python-service {
  least_conn;
  {% raw %}{{range service "python-micro-service"}}server {{.Address}}:{{.Port}} max_fails=3 fail_timeout=60 weight=1;
  {{else}}server 127.0.0.1:65535; # force a 502{{end}}{% endraw %}
}

server {
  listen 80 default_server;

  charset utf-8;

  location ~ ^/python-micro-service/(.\*)$ {
    proxy_pass http://python-service/$1$is_args$args;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
{% endhighlight %}

Now run the nginx container with:

{% highlight bash %}
$ docker run -p 8080:80 -d --name nginx --volume /tmp/service.ctmpl:/templates/service.ctmpl --link consul:consul jlordiales/nginx-consul
{% endhighlight %}

We can `curl` the service multiple times:
{% highlight bash %}
$ curl $DOCKER_IP:8080/python-micro-service/
$ curl $DOCKER_IP:8080/python-micro-service/
$ curl $DOCKER_IP:8080/python-micro-service/
$ curl $DOCKER_IP:8080/python-micro-service/
{% endhighlight %}

You should see a "Hello World from nodeX" where X alternates between 1, 2 and 3.
We are effectively load balancing between the 3 nodes. But there's something
even cooler that you can try.
Leave this running on a terminal:

{% highlight bash %}
$ while true; do curl $DOCKER_IP:8080/python-micro-service/; echo -----; sleep 1; done;
{% endhighlight %}

That will keep calling nginx every second, which in turn will send the request
to one of the 3 nodes. Now from another terminal, stop `node1` with:

{% highlight bash %}
$ docker stop node1
{% endhighlight %}

If you check the terminal running the `while` loop you'll notice that the
requests are now going to node2 and node3 only. You can play around with this
(starting and stopping nodes) to see the configuration updated almost
instantaneous and nginx adjusting which nodes it sends requests to.
And, more importantly, all of this while keeping our service containers and our
nginx container completely ignorant about the fact that we are using Consul as a
service discovery mechanism!

# Conclusion
This post completes the subject of transparent service discovery in Docker. We
saw how we can use a reverse proxy sitting in front of our containers,
accessible through a well known port. The proxy, in turn is kept updated with
the information available in our Consul cluster thanks to a small and handy tool
called Consul Template.

Combined with Registrator and Consul this gives us extreme flexibility and
portability. Of course, as with almost everything else, there are other
alternatives and approaches. I would be glad to hear other people's experiences
around this area.
