---
author: jlordiales
comments: true
date: 2012-12-28
layout: post
slug: when-git-ignores-your-gitignore
title: When git ignores your... .gitignore?
categories:
- Configuration Management
tags:
- .gitignore
- git
- version control system
---

I feel like I should start this post saying that I absolutely [love git](http://youtu.be/4XpnKHJAok8). If you've never heard of it, is a source control system like CVS or Subversion but, unlike those two, is a distributed version control system. I'm not going to get into much details about the history and capabilities of git but if you're curious about it you can go to [http://git-scm.com/book](http://git-scm.com/book) which is an amazing resource with everything from intro to advanced concepts.

I imagine that by now most professional software developers use some form of version control at their daily jobs but you shouldn't stop there. I use git for personal, one-man projects as well. While some people might think that this could be an [overkill](http://programmers.stackexchange.com/questions/69308/git-for-personal-one-man-projects-overkill), I completely disagree. There is nothing like the comfort in knowing that all the history of all your files is safe and ready to be brought back if you ever need them. We all make mistakes sometimes after all. With git this is as easy as writing 3 simple commands:

{% highlight bash %}
mkdir myNewProject
cd myNewProject
git init
{% endhighlight %}

That's it! Every file you create or modify on "myNewProject" will be now tracked by git.

A pretty useful feature that you get with every source control tool is the possibility to ignore certain files from the tool's tracking. Generally speaking, you don't want to get into your code repository any file that can be computed as a result of another file. In a typical Java Maven project this would be for example the "target" directory, or if you are using Eclipse the ".metadata", ".project" or ".settings" files. In git the easiest way to do this is to have a special file named ".gitignore" at the root of your project with all the [exclusion rules](http://www.kernel.org/pub/software/scm/git/docs/gitignore.html) you want to set. The syntax of this file is fairly straightforward. You can also have a ".gitignore" file for each subdirectory in your project, but this is less common.

A tricky thing with git and ignore rules is that if the file you want to ignore is already being tracked by git then adding it to ".gitignore" won't make git to automatically forget about the file. To illustrate this point, consider the following example. First we create a repository with two initial files and commit them:

{% highlight bash %}
mkdir gitExample
cd gitExample
touch file1 file2
git init
git add .
git commit -m "Initial commit"
{% endhighlight %}

Let's create now the .gitignore file to try to ignore "file2" and commit that:

{% highlight bash %}
echo file2 > .gitignore
git add .
git commit -m "Added gitignore for file2"
{% endhighlight %}

Now, let's modify "file2" and see what happens:

{% highlight bash %}
echo "Hello World" >> file2
git status
{% endhighlight %}

We get:
`
# On branch master
# Changes not staged for commit:
#   (use "git add ..." to update what will be committed)
#   (use "git checkout -- ..." to discard changes in working directory)
#
#	modified:   file2
#
no changes added to commit (use "git add" and/or "git commit -a")
`

Git is effectively still tracking file2 even though is already on our .gitignore. Like I said before, this happens because git was already tracking the file when we added it to our ignores. So let's see what happens when we add the ".gitignore" before adding the file to git:

{% highlight bash %}
mkdir gitExample
cd gitExample
touch file1 file2
git init
echo "file2" > .gitignore
git status
{% endhighlight %}

And now we get:
`
# On branch master
#
# Initial commit
#
# Untracked files:
#   (use "git add ..." to include in what will be committed)
#
#	.gitignore
#	file1
nothing added to commit but untracked files present (use "git add" to track)
`

Cool! No mention of file2 anywhere! But if, as our first example, we forgot to add the files to our .gitignore initially? How do we stop git from tracking them? A nice command we can use for this cases is `git rm --cached _file_`. In our first example:

{% highlight bash %}
git rm --cached file2
git commit -m "Removed file2"
{% endhighlight %}

If we now modify the file again and do a `git status` we get:

{% highlight bash %}
echo "Hello World Again" >> file2
git status
{% endhighlight %}

`
# On branch master
nothing to commit (working directory clean)
`

Exactly what we wanted!

Note that this little command will remove the file from git index but it won't do anything with your working copy. That means that you will still have the file on your directory but the file won't be a part of the git repository anymore. This also implies that the next time you do a push to a remote repository the file won't be pushed and, if it already existed on the remote repository, it will be deleted.

This is fine for a typical use case when you added a file that you never intended to have on the repository. But consider this other use case. In a lot of projects the developers upload into the remote central repository a set of config files for their IDE with default values for things like code formatting and style checking. But at the same time, when developers clone the repository they customize those config files to suit their personal preferences. However, those changes that apply to each particular developer should not be commited and pushed back to the repository. The problem with using `git rm --cached` here is that, while each developer will still have their own copy, the next time they push to the server they'll remove the default config from there. In cases like this, there is another pretty useful command that will do the trick: `git update-index --assume-unchanged <file>`. Let's see that with an example:

{% highlight bash %}
mkdir gitExample
cd gitExample
touch file1 file2
git init
git add .
git commit -m "Initial commit"
{% endhighlight %}

There we have our default "file2". Now let's use the `git update-index` command and make some changes to the file:

{% highlight bash %}
git update-index --assume-unchanged file2
echo "Hello World" >> file2
git status
{% endhighlight %}

The result:
`
# On branch master
nothing to commit (working directory clean)
`

Magic! Changes to our file are no longer seen by git and the original file is still on the repository to be cloned by other users with its default value.

Hope this helps someone! Cheers!

