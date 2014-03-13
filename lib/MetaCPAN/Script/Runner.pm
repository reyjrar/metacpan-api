package MetaCPAN::Script::Runner;

use strict;
use warnings;

use Config::JFDI;
use FindBin;
use Hash::Merge::Simple qw(merge);
use IO::Interactive qw(is_interactive);
use Module::Pluggable search_path => ['MetaCPAN::Script'];
use Module::Runtime ();
use Path::Tiny;

# plugins is exported by Module::Pluggable

sub run {
    my ( $class, @actions ) = @ARGV;
    my %plugins
        = map { ( my $key = $_ ) =~ s/^MetaCPAN::Script:://; lc($key) => $_ }
        plugins();
    die 'Usage: metacpan [command] [args]' unless ($class);
    Module::Runtime::require_module( $plugins{$class} );

    my $config = build_config();
    my $obj    = $plugins{$class}->new_with_options($config);
    $obj->run;
}

sub build_config {
    my $path = _build_base_path()->child('etc');

    my $config = Config::JFDI->new(
        name => 'metacpan',
        path => $path,
    )->get;

    if ( $ENV{HARNESS_ACTIVE} ) {
        my $tconf = Config::JFDI->new(
            name => 'metacpan',
            file => $path->child('metacpan_testing.pl'),
        )->get;
        return merge( $config, $tconf );
    }

    if ( is_interactive() ) {
        my $iconf = Config::JFDI->new(
            name => 'metacpan',
            file => $path->child('metacpan_interactive.pl'),
        )->get;
        return merge( $config, $iconf );
    }

    return $config;
}

sub _build_base_path {
    return $ENV{HARNESS_ACTIVE}
        ? Path::Tiny->cwd
        : Path::Tiny->new($FindBin::RealBin)->parent;
}

# AnyEvent::Run calls the main method
*main = \&run;

1;
