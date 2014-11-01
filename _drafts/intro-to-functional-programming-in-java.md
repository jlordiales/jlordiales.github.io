---
author: jlordiales
comments: true
share: true
date: 2014-11-01
layout: post
title: Functional style in Java, an overview
categories:
- Functional Programming
- Java 8
tags:
- Java
- Java 8
- Functional Programming
---

This is going to be the first on a series of posts where I'll explore in a bit of
detail the new functional programming ideas introduced by Java 8. In this post
I'll introduce some concepts and go in very high-level details about all the new
features introduced by Java 8. Subsequent posts will dive into more details
about each specific topic.

# Functional programming
Since the title of the post is "_{{ page.title }}_" it makes sense that we define
what functional programming means first. Unfortunately this is one of those
things that you can ask 50 different people and you will get 50 different
answers. Nevertheless I will give it a shot.

Functional programming is a style of programming (or a programming paradigm)
where programs are executed by evaluating expressions. This is in contrast to
imperative (or procedural) languages where computations are made by executing a
series of statements that usually change global state.
In functional programming, on the other hand, mutable state is usually avoided.
The output of a function is exclusively dependent on the values of its inputs.
This means that if we call a function `x` amount of times with the same
parameters we'll get exactly the same result every time. We already discussed in
a [previous post]({% post_url 2012-12-24-the-ins-and-outs-of-immutability %})
the benefits of immutable data but eliminating the side effects of functions
makes it a lot easier to reason about programs and is one of the main motivators
for functional programming.

