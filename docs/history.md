## Small Dose of Philosophy
The people behind RQ have been working on Unix since the late 1980's. The focus
of RQ has been on reliability and the ease of understanding. The author prefers
systems that allow him to sleep soundly at night, and he thinks the design of
RQ allows him to achieve this. There is a lot to talk about here and why the
existing systems didn't solve the problem. If you are interested in that, read
the full philosphy section below.

Also, if you were on the internet in the 80s or 90s, you will see that this
system bears some resemblance to the UUCP system deployed back then. It was
definitely an inspiration for the design of this system.

## Large Dost of Philosophy

When working in distributed systems, you will eventually learn that the system is never 100% available. Yet,
most developers tend to program as if the system is always available.

Here is a great list of many of the types of failures that can occur:

http://aphyr.com/posts/288-the-network-is-reliable

Why do developers work this way? Most of the time, it is just time pressure to get something out the door. Other
times it is just a lack of understanding. Modern systems tend to have many layers and components. It would
be difficult to know them all.

Currently, it takes effort to mitigate these issues. There is some progress, but there isn't a single framework
that handles all of the issues defined above. All to often the solution is to silently ignore the errors.

Another important point to make is that knowledge transfer has not been good here. For example, many people
use Unix now without really knowing the fundamental concepts of the system. There are common idioms and
best practices. For example, when DHH proclaimed to
'cheat' by running ImageMagick in a separate process, this was a huge revelation to the Rails community. Yet,
this was one of the core tenets of Unix from its earliest days.

RQ is  designed to mitigate a large portion of the above. It is a framework for communication and processing
in a distributed system.

Here are some of the tenets of its operation:

* It provides a system where reliable handoff is provided.
* RQ doesn't allow a system to fail silently.
* The system doesn't require 100% availability for messaging to work.
* No single message can take the system down.
* It is language agnostic. Let the right tool for the job be used vs. a specific language or framework.
* It encourages idempotent queue behaviour.
* It uses Unix properly, and allows those who know Unix transparent access to the RQ system.

## History

During my career, it was common to see people rediscover the need for queueing systems over and over again.
Typically, there is a spectrum for queueing systems. On one end there is the high-speed, message bus
type system that runs a stock exchange. On the other end of the spectrum, you could consider email.

Typically, properly implemented queueing systems required serious infrastructure.
In fact, because of performance issues, most of these do not persist to disk.
The high-end ones have complex APIs and usually are designed for small message sizes.

Then there are the home grown systems which are usually implemented on Redis or memcache

Then there are the basic ones that run off of a SQL database.

All of these require external systems to handle the state.

I decided to make several bets:

1. There might be a quadrant for a general purpose, lightweight queue manager that existed per machine
2. The system should be able to move huge files
3. Ruby was a *good enough* systems language
4. The Ruby VM would be much better within a few years
5. The Unix filesystem would be fast enough

However, only a few of these panned out.

At the time, it was the goto language of choice at BrightRoll.
Other languages were considered that were significantly different than Ruby, but didn't seem
appropriate.

* Java - memory footprint is way too high. POSIX support is poor (process control, signals, etc.).
* Python - practically equivalent to Ruby, and most were rubyists
* NodeJS - was not nearly baked, very promissing. They are the only system to get Unix since C.
* Go / Golang - may not have existed. If it did, it surely was not baked.
* Erlang - interesting language under consideration. I really liked the concurrency model, but the
           environment was way too out of our experience zone.
* Lisp, ML, Haskell,  etc. - A lot like Erlang, except without a good concurrency model.
* C - would take way too much time
* C++ - even more time than C

My goals were:

* Get something running
* Should be easy to install (think PHP apps... through the browser)
* Should be easy to update (think Wordpress)
* No dependencies with Ruby (it should just work)

Of all of those, only the first occurred.

Again, Ruby was a good choice.
It was pretty easy to get certain features implemented and into production. The three biggest
drawbacks to ruby were:

1. Poor IO support for async IO
2. GEMS. GEM conflicts are a huge problem.
3. Overall speed of the language

- When it was initially developed on Mac OS X, it was immediately discovered that the directories would have
  to be named (.noindex) as the activity of RQ caused a tremendous load on Spotlight.
  Now I do my development of RQ via ssh to a VirtualBOX Ubuntu instance.
- We ran into the GLIBC issue where DNS would no longer round-robin.

Yet, even with these drawbacks, the overall architecture proved to work pretty well. The forking model hides
most of the issues that someone would run into with.

## Future

* Address weaknesses
  * Performance - Light message throughput is poor due to Unix filesystem performance
  * Distributed Worker Model - balanced systems
  * Stronger API for Queue Scripts based on JSON
  * Better integration with graphite

* Rewrite the components of the system in C
  * This will keep the memory requirements lower than any other system
  * This avoids all of the negatives that Ruby brings when doing systems work
  * Much better system level control and accounting is possible
* Distributed Worker Model with MongoDB
  * Without changing the Queue Script API, have workers check in
    with a cluster of RQ managers
  * These managers use MongoDB for persistent queue state
  * MongoDB provides a highly reliable, single-data center store
* Have another persistent store

