#!/usr/bin/perl -w

package PI3::Config;

=head1 NAME

PI3::Options - A small module to get command-line arguments

=head1 SYNOPSIS

i3.pl [-h?D] [-d db-config] [-l log-config] [-r name] [-p port]

=head1 OPTIONS

=over 4

=item B<--help> or B<-h> or B<-?>

Some helpful help!

=item B<--pod>

This POD documentation

=item B<--debug> or B<-D>

Enable debugging spam

=item B<--db-config> or B<--db> or B<-d> filename

The config file used for the SQL database connection

=item B<--db-dsn> or B<--dsn> DSN

A DSN used to connect to the SQL database

=item B<--db-username> or B<--user> name

A username used to connect to the SQL database

=item B<--db-password> or B<--password> password

A password used to connect to the SQL database

=item B<--log-config> or B<--log> or B<-l> filename

The config file used for the Log4perl logging system

=item B<--router-name> or B<--router> or B<-r> name

The name of this router

=item B<--router-port> or B<--port> or B<-p> port-number

The port this router listens on

=back

=head1 DESCRIPTION

This is a module which handles collecting command line arguments and
parsing their values for use in controlling some aspects of this perl
mud.

=cut

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
use Pod::Usage;
use Pod::Find qw(pod_where);
use Getopt::Long qw(:config no_ignore_case bundling no_pass_through);
use File::Basename;
use Config::Tiny;

use Exporter qw(import);
our @EXPORT_OK = (); #qw(wizlock debug logfile pidfile libdir specials gameport);
our @EXPORT = ();
our %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);

=head1 FUNCTIONS

=over 4

=item usage()

This is a simple usage function to describe the command line
parameters and how to use them.  It is probably redundant
with the POD documentation, but we'll see which works better.

=cut

my $DEFAULT_DBCONF      = './db.conf';
my $DEFAULT_LOGCONF     = './log4perl.conf';
my ($DEFAULT_NAME)      = fileparse($main::PROGRAM_NAME, ('.pl')) || 'pi3';
my $DEFAULT_PORT        = 8080;

sub usage {
    my $long = shift;

    print STDERR <<~EOM;
InterMUD 3 server: $main::VERSION

usage:  $main::PROGRAM_NAME [-h?D] [-d db-config-file] [-l log-config-file]
                        [-r router-name] [-p router-port]

options:
    --help              This helpful help!
    --pod               Show POD documentation
    --debug             Enable debugging spam
    --db-config         The config file used for the SQL database connection
                        Default: $DEFAULT_DBCONF
    --db-dsn            A DSN used to connect to the SQL database
    --db-username       A username used to connect to the SQL database
    --db-password       A password used to connect to the SQL database
    --log-config        The config file used for the Log4perl logging system
                        Default: $DEFAULT_LOGCONF
    --router-name       The name of this router
                        Default: $DEFAULT_NAME
    --router-port       The port this router listens on
                        Default: $DEFAULT_PORT

EOM
    exit 1 if $long;
}

=item newest_modified_perl()

This walks from the current directory down to find the
perl modules with the newest modification time, to let us
compare our code's time against config file times, even
though we have it broken up into multiple files.

=cut

sub newest_modified_perl {
    my @dirs = ('.');
    my %times = ();

    while(my $d = shift @dirs) {
        opendir(DP, "$d") or die "Cannot open $d: $!";
        my @files = readdir(DP);
        closedir(DP);
        foreach (@files) {
            next if /^\.\.?$/;
            my $f = "$d/$_";
            next if -f $f && $f !~ /\.p[ml]$/;
            $times{$f} = -M $f if -f $f;
            push @dirs, $f if -d $f;
        }
    }
    my @k = sort { $times{$a} <=> $times{$b} } keys %times;
    return $times{$k[0]} if scalar @k > 0;
    return 0.0;
}

=back

=head1 METHODS

=over 4

=cut

=item new()

Constructor.  WHen we create a new instance, we parse the ARGV
arguments and fill the options hash, which all our accessor
functions refer to.

=cut

