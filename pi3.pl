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

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

use Time::HiRes qw(time sleep alarm);

BEGIN { @INC = ( ".", @INC ); }

use PI3::Log qw(:all);  # auto-import $log_main

my $start_time = time();
my $done = undef;

#my $log_object = PI3::Log->new(undef, {weakref => 1});
#my $log_main = $log_object->{logger};
#my $bar_object = PI3::Log->new('bar', {weakref => 1});
#my $bar = PI3::Log->new('bar')->{logger};

my $log_main = PI3::Log->new()->{logger};
my $bar = PI3::Log->new('bar')->{logger};

$log_main->boot("System Started.");
$log_main->info("This is a test of\nmulti-line messages, to see if\nit aligns properly.");
$log_main->info("There are currently " . PI3::Log::count() . " log instances.");
$bar->boot("A different logger.");
$bar->auth("Security breach!");
$log_main->boot("System Halted.");

1;

