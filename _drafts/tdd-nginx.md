---
author: jlordiales
comments: true
share: true
date: 2017-02-16
layout: post
title: Testing your NGINX
categories:
- testing
tags:
- NGINX
- tdd
- test
---
By now [NGINX](https://nginx.org/) needs no introduction. It has become a well
established and high performing web server and reverse proxy, partly thanks to
its event-driven and asynchronous approach to handling requests.
With the hundreds of different configurations and
[modules](https://www.nginx.com/resources/wiki/modules/) available for it,
NGINX configuration files can quickly become complex and full of logic that is
hard to test.
This post will present an approach to write automated tests that will verify
that your NGINX is doing what it's supposed to do from an external client point
of view.

# The use case
A very common use case for NGINX is to serve as a reverse proxy. This means,
typically, that it receives all clients requests and forwards them to the
appropriate backend server. You could setup your network configuration so that
your NGINX node is the only node accessible from the Internet, with the rest of
the services sitting safely inside your private network. 
In this scenario you can use NGINX to do all sorts of neat things like handling
authentication, caching, exposing a bunch of different services under a single
public URL, logging, etc.

But this also means that your NGINX node becomes a crucial part of your
architecture. A bug there can result in none of your backend services being
accessible anymore.
Therefore, it becomes extremely important to make sure that every time you make
a change to one of NGINX's configuration files everything keeps running
smoothly.
What kind of things can you actually test and, more importantly, how?

# Different levels of testing
As with any other software you have different levels at which you can test your
NGINX, each requiring a different effort level and providing different degrees
of confidence.

A first, very basic test you can do is to use NGINX's [command line
option](https://www.nginx.com/resources/wiki/start/topics/tutorials/commandline/#options) 
-t. This will tell NGINX not to run any process but rather just test the
configuration file to make sure that is syntactically valid.

That is a good start of course, but not nearly enough. Your config file can be
perfectly valid from a syntax point of view while still being completely broken
for your business case. You could be adding or deleting headers that you are not
supposed to, sending client requests to the wrong backend servers or a myriad
of other subtle but critical bugs.

So what can you do next? Well, hopefully you are not deploying the changes you
made locally directly to production. You probably have some sort of testing or
staging environment that is production-like and where you deploy your changes
first. 
You can always test manually in that environment after deploying but this comes
with the usual downsides of manual testing. It's boring, time consuming and
highly error prone for us humans. As your NGINX grows in complexity so is the
number of different scenarios that you would like to test for potential
regression bugs.
Furthermore, you might have different configuration files for different
environments which means that you can't really test your production config in
staging.

# Writing automated tests
There's a better way to do this, using the same configuration files that you use
in production, without the need to test manually and all of it running locally
in your machine.
But instead of telling you how you can do it I'm going to show you! We'll start
a small example config that we'll evolve using a TDD approach.  Lets jump right into it.

The first thing we are going to do is to run the official
[nginx](https://hub.docker.com/_/nginx/) docker image with its default
configuration and make sure we can connect to it:

{% highlight bash %}
$> docker run --rm --name nginx -d -p 8080:80 nginx
$> curl localhost:8080
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
{% endhighlight %}

We are up and running. What now? We'll replace the default config with our own.
We'll start really simple, with our NGINX serving as a reverse proxy for just
one of our backend services: the payment service.

![nginx-1](/images/nginx-test/nginx-1.svg)

Our NGINX config file looks something like this:

{% highlight bash %}
$> cat nginx.conf

user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    resolver 8.8.8.8;

    server {
      listen 80;

      location ~ ^/payment/(?<path>.*)$ {
        proxy_pass http://httpbin.org/status/$path;
      }
    }
}
{% endhighlight %}

The important part of this config is the server block at the end. It basically
says that it will listen on port 80 and any request that comes to the
`/payment/*` path will be sent to  `http://httpbin.org/status/*`. We are using
[httpbin](https://httpbin.org/) for now to make sure that our nginx is
forwarding stuff correctly. We'll come back to it in a bit.

Now that we have our config file, lets run our nginx container again but this
time mounting our configuration:

{% highlight bash %}
$> docker run -v $(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro \
-d --rm --name nginx -p 8080:80 nginx
{% endhighlight %}

Once the container is started, lets try to access our payment service:
{% highlight bash %}
$> curl -I localhost:8080/payment/201

HTTP/1.1 201 CREATED
Server: nginx/1.11.10
Date: Sat, 11 Mar 2017 15:38:25 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 0
Connection: keep-alive
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
{% endhighlight %}

It worked! Our nginx received the request on port 8080, saw that it was for
`/payment/201` and sent it forwards to `http://httpbin.org/status/201`

We have proved two things:
- Our nginx config file is valid
- Our proxy rule is working as intended

But running a few curls every time we make a change to our file is no fun, so
let's automate what we have so far.

## The testing framework
What we want to be able to do in a nutshell is to make an http request to a
given URL and assert on the response we get back. Any language with some decent
testing support and a basic http library should suffice. 
I'll use Ruby and RSpec for the examples here because it's really easy to setup
and the syntax for the test scenarios reads very well.

You can create an initial folder structure with `rspec --init`. Then inside the
`spec` directory you create a `payment_spec.rb` file with the following
contents:

{% highlight ruby %}

require 'httparty'

RSpec.describe "payment service nginx proxy" do

  it "Forwards requests to /payment/ to the payment service" do
    nginx_response = HTTParty.get('http://localhost:8080/payment/201')

    expect(nginx_response.code).to eq(201)
  end
end

{% endhighlight %}

If we now run rspec it will tell us that all scenarios are passing, which is
good. But just to make sure that our test is in fact working, lets break it
intentionally but changing the `eq(201)` by `eq(400)`. Now running `rspec` we
get

{% highlight bash %}
$> rspec
.

Finished in 0.25493 seconds (files took 0.21295 seconds to load)
1 example, 0 failures

{% endhighlight %}

We can test different paths on our requests using the same scenario but
iterating over different response codes instead of hard-coding it to 201:

{% highlight ruby %}
  [200, 204, 400, 500].each do |code|
    it "Forwards requests to /payment/#{code} to the payment service" do
      nginx_response = HTTParty.get "http://localhost:8080/payment/#{code}"

      expect(nginx_response.code).to eq(code)
    end
  end
{% endhighlight %}

We should check that our tests are still passing:
{% highlight bash %}
$> rspec
....

Finished in 1.01 seconds (files took 0.16233 seconds to load)
4 examples, 0 failures
{% endhighlight %}

What should happen if our nginx gets a request on a path that doesn't recognize?
We'd expect to get a 404 back, so lets write another scenario for that:

{% highlight ruby %}
  it "Responds with 404 when path is not valid" do
    nginx_response = HTTParty.get "http://localhost:8080/some/path/"

    expect(nginx_response.code).to eq(404)
  end
{% endhighlight %}

## Evolving our config
Now that we have a nice foundation to test our reverse proxy and make sure
everything works, lets evolve our config. But instead of writing the
implementation and then writing tests to make sure that it works lets take a TDD
approach.

The first thing we want to do is to make sure that web crawlers are not
accessing our nginx at all. So we want to have a `robots.txt` path at the root
level of our server sending back a response like: 
{% highlight raw %}
User-agent: *
Disallow: /
{% endhighlight %}

Lets write the test first! We'll create a new `robots_txt_spec.rb` file with:

{% highlight ruby %}
require 'httparty'

RSpec.describe "payment service nginx proxy" do
  it "provides a robots.txt path disallowing everything" do
    response = HTTParty.get "http://localhost:8080/robots.txt"

    expect(response.code).to eq(200)
    expect(response.body).to eq("User-agent: *\nDisallow: /\n")
  end
end
{% endhighlight %}

If we run `rspec` now it should hopefully fail, given we haven't implemented the
functionality yet

{% highlight bash %}
$> rspec
.....F

Failures:

  1) payment service nginx proxy provides a robots.txt path disallowing everything
     Failure/Error: expect(response.code).to eq(200)

       expected: 200
            got: 404

       (compared using ==)
     # ./spec/robots_txt_spec.rb:6:in `block (2 levels) in <top (required)>'

Finished in 1.03 seconds (files took 0.23175 seconds to load)
6 examples, 1 failure

Failed examples:

rspec ./spec/robots_txt_spec.rb:4 # payment service nginx proxy provides a robots.txt path disallowing everything
{% endhighlight %}

Cool! Let's make the changes to our configuration file now. I'll only show the
`server` block to save some space:

{% highlight bash %}
  server {
    listen 80;

    location ~ ^/robots.txt {return 200 "User-agent: *\nDisallow: /\n";}

    location ~ ^/payment/(?<path>.*)$ {
      proxy_pass http://httpbin.org/status/$path;
    }
  }
{% endhighlight %}

Running the tests again we get:
{% highlight bash %}
$> rspec
......

Finished in 1.14 seconds (files took 0.82051 seconds to load)
6 examples, 0 failures
{% endhighlight %}