So what makes a given language functional? Well, again, there doesn't seem to be
a clear [consensus](http://goo.gl/5sXbmL) but the main features that are
expected in any functional language are:

- First class and Higher Order Functions: these have a strong mathematical
  background but in layman terms it means that the language treats functions as
  first class citizens. In other words you can assign functions to variables,
  pass them around in parameters to other functions, return them from other
  functions and define them inline as [lambda
  expressions](http://en.wikipedia.org/wiki/Anonymous_function)

- Pure functions: functions with absolutely no side effects or that operate on
  immutable data. As we discussed before, this has several benefits. First,
  since the data can not be changed (accidentally or not) this means that it can
  be freely shared improving memory requirements and enabling parallelism.
  Second, because the function will return the same result for invocations with
  the same parameters (known as [referential
  transparency](http://en.wikipedia.org/wiki/Referential_transparency_(computer_science)))
  the result can be easily cached and returned any number of times, improving
  performance. Finally, since the computation of functions are referentially
  transparent they can be computed at any time and still give the same result.
  This enables [lazy
  evaluation](https://www.haskell.org/haskellwiki/Lazy_evaluation) to defer the
  computation of values until the point when they are needed. A nice application
  of this is to be able to have [infinite data
  structures](http://en.wikipedia.org/wiki/Lazy_evaluation#Working_with_infinite_data_structures)

- Recursion: functional languages usually make heavy use of
  [recursion](http://en.wikipedia.org/wiki/Recursion_(computer_science)),
  specially to iterate over structures

- Closures: since functions are treated like first class citizens it's really
  useful to be able to pass them around together with their referencing
  environment (a reference to each non-local variable of that function). You can
  see an example of this
  [here](http://programmers.stackexchange.com/questions/40454/what-is-a-closure/40708#40708)

- Currying or partial application: also related to higher order functions. In
  simple terms, the ability to evaluate functions with multiple parameters one
  by one, producing on each step a new function with one less argument. For
  example: `f(x,y) = x + y`. We can call `f(2,3)` to get `5` but we could also
  evaluate `f(3) = g(y) = 3 + y`.

These are some of the features expected in a functional language. Certainly Java
is not a functional language (and it's probably never going to be) when you
compare it with other pure functional languages like Haskell or Erlang. But
that doesn't mean that you can not use a functional style in Java. However,
until Java 7 the syntax and facilities of the language made it really hard and
cumbersome to do so.

# Java with a functional style
Java 8 introduces a set of changes and syntactic sugar that reflect a move away
from the classical object oriented paradigm towards the functional style
spectrum. Again, this doesn't mean that now Java has suddenly became a
functional language. It only means that you can now combine some aspects of OO
with some aspects of functional programming to produce easier to read, write and
maintain applications.
We'll see an overview of these new features in the following sections.

## Methods as first class citizens
Remember how we talked higher order functions and being able to pass them around
as parameters to other functions? In Java the concept of function is associated
with a method. Traditionally you could define methods inside classes and then
pass those classes to other methods but you could not pass the method itself.
Let see this with an example. Let's say you want to list all directories under
the current path. You could do something like this;

{% highlight java %}
File[] directories = new File(".").listFiles(new FileFilter() {
    @Override
    public boolean accept(File pathname) {
      return pathname.isDirectory();
    }
});
{% endhighlight %}

You use the `listFiles` method of the `File` class and you pass a `FileFilter`
instance to tell it which of the files it should actually return. That is not
too bad but it does seem a bit weird that we have to create an anonymous class
just to be able to call the `isDirectory` method on the `File` object.

To make this easier to write and read, Java 8 introduced the concept of method
reference. So you could rewrite the previous code as:

{% highlight java %}
File[] directories = new File(".").listFiles(File::isDirectory);
{% endhighlight %}

Isn't that a lot better? Using the reference operator (`::`) you can create
method references in the same way you create object references with the keyword
`new` and the pass those method references around like we saw.

## Lambdas
We quickly mentioned the concept of lambdas or anonymous functions and how they
are a key aspect of functional languages. We'll see how their introduction in
Java 8 makes our life easier by using the file filtering example again, except
that this time we want to return only the `csv` files. Previous to Java 8 you
could do something like the following:

{% highlight java %}
File[] csvFiles = new File(".").listFiles(new FileFilter() {
    @Override
    public boolean accept(File pathname) {
      return pathname.getAbsolutePath().endsWith("csv");
    }
});
{% endhighlight %}

In this case, however, we can not use a method reference because there is no
method on the `File` class that takes an instance of this class and returns a
`boolean` to determine whether the file is a csv or not. We could create a class
with such a method and then pass a reference to it, but that wouldn't improve
things much with respect to the anonymous class version we just saw. Instead, we
can use the new concept of an anonymous method like this:

{% highlight java %}
File[] csvFiles = new File(".").listFiles(pathname -> pathname.getAbsolutePath().endsWith("csv"));
{% endhighlight %}

This creates a method that takes a `pathname` parameter of type `File`
(implicit) and returns true if that file ends with csv.

Lets look at other example that will set the ground for the next topic. Imagine
that we have a simple `User` class:

{% highlight java %}
public class User {
  private final int age;
  private final String name;
  private final Sex sex;

  public User(int age, String name, Sex sex) {
    this.age = age;
    this.name = name;
    this.sex = sex;
  }

  public int getAge() {
    return age;
  }

  public Sex getSex() {
    return sex;
  }
}

public enum Sex {
  MALE, FEMALE
}
{% endhighlight %}

Now imagine we want to filter a list of those users to get only the adults ones
(18 or older). We could do a typical for loop iteration like:

{% highlight java %}
public List<User> adults(List<User> allUsers) {
  List<User> adultUsers = new ArrayList<>();
  for (User user : allUsers) {
    if (user.getAge() >= 18) {
      adultUsers.add(user);
    }
  }
  return adultUsers;
}
{% endhighlight %}

Now imagine we want to do filter them again but this time we want to get just
the male users. Very similar to the last code we could do:

{% highlight java %}
public List<User> males(List<User> allUsers) {
  List<User> maleUsers = new ArrayList<>();
  for (User user : allUsers) {
    if (MALE.equals(user.getSex())) {
      maleUsers.add(user);
    }
  }
  return maleUsers;
}
{% endhighlight %}

Those two snippets of code look suspiciously similar. And they should since I
copy pasted the first into the second and just changed the condition evaluation.

How can we remove this duplication? Java 8 introduced the `Predicate` interface.
This interface defines a single method `boolean test(T t)`. Similar things
already existed in
[Guava](http://docs.guava-libraries.googlecode.com/git/javadoc/com/google/common/base/Predicate.html)
and [Apache
Commons](https://commons.apache.org/proper/commons-collections/javadocs/api-3.2.1/org/apache/commons/collections/Predicate.html)
but the nice thing about this new interface in Java 8 is that it's a functional
interface. What this basically means is that it can be used as the assignment
target of lambda expressions or method references.  That's a lot of fancy words
so let's see how we can refactor the previous example to use this feature:

{% highlight java %}
public List<User> filterUsers(List<User> allUsers, Predicate<User> predicate) {
  List<User> result = new ArrayList<>();
  for (User user : allUsers) {
    if (predicate.test(user)) {
      result.add(user);
    }
  }
  return result;
}
{% endhighlight %}

This is the same iteration and filtering as before, except that now we are
delegating the condition evaluation to the `Predicate`.
And here is where the functional interface definition we saw before comes in.
You don't need to create an implementation of the `Predicate` interface, you can
just pass a method reference or lambda. Suddenly, your two filter methods are as
simple as:

{% highlight java %}
public List<User> adults(List<User> allUsers) {
  return filterUsers(allUsers, user -> user.getAge() >= 18);
}

public List<User> males(List<User> allUsers) {
  return filterUsers(allUsers, User::isMale);
}
{% endhighlight %}

It seems like iterating through a Collection filtering its elements is a pretty
common operation. Do we really need to define a filter method that takes a
`Predicate` every time we need it? The answer is no, you don't. Meet Java 8
Streams.

## Streams

