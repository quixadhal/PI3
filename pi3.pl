#!/usr/bin/perl -w

package main;

our $VERSION        = "0.06";

=head1 NAME

pi3.pl - An Intermud-3 router, implemented in perl.

=cut

=head1 SYNOPSYS

For usage information, use ./pi3.pl --help.

=cut

=head1 DESCRIPTION

I first started playing text MUDs when I was a student
at Western Michigan University, back in 1992.  At that time
they were a popular type of game, since most college students
used text terminals in the campus labs, and even if you had
your own computer, you probably still used a dialup modem,
making text one of the few mediums you could enjoy fast paced,
real-time interactions with other humans.

It didn't take long for the people writing MUDs to want to
start linking them together, and the "intermud network" was
born.  By the time I ran my own MUD and found out about it,
there were two established networks, I3 for the LPMUD people,
and IMC2 for the DikuMUD people.

Fast forward a bit further, and IMC2 collapsed, with a small
number of the DikuMUDs managing to join I3.  As of this
writing, 2020-01-16, there are about 150 MUDs using the I3
network, with about 100 actually connected at any given time.

Since I3 evolved on the LPMUD platform, the routers responsible
for keeping everyone connected and passing traffic around are
written in LPC, and have to run inside a MUD driver, which
itself is written in C.  The code for the driver has remained
mostly untouched for the last 15 years, and the LPC code that
implements I3 has also been patched but never really reworked
for almost as long.

That's where this project comes in.  Since I3 really has
nothing to do with MUDs, other than being a message service
that they use, it makes sense to write a stand-alone router
that doesn't depend on a game driver.

I've chosen to do this in perl, for the simple reason that
I already know perl and it's very easy to work with text in
this language.  Any dynamic language would be a good choice,
but I had to pick one.

=cut

=head1 DEPENDENCIES

This router is written in perl 5.x, and requires a number of
CPAN modules to function.

    Config::Tiny
    DBD::Pg (indirectly by DBI)
    DBI
    File::Basename
    Getopt::Long
    Log::Log4perl
    Pod::Find
    Pod::Usage
    Time::HiRes
    Try::Tiny

In addition, the B<curl> binary is required, as this is used
to perform a quick and simple lookup of your external IPv4
address.  Yes, we could rewrite it to use LWP instead, but
so far that's the only place it's used.

=cut

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
#use POSIX ":sys_wait_h";
#use IPC::Shareable;
use Try::Tiny;
use DBI;
use Log::Log4perl;
use PI3::Config;

my $Config = PI3::Config->new();

Log::Log4perl::init($Config->log_config());
my $log_main = Log::Log4perl->get_logger('MAIN');
my $log_boot = Log::Log4perl->get_logger('BOOT');
$log_boot->info("Logging system intialized.");

use PI3::DB; # This needs to be AFTER the logging system is configured!
my $Database = PI3::DB->new($Config);

#$Database->register();
$log_main->info(sprintf "I3 router name is *%s, address %s, port %d.",
    $Config->router_name(), $Config->router_address(), $Config->router_port());
sleep 10;
#$Database->unregister();
$log_boot->info("Logging system shutdown.");

