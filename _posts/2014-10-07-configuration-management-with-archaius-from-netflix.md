---
author: jlordiales
comments: true
share: true
date: 2014-10-07
layout: post
slug: configuration-management-with-archaius-from-netflix
title: Configuration management with Archaius (from Netflix)
wordpress_id: 331
categories:
- Configuration Management
tags:
- archaius
- configuration management
- java
- netflix
---

In this post I'll talk about [Archaius](https://github.com/Netflix/archaius), a
pretty cool and easy to use Configuration Management tool from Netflix.

Have you ever read your configuration variables like this?

{% highlight java %}
String prop = System.getProperty("myProperty");
int x = DEFAULT_VALUE;
try {
  x = Integer.parseInt(prop);
} catch (NumberFormatException e) {
  // handle format issues
}
myMethod(x);
{% endhighlight %}

Or maybe you have a properties file that you read using
[Spring](http://docs.spring.io/spring/docs/current/javadoc-api/org/springframework/context/annotation/PropertySource.html).
Or maybe you have a simple key/value table in your DB with some properties that
you read from there?  Or you get them from an external REST endpoint? Or from
other type of key/value store like Redis or Memcached?

Whatever the case might be your configuration variables might be coming from a
lot of different sources and, specially if your app uses more than one, this can
become difficult to maintain. Additionally, you don't want to do a re-deploy
every time you need to change the value of one of your properties, particularly
for [feature toogles](http://martinfowler.com/bliki/FeatureToggle.html).

Luckily, the Netflix folks already had these issues and came up with a solution
that they were kind enough to open source. If you haven't seen [Netflix Github
repository](http://netflix.github.io/) I strongly recommend that you take a
look. They have some serious cool projects that could be just the thing your
application needs. One of those projects is the one that concerns us today:
[Archaius](https://github.com/Netflix/archaius).

Their wiki and examples should give you a very good idea of what Archaius is and
what it is useful for. For now I'll just say that Archaius is an extension of
[Apache's Common Configuration
library](http://commons.apache.org/proper/commons-configuration/) that allows
you to retrieve properties from several dynamic sources and that it solves all
the issues mentioned previously (heterogeneous sources of properties, run-time
changes, etc.).

Rather than going into much details about what the tool is and does I'll go with
some examples instead.  What is the simplest possible example to use Archaius to
read a property file? The well known "Hello World":

{% highlight java %}
public class ApplicationConfig {

  public String getStringProperty(String key, String defaultValue) {
    final DynamicStringProperty property = DynamicPropertyFactory.getInstance().getStringProperty(key,
        defaultValue);
    return property.get();
  }
}

public class ApplicationConfigTest {
  private ApplicationConfig appConfig = new ApplicationConfig();

  @Test
  public void shouldRetrieveThePropertyByKey() {
    String property = appConfig.getStringProperty("hello.world.message", "default message");

    assertThat(property, is("Hello Archaius World!"));
  }

  @Test
  public void shouldRetrieveDefaultValueWhenKeyIsNotPresent() {
    String property = appConfig.getStringProperty("some.key", "default message");

    assertThat(property, is("default message"));
  }
}
{% endhighlight %}

That code, together with a "config.properties" file somewhere in your classpath
(src/main/resources by convention in Maven and Gradle for example).

Notice that you don't need to tell Archaius where to find your properties file
because the default name that he is going to be looking for is
"config.properties". This example doesn't seem like a big improvement over what
you would usually do with Spring or any other tool but remember that this is
just a "Hello World" and bear with me to see more interesting use cases.

What if you don't want or can't name your property file "config.property"? In
that case you need to tell Archaius where to look for this file. You can easily
do this changing the system property
'archaius.configurationSource.defaultFileName', either passing it as a
parameter to the vm when you start your application

{% highlight bash %}
java ... -Darchaius.configurationSource.defaultFileName=customName.properties 
{% endhighlight %}

or in the code itself:

{% highlight java %}
public class ApplicationConfig {
  static {
    System.setProperty("archaius.configurationSource.defaultFileName", "customConfig.properties");
  }

  public String getStringProperty(String key, String defaultValue) {
    final DynamicStringProperty property = DynamicPropertyFactory.getInstance().getStringProperty(key,
        defaultValue);
    return property.get();
  }
}
{% endhighlight %}

Simple enough, right?

Now, what if you want to read several properties files? You can easily define a
chain of property files and the order in which they should be loaded starting
from the default file which is loaded first. From there, you can specify a
special property with key "@next=nextFile.properties" to tell Archaius which is
the next file that should be loaded.  In our example so far, we could add the
following line to our "customConfig.properties" file:
"@next=secondConfig.properties" and add the corresponding
"secondConfig.properties" to our resources folder with the following content:
"cascade.property=cascade value".

We can see this working by adding the following test to our
ApplicationConfigTest class:

{% highlight java %}
@Test
public void shouldReadCascadeConfigurationFiles() {
  String property = appConfig.getStringProperty("cascade.property", "not found");

  assertThat(property, is("cascade value"));
}
{% endhighlight %}

Note that we are getting the property from the new file without any additional
change to our ApplicationConfig class. This is completely transparent from the
point of view of our client.

Until now, we have been reading properties just from different property files
but what if you want to read them from a different source?  In the most general
case, you can code your own logic by implementing
"com.netflix.config.PolledConfigurationSource".  If that new source is a
database that can be accessed through JDBC then Archaius already provides a
"JDBCConfigurationSource" that you can use. You only need to tell him what query
he should use to get the properties and which columns represent the property key
and property value.

So our example would look like:

{% highlight java %}
@Component
public class ApplicationConfig {
  static {
    System.setProperty("archaius.configurationSource.defaultFileName", "customConfig.properties");
  }

  private final DataSource dataSource;

  @Autowired
    public ApplicationConfig(DataSource dataSource) {
      this.dataSource = dataSource;
      installJdbcSource();
    }

  public String getStringProperty(String key, String defaultValue) {
    final DynamicStringProperty property = DynamicPropertyFactory.getInstance().getStringProperty(key,
        defaultValue);
    return property.get();
  }

  private void installJdbcSource() {
    if (!isConfigurationInstalled()) {
      PolledConfigurationSource source = new JDBCConfigurationSource(dataSource,
          "select distinct property_key, property_value from properties", "property_key", "property_value");
      DynamicConfiguration configuration = new DynamicConfiguration(source,
          new FixedDelayPollingScheduler(100, 1000, true));

      ConfigurationManager.install(configuration);
    }
  }
}
{% endhighlight %}

We are using Spring to autowire a data source that will use an in-memory H2
database with a simple key/value table. Note how we create a new
_PolledConfigurationSource_ using the _JDBCConfigurationSource_ already provided
by Archaius and then we register the new configuration using the
_ConfigurationManager_. After doing this we can get any property from the DB
exactly the same way we do it for properties files (i.e., using the
_DynamicPropertyFactory_).

We can now add a couple of tests to make sure that we are actually reading
properties from the DB and that we can update their values and see the changes
reflected in our dynamic configuration.

{% highlight java %}
@Test
public void shouldRetrievePropertyFromDB() {
  String property = appConfig.getStringProperty("db.property", "default message");

  assertThat(property, is("this is a db property"));
}

@Test
public void shouldReadTheNewValueAfterTheSpecifiedDelay() throws InterruptedException {
  template.update("update properties set property_value = 'changed value' where property_key = 'db.property'");
  String property = appConfig.getStringProperty("db.property", "default message");

  //We updated the value on the DB but Archaius polls for changes every 1000 milliseconds so it still sees the old value
  assertThat(property, is("this is a db property"));

  Thread.sleep(1500);

  property = appConfig.getStringProperty("db.property", "default message");
  assertThat(property, is("changed value"));
}
{% endhighlight %}

To conclude this post, another really cool feature offered by Archaius is the
possibility to register our configurations as
[MBeans](http://docs.oracle.com/javase/tutorial/jmx/mbeans/) via JMX. We can do
this by default setting the system property
_archaius.dynamicPropertyFactory.registerConfigWithJMX=true_ or programmatically
with _ConfigJMXManager.registerConfigMbean(config);_.

After doing this we can connect via JConsole and not only get the value of all
properties but also update them and see their new value reflected in Archaius.
This would allow us, for instance, to change the values of properties defined
statically in property files during runtime without the need for a server push.
We can modify our _ApplicationConfig_ class a little bit to add a main method
that will keep running printing the values of different properties, allowing us
to play around in JConsole.

{% highlight java %}
public class ApplicationConfig extends Thread {

  private final DataSource dataSource;

  @Autowired
    public ApplicationConfig(DataSource dataSource) {
      this.dataSource = dataSource;
      cascadeDefaultConfiguration();
      DynamicConfiguration jdbcSource = installJdbcSource();
      registerMBean(jdbcSource);
    }

  public String getStringProperty(String key, String defaultValue) {
    final DynamicStringProperty property = DynamicPropertyFactory.getInstance().getStringProperty(key,
        defaultValue);
    return property.get();
  }

  @Override
    public void run() {
      while (true) {
        try {
          sleep(100);
        } catch (InterruptedException e) {
          throw new RuntimeException(e);
        }

      }
    }

  private void registerMBean(DynamicConfiguration jdbcSource) {
    setDaemon(false);
    ConfigJMXManager.registerConfigMbean(jdbcSource);
  }

  public static void main(String[] args) {
    ApplicationContext applicationContext = new ClassPathXmlApplicationContext("archaiusContext.xml");
    ApplicationConfig applicationConfig = (ApplicationConfig) applicationContext.getBean("applicationConfig");

    applicationConfig.start();

    while (true) {
      try {
        System.out.println(applicationConfig.getStringProperty("hello.world.message", "default message"));
        System.out.println(applicationConfig.getStringProperty("cascade.property", "default message"));
        System.out.println(applicationConfig.getStringProperty("db.property", "default message"));
        sleep(3000);
      } catch (InterruptedException e) {
        throw new RuntimeException(e);
      }

    }
  }
}
{% endhighlight %}

And that's it for now. You can find all the code showed in this post at
https://github.com/jlordiales/archaius-example.

There's a lot more you can do with Archaius, like Callbacks everytime a property
changes, integration with [Zookeeper](http://zookeeper.apache.org/) and other
services. Check out the Archaius project and examples at their Github repo.
