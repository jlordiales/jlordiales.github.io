---
author: jlordiales
comments: true
share: true
date: 2014-12-07
layout: post
title: Running Docker in AWS with Elastic Beanstalk
categories:
- Devops
- Microservices
tags:
- Aws
- Elastic Beanstalk
- Docker
---
By now I would image that [Docker](http://www.docker.com/) needs no
introduction, given that is one of the hottest technologies and indeed buzzwords
in the industry today. But just in case, we'll see the basics of it. We'll also
see how you can quickly run a Docker container in AWS and how you can easily
deploy your changes to it.

# Introduction

The [official documentation](https://docs.docker.com) defines Docker as "an open
platform for developing, shipping, and running applications".
What does that really mean? In simple terms it means that instead of thinking
about your application as only the code that you write and then somehow gets
deployed into some server in the "cloud", you can start thinking about your
application and those things that it needs to run as a single isolated container
that you can just throw at any server and it will work, regardless of what
that server already had installed or not.

When you hear about isolation the first thing that probably comes to mind are
Virtual Machines. The problem with VMs is that they are usually a bit
heavyweight. Even on a pretty decent laptop it usually takes a few minutes for a
VM to start. A Docker container, on the other hand, starts in the order of
seconds. 
On a very simplified view of the world, you can see Docker containers as
lightweight VMs (although in reality they are much much more than that). Each
container can run its own OS, have its own files, run its own processes and so
on. Also, unlike VMs where you can probably run just a few of them on a regular
piece of hardware, you can easily run dozens of Docker containers on your
laptop.

The benefits from using containers for your applications are varied and people
are still finding new and innovative ways to put them to good use. Perhaps one
of the main benefits is related to deployment and portability. You know the
dreaded "It works in my machine" phrase, don't you? Imagine the following
workflow:

- You develop and test in your local box running your application and all the
  services it requires on their own isolated environment.
- Once you are happy with your code you push your changes and the same set of
  containers that you were running locally are now running in a testing
  environment.
- Once you validate your changes in this testing environment you push the same
  container to be run in Production.

Because of the underlying principles of Docker you are guaranteed that
regardless of the differences in environment between your local box, the testing
environment and the production environment, your containers (and therefore your
application) will run exactly in the same way.

What happens if you decide to move to a different provider for your production
environment? Say you were running in AWS and suddenly all your company migrates
to OpenStack. As long as the new server is able to run Docker containers, it
doesn't matter. Your containers will still run exactly in the same way as
before.

Another huge benefit that I see in Docker is the fact that not only your code
runs in a container but also the infrastructure that your code needs, usually in
different containers. This, combined with the fact that the community has
already created thousands of Docker images for all sort of popular applications
(publicly available in [Docker Hub](https://hub.docker.com/)) means that you can
save yourself a lot of trouble.
Say your application needs to use [Redis](http://redis.io/) as its backing
store. Do you install Redis locally in your box to test while you develop and
then make sure that the same version of Redis with the same configuration is
installed in each and every new environment? Or do you get an [official Redis
image](https://registry.hub.docker.com/_/redis/) and run that same image on
every environment with just one command?

# A really simple Docker app
Due to the way that Docker works, it needs a Linux kernel to run on. This is
obviously not a problem if you are actually using a Linux distribution but it
can be an issue if you are on Windows or Mac.
The official documentation covers Docker
[installation](https://docs.docker.com/installation/) on a lot of different
platforms.
Personally, since I use a Mac mostly these days, I really recommend the
[boot2docker](http://boot2docker.io/). It provides a very tiny VM (literally, is
based in [Tiny Core Linux](http://tinycorelinux.net/)) where you can run Docker
from your Mac terminal (almost) as if you were running it locally.

Enough introductions, lets see an example. We are going to develop a really
simple REST service and run it inside a Docker container.
We are going to use Python with [Flask](http://flask.pocoo.org/) for this,
simply because it's really easy to get up an running in no time but the
language and framework of choice are not really important for this. We could
have used Java with Dropwizard or Ruby with Sinatra and the result would be the
same. If you don't want to write the code you can just clone the app from 
[here](https://github.com/jlordiales/docker-python-service.git).

So our application will consist of one `app.py` file that looks like the
following:

{% highlight python %}
from flask import Flask
import os
import socket
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello World from %s' % socket.gethostname()

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
{% endhighlight %}

In order to get the dependencies we need for our app (just flask in this case)
and comply with the [12 factor app](http://12factor.net/) we'll also create a
`requirements.txt` file with just one line:

{% highlight text %}
flask
{% endhighlight %}

With these 2 files we can already run our application with:
{% highlight bash %}
$ pip install -r requirements.txt
$ python app.py
{% endhighlight %}

The application will start a server listening in port 5000. If you run `curl
localhost:5000` from a different shell you should see a hello world message as a
response.

Lets now "dockerize" our application. The easiest way to this is to write a
Dockerfile with the steps we want to take. I won't go into a lot of details
about Dockerfiles but you can read about them
[here](https://docs.docker.com/reference/builder/). I'm rather going to show you
the Dockerfile that we'll use and describe what each step is doing:

{% highlight text %}
FROM python:2.7
EXPOSE 5000
ADD . /code
WORKDIR /code
RUN pip install -r requirements.txt
CMD ["python", "app.py"]
{% endhighlight %}

On the first line we are saying that our new image will use the `python`
[official image](https://registry.hub.docker.com/_/python/) as a base image. The
2.7 part is called a TAG and in this case represents the version of python that
we want installed in our image.
Next we tell Docker that the container will expose port 5000 to the external
world (which is the port where our endpoint will be listening). We'll see how
this is useful in a moment.
The third instruction tells Docker that it needs to copy the current directory
(where the Dockerfile is placed) and copy it to `/code` inside the new
container.
Then, in the following step we tell Docker that we want to `cd` to that `/code`
directory so that all commands we run after that are executed from within that path.
Next we run `pip install` to install our dependencies into the container and
finally we tell Docker that the default command to run should be `python
app.py`.

Now that we have our Dockerfile, we can build an image from it using the `docker
build` command: `docker build -t python_service .`. This step can take a while
the first time you run it because it will need to download the python base image
first (which is currently around 850 MB, a bit too much if you ask me).
When the command finishes you should be able to see your new shiny image after
running `docker images`.

So far you have an image, but not a running container. To run this new image
you'll have to do a `docker run --rm --name service1 -P python_service`. The
`--rm` parameter tells Docker to delete the container after it has stopped
running, which is useful for cases where you are creating lots of different
containers to do quick tests because it will save you quite a bit of disk space.
Next, we give our container a name. This is completely optional and if we don't
specify a name then Docker will assign the container one by default. The `-P`
parameter means that we want to map every port exposed by the container (in our
case just port 5000) into a port in our host. By not specifying any specific
port on the host Docker will randomly assign one. Another alternative, if we
want to explicitly tell Docker which port to use would be to pass the parameter
`-p $HOST_PORT:$CONTAINER_PORT`. But it is usually a good idea not to do that
because we might want to run multiple instances of the same container and they
all have to map to different ports. So its usually better to let Docker decide.

After running the `docker run` command the container will start and you'll see
that it will run our app which is going to be waiting for connections to it.
If you now run `docker ps` on a different shell you'll see something like this:

{% highlight text %}
CONTAINER ID        IMAGE                     COMMAND             CREATED             STATUS              PORTS                     NAMES
86b331209845        python_service:latest   "python app.py"     2 days ago          Up 12 hours         0.0.0.0:49162->5000/tcp   python1
{% endhighlight %}

Pay special attention to the PORTS part. In your Dockerfile you told Docker that
you were exposing port 5000. But remember that when you ran the container with
`docker run` you specified the -P, which meant that the ports exposed by the
container would be mapped to randomly high ports on the host. In our case, the
49162->5000/tcp part is telling us that port 49162 on the host will map to port
5000 on the container.

So how do we curl our service now? If we were running Docker natively on a Linux
machine we could just do a `curl localhost:49162`. But since I'm running on
boot2docker, I need to get the IP of the boot2docker VM first. This can be
easily done with `boot2docker ip`. Unless you've done something to change the
default values this IP will be 192.168.59.103. 
So if we now run `curl 192.168.59.103:49162` we get back our awesome hello world
message from our running container.

# Running manually in AWS
By now you have an independent Docker image with your python service which you
can easily run and query with a simple curl. But so far we have only run the
container locally, which doesn't seem like a big improvement over just running
the application directly. And indeed it wouldn't make a lot of sense to do all
this work if we are only going to run things locally.
So lets see what happens when we want to run the same container somewhere else,
like AWS for instance given that they give us a free year with their [free
tier](http://aws.amazon.com/free/). This AWS server could be a QA environment
for instance.

Before we go into AWS we are going to use the [Docker
registry](https://registry.hub.docker.com/) to push the image we created before,
which is based off the `python` image and has our app and dependencies all
bundled together. The
[documentation](http://docs.docker.com/userguide/dockerrepos/) is pretty clear
about how you work with the registry so I'll skip that part (hint: you should
use the `docker push` command).

Now that our image is on the public Docker registry, lets create a micro
instance on EC2. Create a new account if you don't have one yet, go to your EC2
dashboard, instances and click on Launch instance.
Choose the Amazon Linux AMI that shows up on the first step, select t2.micro for
the instance type, leave all the default options on the next steps until Step 6
where you'll create a security group for your instance specifying which ports
you are going to leave open to the internet. In our case we want port 22 to be
able to ssh into our instance. We also want to add a new custom rule to open the
high ports that Docker usually uses. So we'll create a new TCP rule with Port
Range between 30000-50000. Finally review your instance and Launch!

Once the instance is running, ssh into it using its public IP, install Docker
with `sudo yum install -y docker` and start it with `sudo service docker start`.
Now that we have Docker installed in our new instance we can use it in exactly
the same way that we did locally. 
Since we pushed our image into the Docker registry before, we can do a `sudo docker
pull your_user/repo_name` and then run our container similarly to how we did
before with `sudo docker run --rm --name service1 -p 45000:5000
your_image_name`.
Our container is now running and the host (the EC2 instance in this case) will
map its port 45000 to the container's port 5000 thanks to the `-p` argument.
You can now go to your local shell, run `curl your_ec2_public_ip:45000` and...
get a "Hello World" message back.

Lets take a moment to think about what just happened. We first created a Docker
image and ran it locally to test our app. We then pushed that image into the
public registry, pulled it from a freshly created EC2 instance and ran it in
exactly the same way. Since all the dependencies were already included in the
image, we didn't need to do anything on the server apart from installing Docker.
Same application, same Docker image, same version, same behavior and two completely
different environments.
What would happen now if we wanted to run the application on a different server?
Maybe an OpenStack server, or DigitalOcean or an old laptop at home that is not
doing anything else. It would be exactly the same! The only thing that we need
in every case is a Linux kernel and the Docker daemon running.

This is certainly great progress but what would happen if we want to make some
changes to our code and then redeploy the container again? We would have to push
the image again into the public repository, ssh into our instance, stop the
running container, pull the new image and finally run it again.
 Wouldn't it be great if Amazon could handle all of this for us? Meet Elastic
 Beanstalk!

# Using Elastic Beanstalk
[Elastic
Beanstalk](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/Welcome.html)
is a service provided by Amazon to quickly deploy and manage your applications.
You don't need to worry about creating instances or things like load balancing
and auto scaling. It can be used to run Web Applications in a variety of
languages and, of course, Docker containers.

We are going to use Elastic Beanstalk to run our app and see how we can deploy
new versions of it. We'll first need the `eb` tool, which can be installed using
brew with `brew install aws-elasticbeanstalk`. Next we'll need to initialize a
git repository with the app code (`git init .`) and commit what we have so far
(`git commit -a -m "Initial commit"`). 
Now we can run `eb init` to configure Elastic Beanstalk. This will be a one time
process that will tell EB how to deploy our application. The steps are pretty
self-explanatory. Just make sure that you select the "64bit Amazon Linux
2014.09 v1.0.10 running Docker" when you are asked for the solution stack.

Once that is done you can run `eb start`. It will ask you if you want to deploy
the last commit of your app, to which you'll respond yes. You can then follow
the logs shown on the console to get an idea of what eb is doing. This will
include creating a S3 bucket, creating an Elastic IP address, a security group
for your instance and finally launching your instance. In the end, you will see
a message indicating that your application was deployed and is ready to be
accessed. Something like: "Application is available at ..." an some URL.
Go to that URL and see the glorious Hello World message once again.

Now, let change the message on our app to say something different. Edit the
`app.py` file and change the return line for `return 'Hello Docker World from
%s' % socket.gethostname()`. Save and commit your changes to git. Now we'll use
eb to deploy our app once again. Run `eb push` and Elastic Beanstalk will deploy
the new version of your app. When that finishes you go back to the same URL as
before and see the updated message.

Interestingly, if you go to your AWS Dashboard and then to Elastic Beanstalk you
will be able to see, among other things, all the different versions of your app
that you have ever deployed so rollbacks are trivial. And this is all thanks to
the fact that EB created a new Docker image every time you deployed a new
version.
When you are done you can do a `eb delete` to clean up all the resources that
were created.

And that is all there is to it. Your changes get easily deployed with just one
command and, as an added bonus, you get to keep a record of all the different
versions of your app for easy rollback.

# Conclusion
Docker is revolutionizing the way we think about development and deployment.
Specially at a time were loosely coupled and small services are the way more and
more applications are getting architected. This is still a pretty new area with
lots of exciting tools under heavy development and increasing support from big
players in the industry. Amazon, for instance, announced its [EC2 Container
Service](http://aws.amazon.com/ecs/) in the last re:invent conference to offer
easy support for Docker containers, treating them as first class citizens inside
the AWS ecosystem. Similarly, in the last [DockerCon Europe
2014](http://europe.dockercon.com/) they announced, among other things, support
for [Docker hub in the
enterprise](https://blog.docker.com/2014/12/docker-announces-docker-hub-enterprise/)
and a set of [Alpha
tools](https://blog.docker.com/2014/12/announcing-docker-machine-swarm-and-compose-for-orchestrating-distributed-apps/)
to support easy Docker host provisioning, clustering and orchestration.
As well as Docker, other [container runtime
technologies](https://coreos.com/blog/rocket/) are making their way to the
scene. Where all these technologies and tools will end no one knows but one
thing is for sure, containers are here to stay and they will have a bigger and
bigger impact in the future. So start playing around with them!