sub new {
    my $class = shift;
    my $self = {
        program                     => {
            name                        => $main::PROGRAM_NAME,
            mod                         => 0.0,
            pid                         => $$,
        },
        database                    => {
            config                      => $DEFAULT_DBCONF,
            mod                         => 0.0,
            dsn                         => undef,
            username                    => undef,
            password                    => undef,
        },
        log                         => {
            config                      => $DEFAULT_LOGCONF,
            mod                         => 0.0,
        },
        router                      => {
            name                        => $DEFAULT_NAME,
            port                        => $DEFAULT_PORT,
            pid                         => $$,
            address                     => '127.0.0.1',
        },
        debug                       => undef,
    };

    GetOptions(
        'pod'                       => sub { pod2usage(
                                           '-input'     => pod_where( {'-inc' => 1}, __PACKAGE__ ),
                                           '-verbose'   => 1,
                                           #'-noperldoc' => 1,
                                        ); exit;
                                    },
        'help|h|?'                  => sub { usage(1); },
        'debug|D'                   => \$self->{debug},
        "db-config|db|d=s"          => \$self->{database}{config},
        'db-dsn|dsn=s'              => \$self->{database}{dsn},
        'db-username|user=s'        => \$self->{database}{username},
        'db-password|password=s'    => \$self->{database}{password},
        "log-config|log|l=s"        => \$self->{log}{config},
        "router-name|router|r=s"    => \$self->{router}{name},
        "router-port|port|p=i"      => \$self->{router}{port},
    ) or usage(0);

    $self->{program}{mod}   = newest_modified_perl();
    $self->{database}{mod}  = -M $self->{database}{config} if -r $self->{database}{config};
    $self->{log}{mod}       = -M $self->{log}{config} if -r $self->{log}{config};

    if( -r $self->{database}{config} ) {
        my $db_config   = Config::Tiny->read($self->{database}{config});
        if( exists $db_config->{database} ) {
            foreach (qw(dsn username password)) {
                $self->{database}{$_} = $db_config->{database}{$_} if exists $db_config->{database}{$_};
            }
        }
    }
    die "No config file or DSN provided!"               if !defined $self->{database}{dsn};
    die "No config file or database username provided!" if !defined $self->{database}{username};
    die "No config file or database password provided!" if !defined $self->{database}{password};

    if( ! -r $self->{database}{config} or $self->{program}{mod} < $self->{database}{mod} ) {
        printf "Rewrote DB_CONFIG:  %s %9.6f\n", $self->{database}{config}, $self->{database}{mod};
        open(my $fp, ">", $self->{database}{config}) or die "Cannot create $self->{database}{config} $!";
        print $fp <<~EOM;
            [database]
                dsn = $self->{database}{dsn}
                username = $self->{database}{username}
                password = $self->{database}{password}
        EOM
        close $fp;
    }

    # This has to be in an actual physical file for log4perl to be happy with it.
    # Not MY choice, nor is embedding the DBI connection info directly...
    if( ! -r $self->{log}{config} or $self->{program}{mod} < $self->{log}{mod} ) {
        printf "Rewrote LOG_CONFIG: %s %9.6f\n", $self->{log}{config}, $self->{log}{mod};
        open(my $fp, ">", $self->{log}{config}) or die "Cannot create $self->{log}{config} $!";
        print $fp <<~EOM;
            log4perl.logger.MAIN = DEBUG, SE, DBI
            log4perl.logger.BOOT = DEBUG, SE, DBI
            log4perl.logger.AUTH = DEBUG, SE, DBI
            log4perl.logger.SQL  = DEBUG, SE, DBI

            log4perl.appender.SE = Log::Log4perl::Appender::Screen
            log4perl.appender.SE.stderr = 0
            log4perl.appender.SE.layout = Log::Log4perl::Layout::PatternLayout
            log4perl.appender.SE.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss.SSS} %8P %-6c %-6p %16C %05L| %m{indent,chomp}%n

            log4perl.appender.DBI = Log::Log4perl::Appender::DBI
            log4perl.appender.DBI.datasource = $self->{database}{dsn}
            log4perl.appender.DBI.username = $self->{database}{username}
            log4perl.appender.DBI.password = $self->{database}{password}
            log4perl.appender.DBI.sql = INSERT INTO logfile (pid, category, priority, package, lineno, msg) VALUES (?,?,?,?,?,?)
            log4perl.appender.DBI.params.1 = %P
            log4perl.appender.DBI.params.2 = %c
            log4perl.appender.DBI.params.3 = %p
            log4perl.appender.DBI.params.4 = %C
            log4perl.appender.DBI.params.5 = %L
            log4perl.appender.DBI.usePreparedStmt = 1
            log4perl.appender.DBI.layout = Log::Log4perl::Layout::NoopLayout
            log4perl.appender.DBI.warp_message = 0
        EOM
        close $fp;
    }

    bless $self, $class;
    return $self;
}

