---
author: jlordiales
comments: true
share: true
date: 2012-12-26
layout: post
slug: static-factory-methods-vs-traditional-constructors
title: Static factory methods vs traditional constructors
categories:
- Best Practices
- Java
tags:
- builder
- constructors
- factory
- interface-based API
- java
- patterns
- static
- type inference
---

I've previously talked a little bit about the 
[Builder Pattern]({% post_url 2012-12-13-the-builder-pattern-in-practice %}), 
a useful pattern to instantiate classes with several (possibly optional)
attributes that results in easier to read, write and maintain client code, among
other benefits. Today, I'm going to continue exploring object creation
techniques but this time for a more general case.

Take the following example, which is by no means a useful class other than to
make my point. We have a _RandomIntGenerator_ class that, as the name suggests,
generates random int numbers. Something like:

{% highlight java %}
public class RandomIntGenerator {
  private final int min;
  private final int max;

  public int next() {...}
}
{% endhighlight %}

Our generator takes a minimum and maximum and then generates random numbers
between those 2 values. Notice that the two attributes are declared _final_ so
we have to initialize them either on their declaration or in the class
constructor. Let's go with the constructor:

{% highlight java %}
public RandomIntGenerator(int min, int max) {
  this.min = min;
  this.max = max;
}
{% endhighlight %}

Now, we also want to give our clients the possibility to specify just a minimum
value and then generate random values between that minimum and the max possible
value for ints. So we add a second constructor:

{% highlight java %}
public RandomIntGenerator(int min) {
  this.min = min;
  this.max = Integer.MAX_VALUE;
}
{% endhighlight %}

So far so good, right? But in the same way that we provided a constructor to
just specify the minimum value, we want to do the same for just the maximum.
We'll just add a third constructor like:

{% highlight java %}
public RandomIntGenerator(int max) {
  this.min = Integer.MIN_VALUE;
  this.max = max;
}
{% endhighlight %}

If you try that, you'll get a compilation error that goes: _Duplicate method
RandomIntGenerator(int) in type RandomIntGenerator_. What's wrong?

The problem is that constructors, by definition, have no names. As such, a class
can only have one constructor with a given signature in the same way that you
can't have two methods with the same signature (same return type, name and
parameters type). That is why when we tried to add the _RandomIntGenerator(int
max)_ constructor we got that compilation error, because we already had the
_RandomIntGenerator(int min)_ one.

Is there something we can do in cases like this one? Not with constructors but
fortunately there's something else we can use: **static factory methods**, which
are simply public static methods that return an instance of the class. You've
probably used this technique without even realizing it. Have you ever used
_Boolean.valueOf_? It looks something like:

{% highlight java %}
public static Boolean valueOf(boolean b) {
  return (b ? TRUE : FALSE);
}
{% endhighlight %}

Applying static factories to our `RandomIntGenerator` example, we could get:

{% highlight java %}
public class RandomIntGenerator {
  private final int min;
  private final int max;

  private RandomIntGenerator(int min, int max) {
    this.min = min;
    this.max = max;
  }

  public static RandomIntGenerator between(int max, int min) {
    return new RandomIntGenerator(min, max);
  }

  public static RandomIntGenerator biggerThan(int min) {
    return new RandomIntGenerator(min, Integer.MAX_VALUE);
  }

  public static RandomIntGenerator smallerThan(int max) {
    return new RandomIntGenerator(Integer.MIN_VALUE, max);
  }

  public int next() {...}
}
{% endhighlight %}

Note how the constructor was made private to ensure that the class is only
instantiated through its public static factory methods. Also note how your
intent is clearly expressed when you have a client with
`RandomIntGenerator.between(10,20)` instead of `new RandomIntGenerator(10,20)`

