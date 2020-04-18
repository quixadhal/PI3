#!/usr/bin/perl -w

package PI3::Log;

=head1 NAME

PI3::Log - Logging module.

=head1 SYNOPSIS

use PI3::Log;

=head1 DESCRIPTION

This module initializes the logging system used by the server.

=cut

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

use Scalar::Util qw(weaken refaddr);
use Time::HiRes qw(time sleep alarm);
use Log::Log4perl;
use Log::Log4perl::Layout;
use Log::Log4perl::Level;

our $VERSION = '0.01';

BEGIN { @INC = ( ".", @INC ); }

my $class_data;     # initialized later
my $log_internal;   # for our own internal use

use Exporter qw(import);

#our @EXPORT_OK = qw($log_main);
our @EXPORT_OK = qw();
our @EXPORT = qw();
our %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);

=head1 METHODS

=over 4

=item new()

Constructor.  The first argument after the implied object/class ref is the
category name of the logging object being created.  It defaults to "main".

The second argument is an options hash (reference), which may contain
an alternative logging format, via the "layout" key, or a flag to indicate
that references should be weakened, via the "weakref" key.

If weak references are used, the caller must retain the logging object,
not just the actual logger itself.  If they are not (the default), the
DESTROY function is not reliable, but the caller can simply use the logger
directly.

=cut

sub new {
    my $this    = shift;
    my $id      = shift || "main"; #sprintf "%08x", int(rand(2**32-1));
    my $opt     = shift || {};

    #my $layout  = shift || $class_data->{default_layout};
    #my @args    = @_;

    return $class_data->{instances}{$id} if exists $class_data->{instances}{$id};

    my $class = ref($this) || $this;
    my %data = ();
    my $self = bless \%data, $class;

    $self->{id} = $id;
    $self->{layout} = exists $opt->{layout} ? $opt->{layout}
                                            : $class_data->{default_layout};

    $self->{weakref} = exists $opt->{weakref} ? $opt->{weakref} : undef;
    $self->{layout_object} = 
        Log::Log4perl::Layout::PatternLayout->new($self->{layout});
    $self->{logger} = Log::Log4perl->get_logger($id);
    $self->{appender} = [];

    my $new_appender = Log::Log4perl::Appender->new(
        "Log::Log4perl::Appender::Screen",
        name      => $self->{id} . "_screenlog",
        stderr    => 0);
    $new_appender->layout($self->{layout_object});
    $self->{logger}->add_appender($new_appender);
    push @{ $self->{appender} }, $new_appender;

    $self->{logger}->level($DEBUG);
    $self->{created} = time();
    $self->{logger}->debug("New Logger " . $self->{id} . " created.");
    $class_data->{instances}{$id} = $self;
    # We weaken the reference here so that the logger will go away
    # when the caller's variable goes out of scope.  This has the
    # side effect of forcing them to keep the variable around.
    #
    weaken $class_data->{instances}{$id} if defined $self->{weakref};
    #
    # NOT doing this means the caller no longer needs to keep a reference
    # around to prevent the logger from going poof... but it also means we
    # can't do anything during shutdown, since DESTROY() is not reliable.

    return $self;
}

=item DESTROY()

Destructor.  Not reliable.

=cut

sub DESTROY {
    my $self = shift;

    return if !defined $self->{id};

    if( !defined $class_data->{instances}{$self->{id}} ) {
        print STDERR "DESTROY called for ".$self->{id}."\n";
        return;
    }
    my $logger = Log::Log4perl->get_logger($self->{id});
    return if !defined $logger;

    $logger->debug("Logger " . $self->{id} . " being destroyed.");
    foreach (@{ $self->{appender} }) {
        #Log::Log4perl->eradicate_appender($_->{name});
        $logger->remove_appender($_->{name});
    }
    # Might need to do database shutdown stuff here
    $self = undef;
}

=item count()

Returns how many instances of the logger class exist.

=cut

sub count {
    return scalar keys %{ $class_data->{instances} };
}

=item instance()

Returns an instance of the PI3::Log object, given the logger object's reference.

=cut

