---
author: jlordiales
comments: true
share: true
date: 2014-11-08
layout: post
title: Lambdas and Functional interfaces in Java 8
categories:
- Functional Programming
- Java 8
tags:
- Java
- Java 8
- Functional Programming
- Lambdas
- Functional interfaces
- Method reference
---

In the 
[previous post]({% post_url 2014-11-01-overview-java-8 %}) we saw an
overview of what functional programming is and how the new features of Java 8
allow developers to write their applications using a more functional style. One
of the main points in this new version of the language was the introduction of
lambdas. Together with lambdas came the use of functional interfaces and methods
references. This post will explore these features in more detail, showing
when to use them, the restrictions around them and how you can use them
to make your code more readable and concise.

# Lambdas
First things first, what is a lambda (or lambda expression)? A lambda is an
anonymous method that doesn't have a name but it has a list of parameters, a
body, a return type and potentially a list of exception that the lambda can
throw. Unlike regular class methods, lambdas are not actually associated with
any class. They can also be assigned to variables or passed as arguments to
other methods. The name _lambda expression_ comes from the field of
[mathematics](http://en.wikipedia.org/wiki/Lambda_calculus).

We saw an example of a lambda expression in the 
[previous post]({% post_url 2014-11-01-overview-java-8 %}), using an example
from the `File` class to list `csv` files:

{% highlight java %}
File[] csvFiles = new File(".")
                    .listFiles(pathname -> pathname.getAbsolutePath().endsWith("csv"));
{% endhighlight %}

Here, we are passing a lambda expression to the `listFiles` method that takes
one input parameter and returns a boolean value. I also mentioned that you can
assign lambdas to variables, so the previous code is functionally equivalent to:

{% highlight java %}
FileFilter csvFilter = pathname -> pathname.getAbsolutePath().endsWith("csv");
File[] csvFiles = new File(".").listFiles(csvFilter);
{% endhighlight %}

How did we use to do that before Java 8? Like this:

{% highlight java %}
File[] csvFiles = new File(".").listFiles(new FileFilter() {
    @Override
    public boolean accept(File pathname) {
      return pathname.getAbsolutePath().endsWith("csv");
    }
});
{% endhighlight %}

You have to admit that the snippet using a lambda expression looks much more
concise and cleaner. In the last snippet we have to create an anonymous class
with an `accept` method (with all the verbosity that it implies). In the first
one, we just need to specify our logic.

This brings an interesting question, if the `listFiles` method takes a parameter
of `FileFilter` type (which is an interface), how come we can pass a lambda
instead? We can do this because the `FileFilter` interface is a functional
interface.

# Functional interfaces
In a nutshell, a functional interface is an interface that specifies exactly
**one** abstract method. So the `FileFilter` interface we saw before is
specified as:

{% highlight java %}
@FunctionalInterface
public interface FileFilter {
  boolean accept(File pathname);
}
{% endhighlight %}

Another example, is the `Runnable` interface:

{% highlight java %}
@FunctionalInterface
public interface Runnable {
  public abstract void run();
}
{% endhighlight %}

You can see that both of these interfaces have a `@FunctionalInterface`
annotation. So what does that do? First it informs people who look at that
interface that it is intended to be a functional interface and that they can use
lambdas and method references wherever they are expected. Second, it works as a 
compile-time check to make sure that the interface is indeed functional. If you
add this annotation to your interface and it is not in fact functional then you
will get a nice compile error leting you know this. It is worth noting that the
annotation is not actually required but it is usually a good idea to have it
there for the reasons I mentioned before.

