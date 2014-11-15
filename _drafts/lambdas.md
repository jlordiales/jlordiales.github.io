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
will get a nice compile error letting you know this. It is worth noting that the
annotation is not actually required but it is usually a good idea to have it
there for the reasons I mentioned before.

# Some useful functional interfaces
Now that we know what a functional interface is and how it can be used, lets
look at some pretty useful interfaces provided by Java in its
`java.function.util` package

## Predicate
The predicate interface defines a simple `test` method that takes an object and
returns a boolean. It looks something like:

{% highlight java %}
@FunctionalInterface
public interface Predicate<T> {
    boolean test(T t);
}
{% endhighlight %}

This is pretty useful for things like filtering. You could have a generic method
to filter a list:

{% highlight java %}
public static <T> List<T> filter(List<T> list, Predicate<T> predicate) {
  List<T> result = new ArrayList<>();
  for (T elem : list) {
    if (predicate.test(elem)) {
      result.add(elem);
    }
  }
  return result;
}
{% endhighlight %}

And then create a predicate for your particular object. For example, a predicate
that given a `User` returns true if his age is greater than or equal to 18:

{% highlight java %}
public enum Sex {
  MALE, FEMALE
}

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

  public boolean isMale() {
    return MALE.equals(sex);
  }
}

Predicate<User> predicate = user -> user.getAge() >= 18;
{% endhighlight %}

A pretty useful functionality about predicates is that they can be composed
together to form more complex ones. For instance, what do you do if suddenly you
want a new `User` predicate that returns true for all users who are less than
18? Do you create a new predicate like the previous one but changing the `>=` by
`<`? Luckily, you don't have to because the `Predicate` interface provides 3
methods to compose several predicates: `and`, `or` and `negate`. So the previous
example could be written as:

{% highlight java %}
Predicate<User> older = user -> user.getAge() >= 18;
Predicate<User> younger = older.negate();
{% endhighlight %}

Similarly, if we want a predicate that returns true for all the male users older
or equal to 18, we could write it as:

{% highlight java %}
Predicate<User> older = user -> user.getAge() >= 18;
Predicate<User> adultMales = older.and(User::isMale);
{% endhighlight %}

That last example shows that we can use method references where a `Predicate` is
expected. In fact, we can use a method reference wherever a functional interface
is expected. We quickly saw method references in the [previous post]({%
post_url 2014-11-01-overview-java-8 %}) but we'll discuss more about them later
on.

## Function
The java.util.function.Function interface is defined as:

{% highlight java %}
@FunctionalInterface
public interface Function<T, R> {
  R apply(T t);
}
{% endhighlight %}

What this basically does is take an input of type `T` and transform it somehow
to return an object of type `R`. Note that the `Predicate` interface can be seen
as a special case of a `Function` where `R` is always a boolean value. Following
our `User` examples, imagine we want a function that given an `User` instance it
returns that user's name length instance it returns that user's name length. We
could write this function like this:

{% highlight java %}
Function<User,Integer> nameLength = user -> user.getName().length();
{% endhighlight %}

Like predicates, the `Function` interface also has some useful methods to
compose several functions. The two methods offered are `compose` and `andThen`.
The difference between them is subtle but important. To understand this better,
imagine we have the following 2 functions:

{% highlight java %}
Function<Integer,Integer> sumOne = number -> number + 1;
Function<Integer,Integer> duplicate = number -> number * 2;
{% endhighlight %}

We can then create 2 new functions in the following way:

{% highlight java %}
Function<Integer, Integer> composed = sumOne.compose(duplicate);
Function<Integer, Integer> andThen = sumOne.andThen(duplicate);

System.out.println(composed.apply(2));
System.out.println(andThen.apply(2));
{% endhighlight %}

The `composed` function will first apply `duplicate` and then apply `sumOne` on
the result. In other words, composing `sumOne` with `duplicate` will result in
`sumOne(duplicate(x))` and the first System.out will print 5. The `andThen`
function will do exactly the opposite, it will first apply `sumOne` and then
apply `duplicate` on the result. In this case the second System.out will print
6.

## Consumer
The java.util.function.Consumer interface defines an `accept` method that takes
a paramter of type `T` and returns no value. In other words:

{% highlight java%}
@FunctionalInterface
public interface Consumer<T> {
    void accept(T t);
}
{% endhighlight %}

This interface is useful when you want to access an element and perform some
operation on it. For instance, starting with Java 8, lists have a `forEach`
method where you can pass a `Consumer<T>` and this function will be applied to
each element on the list. 

So imagine that you want to print to `System.out` each element on a list. You
could do that in the following way:

{% highlight java %}
List<String> users = Arrays.asList("java","8","rocks");
users.forEach(elem -> System.out.println(elem));
{% endhighlight %}

The implementation of the `forEach` method is actually quite straightforward:

{% highlight java %}
void forEach(Consumer<? super T> action) {
  for (T t : this) {
    action.accept(t);
  }
}
{% endhighlight %}

# Method references
Lambda expressions are undoubtedly a great construct to make your code more
compact. However, some times all you do in your lambda is to call an individual
method potentially passing some parameter to it. In these cases you can often
replace your lambda expression by a method reference. 

Method references are compact ways to create lambda expressions for methods that
already have a name. For instance, in the previous section we saw an example of
the `forEach` method:

{% highlight java %}
List<String> users = Arrays.asList("java","8","rocks");
users.forEach(elem -> System.out.println(elem));
{% endhighlight %}

Here, our lambda expression is only calling the `System.out.println` method.
Therefore, we could rewrite it like this:

{% highlight java %}
List<String> users = Arrays.asList("java","8","rocks");
users.forEach(System.out::println);
{% endhighlight %}