sub instance {
    my $self = shift;
    my $id = shift;

    print Dumper({ self => $self, ref => ref $self, id => $id });

    # If we called this as a class method or plain function, without an id.
    return undef if !defined $id and !defined ref $self;

    # Called as an object or class method, but with an id provided.
    # my $foo = $log_object->instance($id);
    # my $bar = PI3::Log->instance($id);
    return $class_data->{instances}{$id} if defined $id;

    # We were called as a class method, but without an id.
    return undef if !defined $self;

    # Otherwise, we want the logger object that's bound to
    # our supervisor object... $self.
    foreach (keys %{ $class_data->{instances} }) {
        return $class_data->{instances}{$_}
            if refaddr($class_data->{instances}{$_}->{logger}) == refaddr($self);
    }

    return undef;
}

=back

=head1 BEGIN

=over 4

=item BEGIN-setup

This is some initialization code that has to happen BEFORE any instance of
the class can be used.  I split it off into a BEGIN block because I had to
use BEGIN to override several other built-in logging systems as well.

=cut

BEGIN {
    $class_data = {} if ref $class_data ne 'HASH';
    $class_data->{default_layout} = "%d{yyyy-MM-dd HH:mm:ss.SSS} "
                                  . "%-6c %-6p %16C %05L| %m{indent,chomp}%n"
                                  if !exists $class_data->{default_layout};
    if (!exists $class_data->{instances}) {
        $class_data->{instances} = {};
        # DEBUG, INFO, WARN, ERROR and FATAL
        #             ^     ^
        #             |     AUTH
        #             BOOT
        Log::Log4perl::Logger::create_custom_level("AUTH", "ERROR");
        Log::Log4perl::Logger::create_custom_level("BOOT", "WARN");
    }

    $log_internal = PI3::Log->new()->{logger}
        if !defined $log_internal;
}

=item BEGIN-override

This is how we're attempting to override the use of the built-in warn/die
and the Carp module, which are often used by OTHER modules before our own
logging system is configured.

If this module is used BEFORE any others, it should forcibly override
the code refs of Carp and friends and point them at our own system.

=cut

BEGIN {
    # Soooo, IPC::Shareable has lots of calls to carp and croak in it.
    # Normally, this is fine, however, we're trying to use Try::Tiny
    # to be cleaner than the old eval kludge for handling timeouts.
    # It does NOT play nice with the Carp module, only with warn/die.
    #
    # Thus, we are importing Carp here so we can override it BEFORE
    # IPC::Shareable gets to it, and thus it will use OUR versions
    # which direct things to our logging system.
    #
    # We didn't catch warn/die before, but since we have to go this far,
    # we might as well grab them too...
    require Carp;

    my $o_carp = \&Carp::carp;
    my $o_cluck = \&Carp::cluck;
    my $o_warn = \&CORE::GLOBAL::warn;
    my $o_croak = \&Carp::croak;
    my $o_confess = \&Carp::confess;
    my $o_die = \&CORE::GLOBAL::die;

    no warnings 'redefine';
    *Carp::carp = sub { $log_internal->warn(@_); };
    *Carp::cluck = sub { $log_internal->warn(@_); };
    *CORE::GLOBAL::warn = sub { $log_internal->warn(@_); };
    *Carp::croak = sub {
        $log_internal->fatal(@_);
        $log_internal->boot("System Halted.");
        exit 1;
        if( $^S ) {
            # If we're inside an eval, call the real die...
            CORE::die(@_);
        } else {
            $log_internal->boot("System Halted.");
            exit 1;
        }
    };
    *Carp::confess = sub {
        #my @call_data = caller();
        $log_internal->fatal(@_);
        $log_internal->boot("System Halted.");
        exit 1;
        if( $^S ) {
            # If we're inside an eval, call the real die...
            CORE::die(@_);
        } else {
            $log_internal->boot("System Halted.");
            exit 1;
        }
    };
    *CORE::GLOBAL::die = sub {
        $log_internal->fatal(@_);
        if( $^S ) {
            # If we're inside an eval, call the real die...
            CORE::die(@_);
        } else {
            $log_internal->boot("System Halted.");
            exit 1;
        }
    }
};

=back

=cut

1;
