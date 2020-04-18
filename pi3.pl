#!/usr/bin/perl -w

package main;

=head1 NAME

pi3 - An Intermud-3 router, implemented in perl.

=head1 SYNOPSYS

Please see L<PI3::Options> for usage details.

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

=head1 NOTICE

It should be noted that this is just a chunk of test code
to start working on the basic ideas.  It will change when
we figure out all the tools we'll end up using.

=cut

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
use POSIX ":sys_wait_h";
use IPC::Shareable;
use Try::Tiny;
use Log::Log4perl;

my $LOG_CONFIG = "./log4perl.conf";

if( ! -r $LOG_CONFIG ) {
    open(my $fp, ">", $LOG_CONFIG) or die "Cannot create $LOG_CONFIG: $!";
    print $fp <<~EOM;
        log4perl.logger.MAIN = DEBUG, A1
        log4perl.logger.BOOT = DEBUG, A1
        log4perl.logger.AUTH = DEBUG, A1

        log4perl.appender.A1 = Log::Log4perl::Appender::Screen
        log4perl.appender.A1.stderr = 0
        log4perl.appender.A1.layout = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.A1.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss.SSS} %8P %-6c %-6p %16C %05L| %m{indent,chomp}%n
    EOM
    close $fp;
}

Log::Log4perl::init($LOG_CONFIG);

my $log_main = Log::Log4perl->get_logger('MAIN');
my $log_boot = Log::Log4perl->get_logger('BOOT');
my $log_auth = Log::Log4perl->get_logger('AUTH');

use PI3::TestServer qw(server_main);
use PI3::TestClient qw(client_main);

my $server_kid = undef;
my $client_kid = undef;
$| = 1;
$SIG{CHLD} = "IGNORE";
$log_boot->info("Main process launching children.");

$log_main->logdie("Failed to fork: $!") unless defined ($server_kid = fork());
server_main() if $server_kid == 0;
$log_main->info("Child $server_kid launched as server.");

$log_main->logdie("Failed to fork: $!") unless defined ($client_kid = fork());
client_main() if $client_kid == 0;
$log_main->info("Child $client_kid launched as client.");

$log_main->info("This is a test of\nmulti-line messages, to see if\nit aligns properly.");
$log_auth->warn("Security breach!");

# Wait until both kids are done
while((my $death = waitpid(-1, WNOHANG)) > -1) {
    # Note that if you are IGNORing SIGCHLD, you never get a > 0 response.
    $log_main->info("Child $death has exited.") if $death > 0;
    sleep 0.5;
}
$log_boot->info("Main process done.");

1;
