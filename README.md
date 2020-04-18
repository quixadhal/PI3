# PI3
Standalone I3 router/client software

The goal of this little project is to write a server that can replace
the existing LPC-based Intermud-3 server software, removing the implicit
dependency on a MUD driver, and allowing it to be more easily extended
and maintained.  I've chosen perl as a langauge to do this, due to my
familiarity with it, the ease of which it can be obtained for a variety
of platforms, and the simplicity of dealing with string data in such a
dynamic language.

What I believe is needed is a framework that allows multiple distinct
services to run in parallel, spawning processes as needed to handle
various tasks.

First, I'd like to use a standardized logging system, such as Log4Perl,
that will let this entire project log things to a given set of destinations,
which might be flat files or a database system.  Each service would be
a category, with various severity levels to make finding errors or
anomolies easier.

Second, I'd like a standard DBI interface to store and retrieve both
configuration data and data created by, or consumed by, the various
services.  This will need to be asynchronous to some degree, to prevent
any long running queries from blocking other database access.

Third, a web interface that can act as both an administration interface,
and as a user interface to access statistics and data created by other
services.

Finally, several TCP socket servers will be implemented to service I3
clients, to interact with the IRN cluster, and perhaps to provide
data feeds for other purposes.  We might also choose to support IMC2,
IRC, Twitter, or Discord as future targets.

In the case of the I3 and IRN sockets, we'll need a new TCP subclass.

"MUD mode sockets":  a subclass of IO::Net::TCP that implements the basic
layer needed for the "MUD mode" protocol, which is simply the escaping of
data needed to ensure it can be safely parsed by LPC as a "saved object"
stream, the prepending of a 32-bit network-byte-order length prefix, and the
appending of a trailing NUL byte.

    $socket->send() should accept any valid perl hash, array, or scalar that
    can be encoded as a valid LPC data structure.  References are not allowed,
    and objects must be transformed to an unblessed hash by a higher layer.
    Failures might result in an error return, or an exception being raised.
    

    $socket->recv() should read a valid "MUD mode" stream chunk, from the
    32-byte length value to the trailing NUL byte, unescape it, and then
    parse it and return a hash, array, or scalar.  Creating a blessed object
    would be the responsiblity of the consumer of this data.

"I3 packets":  an object class that represents an I3 packet type, and which
will have methods to convert its data to an unblessed hash to be fed to a
"MUD mode" socket object, and methods to covert an unblessed hash into an
object via the constructor.  The base class will not be a valid final object,
but will be used to create subclasses for each supported packet type in the
I3 or IRN protocols.

I believe the POE framework is the logical choice to handle all these things,
as it is one of the few frameworks designed to run various distinct servers
in parallel, as a group of services.

For DBI, POE::Component::EasyDBI looks like a reasonable candidate.  It appears
to provide non-blocking callback-style queries using the POE style events.

Potential basic flow:

server process will use IPC::Shareable to have a shared message queue
and Net::Server::PreFork to handle forking servers for each protocol
used (I3, WEB, CHAT)

server process sets up each Net::Server and a shared hash for each service.

When a client is forked, it will register itself in the shared hash and
then wait for I/O.  When it gets a message, it will handle it and push any
results into the shared hash if the server/other-clients need to be
involved.  It will also be woken up (via signal?) when any outgoing
data is placed it its hash by the server, so it can respond to it.

Additionally, we'll be using a database for some things, so we need
a connection pool that all children can use.  This would be more efficient
than having each child open their own connection, especially if they are
short lived.

So, the shared hash should have a few fixed things in it.

{
    service     =>  type of service this data is, "chat", etc...
    config      =>  configuration data set by the parent for the
                    children to access.  if changed, they should
                    be signalled to re-read it.
                    {
                        version =>  version serial number, so the clients
                                    can quickly see if they need to parse
                                    the rest of the hash or not.
                        ...
                    }
    clients     =>  hash of clients registered, can be empty
                    client count would be (scalar keys $t->{clients})
                    {
                        pid     =>  process ID of child
                                    this is also the hash key and
                                    will be used by the parent to
                                    send signals, or force termination.
                        input   =>  hash of message packets processed
                                    by the child and ready for the
                                    server to handle.
                        output  =>  hash of message packets from the
                                    server for the child to handle.
                        ...
                    }
}