It's worth mentioning that this technique is not the same as the Factory method
Design Pattern from the [Gang of
Four](http://en.wikipedia.org/wiki/Design_Patterns_(book)). Any class can
provide static factory methods instead of, or in addition to, constructors. So
what are the advantages and disadvantages of this technique?

We already mentioned the first advantage of static factory methods: unlike
constructors they have names. This has two direct consequences,
	
  1. We can provide a meaningful name for our constructors.
	
  2. We can provide several constructors with the same number and type of
     parameters, something that as we saw earlier we can't do with class
     constructors.

Another advantage of static factories is that, unlike constructors, they are not
required to return a new object every time they are invoked. This is extremely
useful when working with 
[immutable classes]({% post_url 2012-12-24-the-ins-and-outs-of-immutability %}) 
to provide constant objects for common used values and avoid creating
unnecessary duplicate objects. The `Boolean.valueOf` code that I showed
previously illustrates this point perfectly. Notice that this static method
returns either `TRUE` or `FALSE`, both immutable Boolean objects.

A third advantage of static factory methods is that they can return an object of
any subtype of their return type. This gives you the possibility to change the
return type freely without affecting clients. Moreover, you can hide
implementation classes and have an [interface-based
API](http://en.wikipedia.org/wiki/Interface-based_programming), which is usually
a really good idea. But I think this can be better seen by an example.
 
Remember the `RandomIntGenerator` at the beginning of this post? Let's make that
a little bit more complicated. Imagine that we now want to provide random
generators not just for integers but for other data-types like String, Double or
Long. They are all going to have a `next()` method that returns a random object
of a particular type, so we could start with an interface like:

{% highlight java %}
public interface RandomGenerator<T> {
  T next();
}
{% endhighlight %}

Our first implementation of the `RandomIntGenerator` now becomes:

{% highlight java %}
class RandomIntGenerator implements RandomGenerator<Integer> {
  private final int min;
  private final int max;

  RandomIntGenerator(int min, int max) {
    this.min = min;
    this.max = max;
  }

  public Integer next() {...}
}
{% endhighlight %}

We could also have a String generator:

{% highlight java %}
class RandomStringGenerator implements RandomGenerator<String> {
  private final String prefix;

  RandomStringGenerator(String prefix) {
    this.prefix = prefix;
  }

  public String next() {...}
}
{% endhighlight %}

Notice how all the classes are declared package-private (default scope) and so
are their constructors. This means that no client outside of their package can
create instances of these generators. So what do we do? Tip: It starts with
"static" and ends with "methods".  Consider the following class:

{% highlight java %}
public final class RandomGenerators {
  // Suppresses default constructor, ensuring non-instantiability.
  private RandomGenerators() {}

  public static final RandomGenerator<Integer> getIntGenerator() {
    return new RandomIntGenerator(Integer.MIN_VALUE, Integer.MAX_VALUE);
  }

  public static final RandomGenerator<String> getStringGenerator() {
    return new RandomStringGenerator("");
  }
}
{% endhighlight %}

RandomGenerators` is just a noninstantiable utility class with nothing else than
static factory methods. Being on the same package as the different generators
this class can effectively access and instantiate those classes. But here comes
the interesting part. Note that the methods only return the `RandomGenerator`
interface, and that's all the clients need really. If they get a
`RandomGenerator<Integer>` they know that they can call `next()` and get a
random integer.  Imagine that next month we code a super efficient new integer
generator. Provided that this new class implements `RandomGenerator<Integer>` we
can change the return type of the static factory method and all clients are now
magically using the new implementation without them even noticing the change.

Classes like `RandomGenerators` are quite common both on the JDK and on third
party libraries. You can see examples in `Collections` (in java.util), `Lists`,
`Sets` or `Maps` in [Guava](http://code.google.com/p/guava-libraries/). The
naming convention is usually the same: if you have an interface named `Type` you
put your static factory methods in a noninstantiable class named `Types`.

A final advantage of static factories is that they make instantiating
parameterized classes a lot less verbose. Have you ever had to write code like
this?

{% highlight java %}
Map<String, List<String>> map = new HashMap<String, List<String>>();
{% endhighlight %}

You are repeating the same parameters twice on the same line of code. Wouldn't
it be nice if the right side of the assign could be _inferred_ from the left
side? Well, with static factories it can. The following code is taken from
Guava's `Maps` class:

{% highlight java %}
public static <K, V> HashMap<K, V> newHashMap() {
  return new HashMap<K, V>();
}
{% endhighlight %}

So now our client code becomes:

{% highlight java %}
Map<String, List<String>> map = Maps.newHashMap();
{% endhighlight %}

Pretty nice, isn't it? This capability is known as [Type
inference](http://docs.oracle.com/javase/tutorial/java/generics/genTypeInference.html).
It's worth mentioning that Java 7 introduced type inference through the use of
the [diamond operator](http://www.javaworld.com/community/node/7567). So if
you're using Java 7 you can write the previous example as:

{% highlight java %}
Map<String, List<String>> map = new HashMap<>();
{% endhighlight %}

The main disadvantage of static factories is that classes without public or
protected constructors cannot be extended. But this might be actually a good
thing in some cases because it encourages developers to [favor composition over
inheritance](http://en.wikipedia.org/wiki/Composition_over_inheritance).

To summarize, static factory methods provide a lot of benefits and just one
drawback that might actually not be a problem when you think about it.
Therefore, resist the urge to automatically provide public constructors and
evaluate if static factories are a better fit for your class.
