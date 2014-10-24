---
author: jlordiales
comments: true
date: 2012-12-24
layout: post
slug: the-ins-and-outs-of-immutability
title: The ins and outs of immutability
categories:
- Best Practices
- Java
tags:
- best practices
- defensive copies
- immutable
- java
- technology
---

So in my first post I talked a little bit about the [builder pattern]({% post_url 2012-12-13-the-builder-pattern-in-practice %}) and I mentioned a really powerful but yet overlooked concept: immutability.

What is an immutable class? It's simply a class whose instances can't be modified. Every value for the class' attributes is set on their declaration or in its constructor and they keep those values for the rest of the object's life-cycle. Java has quite a few immutable classes, such as _String_, all the boxed primitives (_Double_, _Integer_, _Float_, etc), _BigInteger_ and _BigDecimal_ among others. There is a good reason for this: immutable classes are easier to design, implement and use than mutable classes. Once they are instantiated they can only be in one state so they are less error prone and, as we'll see later in this post, they are more secure.

How do you ensure that a class is immutable? Just follow these 5 simple steps:



	
  1. **Don't provide any public methods that modify the object's state**, also known as mutators (such as setters).

	
  2. **Prevent the class from being extended**. This doesn't allow any malicious or careless class to extend our class and compromise its immutable behavior. The usual and easier way to do this is to mark the class as _final_, but there's another way that I'll mention in this post.

	
  3. **Make all fields _final_**. This is a way to let the compiler enforce point number 1 for you. Additionally, it clearly lets anyone who sees your code know that you don't want those fields to change their values once they are set.

	
  4. **Make all fields private**. This one should be pretty obvious and [you should follow it](http://www.javaworld.com/jw-05-2001/jw-0518-encapsulation.html) regardless of whether you're taking immutability into consideration or not, but I'm mentioning this just in case.

	
  5. **Never provide access to any mutable attribute**. If your class has a mutable object as one of its properties (such as a _List_, a _Map_ or any other mutable object from your domain problem) make sure that clients of your class can never get a reference to that object. This means that you should never directly return a reference to them from an accessor (e.g., a getter) and you should never initialize them on your constructor with a reference passed as parameter from a client. You should always make defensive copies in this case.


That's a lot of theory and no code, so lets see what a simple immutable class looks like and how it deals with the 5 steps I mentioned before:

{% highlight java %}
public class Book {
    private final String isbn;
    private final int publicationYear;
    private final List reviews;
    private Book(BookBuilder builder) {
        this.isbn = builder.isbn;
        this.publicationYear = builder.publicationYear;
        this.reviews = Lists.newArrayList(builder.reviews);
    }
    public String getIsbn() {
        return isbn;
    }
    public int getPublicationYear() {
        return publicationYear;
    }
    public List getReviews() {
        return Lists.newArrayList(reviews);
    }
    public static class BookBuilder {
        private String isbn;
        private int publicationYear;
        private List reviews;
        public BookBuilder isbn(String isbn) {
            this.isbn = isbn;
            return this;
        }
        public BookBuilder publicationYear(int year) {
            this.publicationYear = year;
            return this;
        }
        public BookBuilder reviews(List reviews) {
            this.reviews = reviews == null ? new ArrayList() : reviews;
            return this;
        }
        public Book build() {
            return new Book(this);
        }
    }
}
{% endhighlight %}

We'll go through the important points in this pretty simple class. First of all, as you've probably noticed, I'm using the builder pattern again. This is not just because I'm a big fan of it but also because I wanted to illustrate a few points that I didn't want to get into my previous post without first giving you a basic understanding of the concept of immutability. Now, let's go through the 5 steps that I mentioned you need to follow to make a class immutable and see if they hold valid for this _Book_ example:




	
    * **Don’t provide any public methods that modify the object’s state**. Notice that the only methods on the class are its private constructor and getters for its properties but no method to change the object's state.

	
    * **Prevent the class from being extended**. This one is quite tricky. I mentioned that the easiest way to ensure this was to make the class _final_ but the _Book _class is clearly not final. However, notice that the only constructor available is _private_.  The compiler makes sure that a class without public or protected constructors cannot be  subclassed. So in this case the _final_ keyword on the class declaration is not necessary but it might be a good idea to include it anyway just to make your intention clear to anyone who sees your code.

	
    * **Make all fields _final_**. Pretty straightforward, all attributes on the class are declared as _final_.

	
    * **Never provide access to any mutable attribute**. This one is actually quite interesting. Notice how the _Book_ class has a _List<String>_ attribute that is declared as _final_ and whose value is set on the class constructor. However, this _List_ is a mutable object. That is, while the _reviews_ reference cannot change once it is set, the content of the list can. A client with a reference to the same list could add or delete an element and, as a result, change the state of the _Book_ object after its creation. For this reason, note that on the _Book_ constructor we don't assign the reference directly. Instead, we use the [Guava library](http://code.google.com/p/guava-libraries/) to make a copy of the list by calling "`this.reviews = Lists.newArrayList(builder.reviews);`". The same situation can be seen on the `getReviews` method, where we return a copy of the list instead of the direct reference. It is worth noting that this example might be a bit oversimplified, because the _reviews_ list can only contain strings, which are immutable. If the type of the list is a mutable class then you would also have to make a copy of each object in the list and not just the list itself.



That last point illustrates why immutable classes result in cleaner designs and easier to read code. You can just share around those immutable objects without having to worry about defensive copies. In fact, you should never make any copies at all because any copy of the object would be forever equal to the original. A corollary is that immutable objects are just plain simple. They can be in only one state and they keep that state for their entire life. You can use the class constructor to check any invariants (i,e,. conditions that need to be valid on the class like range of values for one of its attributes) and then you can ensure that those invariants will remain true without any effort on your part or your clients.

Another huge benefit of immutable objects is that they are inherently thread-safe. They cannot be corrupted by multiple threads accessing the objects concurrently. This is, by far, the easiest and less error prone approach to provide thread safety in your application.

But what if you already have a _Book_ instance and you want to change the value of one of its attributes? In other words, you want to change the state of the object. On an immutable class this is, by definition, not possible. But, as with most things in software, there's always a workaround. In this particular case there's actually two.

The first option is to use the [Fluent Interface](http://martinfowler.com/bliki/FluentInterface.html) technique on the _Book_ class and have setter-like methods that actually create an object with the same values for all its attributes except for the one you want to change. In our example we would have to add the following to the _Book_ class:

{% highlight java %}
    private Book(BookBuilder builder) {
        this(builder.isbn, builder.publicationYear, builder.reviews);
    }
    private Book(String isbn, int publicationYear, List reviews) {
        this.isbn = isbn;
        this.publicationYear = publicationYear;
        this.reviews = Lists.newArrayList(reviews);
    }
    public Book withIsbn(String isbn) {
        return new Book(isbn,this.publicationYear, this.reviews);
    }
{% endhighlight %}

Note that we added a new private constructor where we can specify the value of each attribute and modified the old constructor to use the new one. Additionally, we added a new method that returns a new _Book_ object with the value we wanted for the _isbn_ attribute. The same concept applies to the rest of the class' attributes. This is known as a _functional approach_ because methods return the result of operating on their parameters without modifying them. This is to contrast it from the _procedural_ or _imperative_ approach where methods apply a procedure to their operands, thus changing their state.

This approach to generate new objects shows the only real disadvantage of immutable classes: they require us to create a new object for each distinct value we need and this can produce a considerable overhead in performance and memory consumption. This problem is magnified if you want to change several attributes of the object because you are generating a new object in each step and you end up discarding all intermediate objects and keeping just the last result.

We can provide a better alternative for the case of multi-step operations like the one I described on the last paragraph with the help of the builder pattern. Basically, we add a new constructor to the builder that takes an already created instance to set all its initial values. Then, the client can use the builder in the usual way to set all the desired values and then use the build method to create the final object. That way, we avoid creating intermediate objects with only some of the values we need. In our example this technique would look something like this on the builder side:

{% highlight java %}
public BookBuilder(Book book) {
    this.isbn = book.getIsbn();
    this.publicationYear = book.getPublicationYear();
    this.reviews = book.getReviews();
}
{% endhighlight %}

Then, on our clients, we can have:

{% highlight java %}
Book originalBook = getRandomBook();

Book modifiedBook = new BookBuilder(originalBook).isbn("123456").publicationYear(2011).build();
{% endhighlight %}

Now, obviously the builder is not thread-safe so you have to take all the usual precautions, such as not sharing a builder with multiple threads.

I mentioned that the fact that we have to create a new object for every change in state can have an overhead in performance and this is the only real disadvantage of immutable classes. However, object creation is one of the aspects of the JVM that is under continuous improvement. In fact, except for exceptional cases, object creation is a lot more efficient than you probably think. In any case, it's usually a good idea to come up with a simple and clear design and then, only after measuring, refactor for performance. Nine out of ten times when you try to guess where your code is taking so much time you'll discover that you were wrong. Additionally, the fact that immutable objects can be shared freely without having to worry about the consequences gives you the chance to encourage clients to reuse existing instances wherever possible, thus reducing considerably the number of objects created. A common way to do this is to provide public static final constants for the most common values. This technique is heavily used on the JDK, for example in _Boolean.FALSE_ or _BigDecimal.ZERO_. 

To conclude this post, if you want to take something out of it let it be this: **classes should be immutable unless there's a very good reason to make them mutable**. Don't automatically add a setter for every class attribute. If for some reason you absolutely can't make your class immutable, then limit its mutability as much as possible. The fewer states in which an object can be, the easier it is to think about the object and its invariants. And don't worry about the performance overhead of immutability, chances are that you won't have to worry about it.
