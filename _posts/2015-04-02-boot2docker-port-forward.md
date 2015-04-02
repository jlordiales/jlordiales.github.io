---
author: jlordiales
comments: true
share: true
date: 2015-04-02
layout: post
title: Accessing docker containers on localhost when using Boot2Docker
categories:
- Devops
tags:
- Docker
- Boot2Docker
- VirtualBox
---

If you have been following my posts on Docker then you know by now that I
usually run on OSX with
[Boot2Docker](https://github.com/boot2docker/boot2docker). It is definitely a
really useful tool if you are not on a native Linux kernel and it makes using
Docker on Mac and Windows almost as easy and transparent as if you were on Linux.
That is, until you need to expose one or more ports from your containers and
then you want to access those from your host. If you are on Linux then you can
simply go to `localhost` and the port number and that's it. If you are using
boot2docker however, you need to remember that your docker host is actually the
boot2docker VM and not your laptop, so you first need to know what that VM's IP
is.  In this very short post I want to describe a way in which you can access
your containers on `localhost` even if you are using boot2docker.

The important thing to know is that boot2docker is a Virtual Machine that runs
on Virtual Box. And as with any other VM you can forward ports between your host
and guest operating system. That means that if we can get Virtual Box to forward
whatever port we expose from our containers, from our host OS to the boot2docker
VM then those ports will be accessible from our `localhost`.

So how can we do that? I don't really know if this works on Windows (I assume it
does) but on Mac you can use the `VBoxManage` command line tool to control the
different VMs that Virtual Box manages.
So let's imagine that our Nginx container exposes port 80 and then we map that
to port 8080 on the VM when we do a `docker run -p 8080:80`. Normally you would
be able to access this by going to `http://$DOCKER_IP:8080`. But with VBoxManage
you can do: `VBoxManage controlvm boot2docker-vm natpf1 "nginx,tcp,127.0.0.1,8080,,8080"`.
This basically means: "Take the boot2docker-vm and create a new NAT rule called
nginx that will forward all requests on the localhost (127.0.0.1) port 8080 to
port 8080 on the VM".
Now we can access our container on `http://localhost:8080`. Simple as that! Best
of all is that you can do this while the VM and your containers are running and
doesn't require you to restart anything.
When you are done and you want to delete the NAT rule you can just do
`VBoxManage controlvm boot2docker-vm natpf1 delete "nginx"`.

# But why would you do this?

Arguably, typing `$DOCKER_IP` instead of `localhost` makes little to no
difference. In fact, if you count the time it takes you to do the `VBoxManage`
stuff then it is probably slower.
In the case when you are just playing around with different containers and want
to test things locally I agree that this makes no sense. But sometimes it can be
quite useful.

Imagine for instance that you are developing a webapp. You run all the backend
services that your app needs as docker containers and then you just run the
frontend part in your laptop, pointing to these containers. 
If you are developing on Mac then you would have to point your webapp to
$DOCKER_IP but if then you move to Ubuntu for instance, you would need to change
all places where you were previously using $DOCKER_IP to use localhost instead.
In this scenario, creating a little script that runs the containers and then
uses `VBoxManage` to forward the exposed ports can give you better portability
between different platforms.

In any case, whether you find a good use case for it or not it is still good to
know that you have that option if you ever need it. The rest is up to you!

Cheers!
