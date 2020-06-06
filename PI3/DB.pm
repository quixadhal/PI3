#!/usr/bin/perl -w

package PI3::DB;

=head1 NAME

PI3::DB - Mostly SQL utilty functions

=head1 DESCRIPTION

This is a module with a few SQL utility functions to make it simpler
to push data around.

=head1 DEPENDENCIES

=over 4

=item SQL Schema

To use DBI logging, you must first set up a database and a table to
hold logging data.  Here is the table create statement I used for this
simple test.  You may want to do things differently, or add indexes
and other things for real.

    CREATE TABLE logfile (
        local       TIMESTAMP WITH TIME ZONE    DEFAULT now(),
        pid         INTEGER,
        category    TEXT,
        priority    TEXT,
        package     TEXT,
        lineno      INTEGER,
        msg         TEXT
    );

We also need to have a table to store i3 server information, since our
system is designed to allow multiple servers to run against the same
database to provide a local cluster.

    CREATE TABLE servers (
        name        TEXT PRIMARY KEY NOT NULL,
        port        INTEGER NOT NULL,
        address     TEXT,
        pid         INTEGER
    );

=cut

=back

=cut

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
use Try::Tiny;
use DBI;
use Log::Log4perl;

use Exporter qw(import);
our @EXPORT_OK = (); #qw(wizlock debug logfile pidfile libdir specials gameport);
our @EXPORT = ();
our %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);

our $log_sql = Log::Log4perl->get_logger('SQL') or die "Cannot get logging object!";

=head1 FUNCTIONS

=over 4

=item get_ip_address()

This uses an exteral service to find out our public IPv4 address, so we
can register it in the database.

=cut

sub get_ip_address {
    my %services = (
        amazon  => 'https://checkip.amazonaws.com',
        mud     => 'https://www.themud.org/whatsmyip.php',
    );

    my $address_service = 'amazon';
    local $| = 1;
    open(my $fp, '-|', 'curl', '-s', '-4', $services{$address_service})
        or $log_sql->logdie("Cannot get external IP address: $!");
    my ($address) = (<$fp>);
    chomp $address;
    $log_sql->info(sprintf "service '%s' says we are '%s'",
        $address_service, $address);
    return $address;
}

=back

=cut

=head1 METHODS

=over 4

=item new()

Constructor.  When we create a new instance, we connect to
the database and register ourselves as an active router.

=cut

sub new {
    my $class       = shift;
    my $cfg         = shift or $log_sql->logdie("Config object is required!");

    my $self = {
        _db     => undef,
        _config => $cfg,
        _log    => $log_sql,
        router  => {
            name    => undef,
            port    => undef,
            address => undef,
            pid     => undef,
            online  => undef,
        },
    };

    $cfg->router_address(get_ip_address());

    $self->{_db} = DBI->connect(
        $cfg->db_dsn(), $cfg->db_username(), $cfg->db_password(), 
        { AutoCommit => 1, RaiseError => 1, PrintError => 0, }
    );

    bless $self, $class;
    $self->register();
    return $self;
}

=item DESTROY()

Destructor.  Attempt to do any cleanup work when this object is
destroyed.  You SHOULD do these things yourself, in case garbage
collection removes objects out of order...

=cut

sub DESTROY {
    my $self = shift;

    $self->unregister();
}

=item db()

This just returns the active database connection object.

=cut

sub db {
    my ($self, $setting) = @_;

    return $self->{_db};
}

=item register()

This registers the current router in the database, so other routers
that use the same database can find it.

=cut

sub register {
    my $self = shift;
    my $db = $self->{_db};
    my $cfg = $self->{_config};

    $self->{router} = {
        name    => $cfg->router_name(),
        port    => $cfg->router_port(),
        address => $cfg->router_address(),
        pid     => $cfg->router_pid(),
        online  => undef,
    };

    $db->begin_work();
    my $insert_sql = $db->prepare( qq!
        INSERT INTO servers ( name, port, address, pid )
        VALUES (?,?,?,?)
        ON CONFLICT (name)
        DO UPDATE
        SET address = ?, pid = ?
    !);
    my $rv = $insert_sql->execute(
        $self->{router}{name},
        $self->{router}{port},
        $self->{router}{address},
        $self->{router}{pid},
        $self->{router}{address},
        $self->{router}{pid}
    );
    if($rv) {
        $db->commit;
        $self->{router}{online} = 1;
    } else {
        $log_sql->error(sprintf "%s", $DBI::errstr);
        #print STDERR $DBI::errstr."\n";
        $db->rollback;
    }
}

=item unregister()

This removes the PID from the SQL entry, so other servers know this
router has gone offline.

=cut

sub unregister {
    my $self = shift;
    my $db = $self->{_db};

    $db->begin_work();
    my $insert_sql = $db->prepare( qq!
        UPDATE servers
        SET pid = NULL
        WHERE name = ? AND port = ?
    !);
    my $rv = $insert_sql->execute(
        $self->{router}{name}, $self->{router}{port}
    );
    if($rv) {
        $db->commit;
        $self->{router}{online} = undef;
    } else {
        $log_sql->error(sprintf "%s", $DBI::errstr);
        #print STDERR $DBI::errstr."\n";
        $db->rollback;
    }
}

=back

=cut

1;

