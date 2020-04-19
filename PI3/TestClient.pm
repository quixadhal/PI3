#!/usr/bin/perl -w

package PI3::TestClient;

use strict;
use warnings;
use English -no_match_vars;
use Data::Dumper;

BEGIN { @INC = ( ".", @INC ); }

use Time::HiRes qw(time sleep alarm);
use IPC::Shareable;
use Try::Tiny;
use DBI;
use Log::Log4perl;

use Exporter qw(import);
our @EXPORT_OK = qw( client_main );
our @EXPORT = qw();
our %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);

my $log_main = Log::Log4perl->get_logger('MAIN');
my $log_boot = Log::Log4perl->get_logger('BOOT');
my $log_auth = Log::Log4perl->get_logger('AUTH');

sub client_main {
    $| = 1;
    $SIG{CHLD} = "IGNORE";

    my $start_time = time();
    my $done = undef;
    my $shared_name = 'fart';
    my $share_options = {
        create      => 0,
        exclusive   => 0,
        mode        => 0666,
        destroy     => 0,
    };

    $log_boot->info("Client Started.");

    my %data = ();
    my $shared = undef;

    try {
        $shared = tie %data, 'IPC::Shareable', $shared_name, $share_options;
        $log_main->info("Shared memory structure $shared_name connected.");
    } catch {
        $log_main->fatal("Failed to connect to shared memory structure $shared_name\n$_");
        $log_boot->logdie("Client Halted.");
        exit 1;
    };

    $log_main->info("Client $$ PID is ".(defined $data{client_pid}) ? $data{client_pid} : "undefined");

    $log_main->info("Flavor is ".(defined $data{flavor} ? $data{flavor} : "undefined"));
    sleep 15;
    $log_main->info("Flavor is ".(defined $data{flavor} ? $data{flavor} : "undefined"));

    $log_boot->info("Client Halted.");
    exit 1;
}

1;