=item debug( [<integer>|false] )

Debug mode enables extra debugging output.  

Calling this without an argument returns the current
state, FALSE by default.  Giving it an argument will
set the debug level.

=cut

sub debug {
    my ($self, $setting) = @_;

    $self->{debug} = $setting if defined $setting;
    return $self->{debug};
}

=item log_config( [<string>] )

This is the config file for Log4perl.

Calling this without an argument returns the current
filename.  Giving it an argument will set the filename.

=cut

sub log_config {
    my ($self, $setting) = @_;

    $self->{log}{config} = $setting if defined $setting;
    return $self->{log}{config};
}

=item db_dsn( [<string>] )

The DSN used to connect to the SQL database.

=cut

sub db_dsn {
    my ($self, $setting) = @_;

    warn "Changing the SQL DSN on the fly is not supported.\n" if defined $setting;
    return $self->{database}{dsn};
}

=item db_username( [<string>] )

The username used to connect to the SQL database.

=cut

sub db_username {
    my ($self, $setting) = @_;

    warn "Changing the SQL username on the fly is not supported.\n" if defined $setting;
    return $self->{database}{username};
}

=item db_password( [<string>] )

The DSN used to connect to the SQL database.

=cut

sub db_password {
    my ($self, $setting) = @_;

    warn "Changing the SQL password on the fly is not supported.\n" if defined $setting;
    return $self->{database}{password};
}

=item router_name( [<string>] )

The name this router is known by, to I3.

This is normally set to be the name of the script with an asterisk
in front, but can be set manually from the command line, or changed
on the fly... but will probably break everything if done.

=cut

sub router_name {
    my ($self, $setting) = @_;

    warn "Changing the router name on the fly is not supported.\n" if defined $setting;
    return $self->{router}{name};
}

=item router_port( [<integer>] )

The port this router listens on for I3 connections.

=cut

sub router_port {
    my ($self, $setting) = @_;

    warn "Changing the router port on the fly is not supported.\n" if defined $setting;
    return $self->{router}{port};
}

=item router_address( [<string>] )

This is the IPv4 address on which the router will listen for connections.
It must be set after configuration, as it will be determined at runtime.

=cut

sub router_address {
    my ($self, $setting) = @_;

    $self->{router}{address} = $setting if defined $setting;
    warn "No valid address set!" if !defined $self->{router}{address};
    return $self->{router}{address};
}

=item router_pid( [<integer>] )

The process ID of the router, currently the same as the main program.

=cut

sub router_pid {
    my ($self, $setting) = @_;

    warn "Cannot change our process ID!" if defined $setting;
    return $self->{router}{pid};
}

=back

=cut

=head1 CONFIGURATION

=over 4

=item Hard Coded Variables

Yes, there are a couple.  $DEFAULT_DBCONF and $DEFAULT_LOGCONF, both above this
documentation block, control the filenames used for the various configuration
files, which will be auto-generated with examples if not present.

$DEFAULT_NAME should not be used, but it's provided in case you run the
program without an $ARGV[0], which might happen in a non-cli environment.

$DEFAULT_PORT is the default port the router will listen on, if nothing is
provided by configuration.

=cut

=item LOG4PERL_CONF

For reasons, Log4perl's DBI interface requires configuration to be on disk,
and so we create an example logging configuration for you to edit, or not.

=cut

=item DB_CONF

To simplify database connections, we expect you to provide the DSN
used to connect to your database of choice (I use PostgreSQL), and
the username and password needed for that connection.

Rather than hard-coding it, I decided to require you to make a
config file, which is in the classic Windows INI format with a
database section heading, and 3 entries under it, for the DSN,
username, and password.

If one isn't present, an example will be generated for you to edit.

=cut

=back

=cut

1;

