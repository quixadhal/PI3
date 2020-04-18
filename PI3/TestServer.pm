#!/usr/bin/perl -w

package PI3::TestServer;

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
use IPC::Shareable;
use Try::Tiny;
use Log::Log4perl;

use Exporter qw(import);
our @EXPORT_OK = qw( server_main );
our @EXPORT = qw();
our %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);

my $log_main = Log::Log4perl->get_logger('MAIN');
my $log_boot = Log::Log4perl->get_logger('BOOT');
my $log_auth = Log::Log4perl->get_logger('AUTH');

sub server_main {
    $| = 1;
    $SIG{CHLD} = "IGNORE";

    my $start_time = time();
    my $done = undef;
    my $shared_name = 'testing';
    my $share_options = {
        create      => 1,
        exclusive   => 0,
        mode        => 0666,
        destroy     => 1,
    };

    $log_boot->info("Server Started.");

    my %data = ();
    my $shared = tie %data, 'IPC::Shareable', $shared_name, $share_options
        or die "Cannot tie data: $!";

    $log_boot->info("Shared memory structure created.");

    sleep 10;

    $log_main->info("Installing flavor...");
    try {
        local $SIG{ALRM} = sub { die "TIMEOUT"; };
        alarm 10;
        sleep 0.1 until $shared->shlock;
        $data{flavor} = "cherry";
        $shared->shunlock;
        alarm 0;
        $log_main->info("Flavor installed.");
    } catch {
        $log_main->fatal("FAILED to install flavor!");
    };

    sleep 10;

    $log_boot->info("Server Halted.");
    exit 1;
}

1;
