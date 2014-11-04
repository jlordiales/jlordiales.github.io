---
author: jlordiales
comments: true
share: true
date: 2014-11-01
layout: post
title: An overview of functional style programming in Java 8
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
  since the data can not be changed (accidentally or on purpose) this means that
  it can be freely shared improving memory requirements and enabling
  parallelism.  Second, because the function will return the same result for
  invocations with the same parameters (known as [referential
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
the current path. You could do something like this:

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
File[] csvFiles = new File(".")
                    .listFiles(pathname -> pathname.getAbsolutePath().endsWith("csv"));
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

Now imagine we want to filter a list of those users to get only the adult ones
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
Almost every Java application needs to work with collections of elements. They
need to create them, iterate through them, filter them, group their elements and
so on. And yet, dealing with Java collections always seems cumbersome.
Furthermore, you usually end up repeating the same boilerplate code like we saw
on the last example.
Let's look at another example of our `User` class to see how simple operations
such as filtering and grouping can become a real pain to handle. Imagine we want
to take our list of users and from there, we want to filter out all underage
users and then group them by sex. We basically want a method that returns a
`Map<Sex,List<User>>` so that then we can say something like `result.get(MALE)`
and get back a list of all the male users of 18 or more. We could write
something like the following:

{% highlight java %}
public Map<Sex, List<User>> groupUsers(List<User> allUsers) {
  Map<Sex, List<User>> result = new HashMap<>();
  for (User user : allUsers) {
    if (user.getAge() >= 18) {
      List<User> currentUsers = result.get(user.getSex());
      if (currentUsers == null) {
        currentUsers = new ArrayList<>();
        result.put(user.getSex(),currentUsers);
      }
      currentUsers.add(user);
    }
  }
  return result;
}
{% endhighlight %}

You can see there's a lot of boilerplate to iterate through the list, to filter
some users, to check whether we had a previous value on the map and so on. This
makes the code harder to understand at first glance.

With the Stream API introduced in Java 8 we can refactor the previous code to:

{% highlight java %}
public Map<Sex, List<User>> groupUsers(List<User> allUsers) {
  return allUsers
    .stream()
    .filter(user -> user.getAge() >= 18)
    .collect(groupingBy(User::getSex));
}
{% endhighlight %}

We'll cover streams in more details in future posts. For now it is worth noting
that even though Streams and Collections might seem similar (a sequence of
elements) they are crucially different. With Collections you have to manage the
iteration yourself, which is error prone and results in duplication of code.
With Streams the iteration is managed internally by the library, you only to
specify the behavior of what you are trying to do with it.

Another big advantage of Streams over Collections is that they take advantage of
parallelism without the need for the programmer to use convoluted and error
prone synchronization mechanisms. In the previous example, if we know that the
list of Users is potentially big we could split the stream to process it in
parallel by doing one simple modification:

{% highlight java %}
public Map<Sex, List<User>> groupUsers(List<User> allUsers) {
  return allUsers
    .parallelStream()
    .filter(user -> user.getAge() >= 18)
    .collect(groupingBy(User::getSex));
}
{% endhighlight %}

As always, if something seems to good to be true it usually is. So this "using
parallelism" with a one liner change has its own restrictions and might not work
as intended every time. We'll explore more of that on the next post.

If you were looking closely at the examples you might have noticed that the
`List` class has a `stream` and `parallelStream` methods that were not there
before Java 8. Where are these methods declared? They are coming from
`Collection`, an interface that `List` actually extends. But how did they add a
new method to an interface that is being heavily used and implemented by classes
outside of Java without breaking them? By implementing them on the `Collection`
interface itself using a new feature introduced in Java 8, default methods.

## Default methods
Like I said before, the new default method feature allows you to actually
implement a given method on the interface. Using the `stream` example from the
`Collection` interface, its implementation looks like:

{% highlight java %}
default Stream<E> stream() {
  return StreamSupport.stream(spliterator(), false);
}
{% endhighlight %}

Notice the new `default` keyword on the method signature. Similarly, now the
`List` interface has a sort method. So you don't need to do
`Collections.sort(myList, myComparator)` anymore, you can simply do
`myList.sort(myComparator)`. Again, the `sort` method was implemented as a
default method on the `List` interface.

This new feature is mainly there to help library providers to evolve their APIs
more easily, adding methods they didn't originally think about without breaking
existing clients. While this feature is certainly available to all Java users
(not only APIs designers) you should use it with care, as you could end up
making the code [harder to understand](http://goo.gl/vglwF1).

Note that default methods introduce certain problems for the compiler as well.
What happens if my interface `A` defines the default method `foo` and class `B`
implements `A` and overrides `foo`? Which method gets invoked when I do a `new
B().foo()`? Even more interesting, what if I also have a `C` interface with a
default method `foo` and `B` implements both `A` and `C`? Which one gets called?
There are two basic rules to decide which code gets executed in these
situations:

1. Classes always take priority over interfaces. If you have a default method in
   an interface and you override that method in a class, then the method in the
   class will always win

2. If you have two interfaces and both define the same default method then you
   have to explicitly tell Java which one it should use, otherwise you get a
   compilation error. For example:
{% highlight java %}
public interface A {
  default void foo() {
    System.out.println("A");
  }
}

public interface B {
  default void foo() {
    System.out.println("B");
  }
}

public class C implements A,B {
  public void foo() {
    B.super.foo();
  }
}
{% endhighlight %}

## Conclusions
Since the release of Java 1.0 in 1996, the language has been evolving gradually
over the years to accommodate the new technologies and practices of the
industry. Some would say that the changes introduced in Java 8 are in some ways
more profound that any other change introduced on Java's history. These changes
do not only move Java to a more functional style but also aim to provide
developers with the capabilities to make better use of concurrency, a crucial
aspect in times where the data that needs to be processed becomes larger and
larger.

It should be clear though, the fact that Java now has **some** of the features
that are available and largely used in functional languages doesn't
automatically make it a functional language as well. Java is still at its core
an Object Oriented, imperative programming language and will continue to be so.
As with most things in technology, these new features are merely tools that you
can add to your toolbox. It's your job to understand them and knowing when it
makes sense to use them and, more importantly, when it doesn't.

Cheers!
