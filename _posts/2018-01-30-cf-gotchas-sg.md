---
author: jlordiales
comments: true
share: true
date: 2018-01-30
layout: post
title: AWS CloudFormation gotchas - Security groups
categories:
- aws
tags:
- aws
- CloudFormation
---
If you are working with AWS and keeping your infrastructure as code (Hint: you
really should) then you've probably come across
[CloudFormation](https://aws.amazon.com/cloudformation/) or
[Terraform](https://www.terraform.io/) at some point.
If you are using the former option, then there's a small gotcha related to
security groups that might cause some unexpected behaviour if you are not aware
of it (for me it caused a production incident...).

# The use case
Imagine you have the following small template defining a security group that
allows incoming HTTPS traffic from a specific IP range and a load balancer that
will use that security group:

{% highlight yaml %}
AWSTemplateFormatVersion: '2010-09-09'
Description: My awesome template
Outputs:
  SecurityGroup:
    Value: !Ref SecurityGroup
Resources:
  SecurityGroup:
    Properties:
      GroupDescription: Security group used for the test
      SecurityGroupEgress:
        - CidrIp: 0.0.0.0/0
          IpProtocol: '-1'
      SecurityGroupIngress:
        - CidrIp: 10.2.2.0/24
          FromPort: '443'
          IpProtocol: tcp
          ToPort: '443'
      VpcId: <your_vpc_id>
    Type: 'AWS::EC2::SecurityGroup'

  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Scheme: internal
      Subnets: <subnets>
      SecurityGroups:
        - !Ref SecurityGroup
{% endhighlight %}

You create your CloudFormation stack and everything works as expected. Both
resources are created and the security group is associated with the load
balancer to make sure that only HTTPS traffic from that specific IP range is
accepted. After a short test, you start routing all traffic to your new shiny
load balancer.

# The problem

A few weeks later you come back to this simple template to add a new resource
and you try to remember what that specific IP range meant. Was it the subnet of
one of your clients? If so, which one? Who do I need to notify in case the port
or range needs to change? 
After some searching through your archived emails you finally find where that
range came from. Since you are a good engineer and you don't want anyone else to
waste 20 minutes of their life trying to understand why that rule is the way it
is, you decide "I should probably add a description to my rule now that AWS [supports
it](https://aws.amazon.com/blogs/aws/new-descriptions-for-security-group-rules/)".

So you go ahead and add that:

{% highlight yaml %}
SecurityGroup:
  Properties:
    GroupDescription: Security group used for the test
    SecurityGroupEgress:
      - CidrIp: 0.0.0.0/0
        IpProtocol: '-1'
    SecurityGroupIngress:
      - CidrIp: 10.2.2.0/24
        FromPort: '443'
        IpProtocol: tcp
        ToPort: '443'
        Description: "This IP range belongs to the subnet of Team X"
    VpcId: <your_vpc_id>
  Type: 'AWS::EC2::SecurityGroup'
{% endhighlight %}

Quite happy with yourself you do your usual `aws cloud-formation update-stack`
and you switch to something else.
Immediately after firing the stack update you start getting alarms (because of
course you monitor your infrastructure) telling you that no traffic is getting
through your load balancer. After a few minutes the alarms go away and you start
getting traffic again but it was enough for your clients to notice that all
their requests were timing out.
What the hell happened!?

You know the problem is related to your change in the security group but how can
adding a description possibly cause that? You quickly go to your CloudFormation
console and look at the events of the stack, nothing wrong there.
You go to the CloudFormation
[documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-security-group.html#cfn-ec2-securitygroup-securitygroupingress)
to see if you missed something, but nowhere does it say anything special about
adding a description to one of the rules. In fact, it explicitly says that
changes to the `SecurityGroupIngress` require "No interruption". 

You start to think that maybe it had nothing to do with your update and that it
was an extremely unlucky coincidence. But on a last attempt to see if you find
anything weird you log in to your AWS Console and find your security group there.
It looks correct but just for fun you click the "Edit" button. Of course you
would never update stuff like that manually (infra as code remember?) but you
are desperate at this point. And in there (only in there) you see this:

![sg](/images/aws-sg/sg.png)

**NOTE: Any edits made on existing rules will result in the edited rule being
deleted and a new rule created with the new details. This will cause traffic
that depends on that rule to be dropped for a very brief period of time until
the new rule can be created.**

What? How? Why? You would understand if that was the case when changing the port
or the IP range, but adding a description to it? Really? 
To add salt to the wound, you then find out that AWS has an operation on their
API to do exactly this, it's aptly called
[UpdateSecurityGroupRuleDescriptionsIngress](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_UpdateSecurityGroupRuleDescriptionsIngress.html).
So this feels like pure laziness. Instead of checking what actually changed in
the definition of the rule and call the proper API in case that was only the
description, CloudFormation decides it's easier to fully recreate the rule
if anything changes (with the corresponding traffic drop).

You decide to test this for yourself by creating a new test template with only
the security group definition, initially without description:

{% highlight yaml %}
AWSTemplateFormatVersion: '2010-09-09'
Description: Security group description update test
Outputs:
  TestSecurityGroup:
    Value: !Ref TestSecurityGroup
Resources:
  TestSecurityGroup:
    Properties:
      GroupDescription: Security group used for the test
      SecurityGroupEgress:
        - CidrIp: 0.0.0.0/0
          IpProtocol: '-1'
      SecurityGroupIngress:
        - CidrIp: 10.2.2.0/24
          FromPort: '443'
          IpProtocol: tcp
          ToPort: '443'
      VpcId: <your_vpc_id>
    Type: 'AWS::EC2::SecurityGroup'
{% endhighlight %}

After the stack is created you check your security group from the AWS cli:
{% highlight raw %}
$> aws ec2 describe-security-groups --group-ids <your_sg_id> | jq '.SecurityGroups[0].IpPermissions'

[
  {
    "PrefixListIds": [],
    "FromPort": 443,
    "IpRanges": [
      {
        "CidrIp": "10.2.2.0/24"
      }
    ],
    "ToPort": 443,
    "IpProtocol": "tcp",
    "UserIdGroupPairs": [],
    "Ipv6Ranges": []
  }
]
{% endhighlight %}

Now, as you did before, you add a nice description to your ingress rule and do
an `update-stack`. And here's where it gets really interesting. As soon as you
trigger the stack update you run your `describe-security-groups` command again
and you see this as the output:

{% highlight raw %}
$> aws ec2 describe-security-groups --group-ids <your_sg_id> | jq '.SecurityGroups[0].IpPermissions'

[]
{% endhighlight %}
That's right, no ingress rules for your security group. Which of course means no
traffic can get through.
You try again after you stack is finished updating and you see your rule there
again, this time with the description.

Like I said before, given that the functionality to update only a rule
description is present on their API, this feels like a pretty serious bug in
CloudFormation to me.
But even if it wasn't, I would definitely expect to see some sort of
warning on CloudFormation docs (not in some obscure part of the AWS UI).

# The solution

So, given this limitation in CloudFormation, how do you work around it? How do
you add descriptions to your existing rules?

The most straightforward approach is simply to have a planned maintenance window
for your service (or services) and just do the update. As far as I could see in
my tests it usually takes less than a minute for the new rule to be created and
put in place.

If that's not acceptable for your use case then it gets a bit more tricky. Here
are some of the things I tried and didn't work.

Using the AWS cli, you can update the description using the API I mentioned
previously
(https://docs.aws.amazon.com/cli/latest/reference/ec2/update-security-group-rule-descriptions-ingress.html).
That works and doesn't incur in any downtime but now your CloudFormation
template doesn't really represent the current state of your infrastructure. You
might think that adding the same description as you used in the cli to your
template would work but it doesn't.
Since the latest version of the template that CloudFormation knows about doesn't
contain any description, the next update will recreate the rule just as it did
the first time.

A second potential approach was to just add a second ingress rule to the
template with the same IP range and port that includes our awesome description.
By doing this I was expecting CloudFormation to leave the old rule untouched
while creating a new one and, on a second update after that, to remove the first
rule (the one without description). Unfortunately this doesn't work because
CloudFormation seems to use the (IP, port) pair as a way to identify each rule. That
means 2 things for our example: the first update will not create a new rule
and, even worse, the second update to remove the old rule will actually leave
your security group without any ingress rules.

The only approach that has worked for me so far is a slight variation of the
previous one:
- Add a new rule that is more permissive than the original one so that it allows
  traffic from the same IP range (0.0.0.0/0 for instance if you are not worried
  about opening access to everyone for a few minutes) and update your stack
- At this point you should have 2 ingress rules in your security group. Now you
  can add your description to the original rule and do an update. This will
  recreate the rule but that should be fine because we have our second rule
  still there that should allow traffic from the same source
- Finally, delete the second rule. Now you should be back to having only your
  original IP range with the description included

Having to do 3 stack updates to add a simple description to an ingress rule is
less than ideal but I haven't found a better way to do it without incurring in
some downtime for your clients.

# What about Terraform?
If you are using Terraform then things should work as expected. Terraform will
do the update without incurring in any packet loss.
From the output of `terraform plan` you can actually see that it is creating a
new rule with your description and deleting the old one, but it does so in a way
that you always have at least 1 of them present.
Kudos to HashiCorp for that!
