use strict;
use warnings;

use MetaCPAN::Script::Runner;
use Test::Most;

my $config = MetaCPAN::Script::Runner->build_config;

ok( $config, 'builds config' );

is_deeply(
    $config,
    {   cpan   => 't/var/tmp/fakecpan',
        es     => ':9900',
        level  => 'info',
        logger => [
            { class => 'Log::Log4perl::Appender::Screen', name => 'testing' }
        ],
        port        => 5900,
        source_base => 't/var/tmp/source'
    },
    'test config returned'
);

{
    local $ENV{MINICPAN} = $config->{cpan};
    local @ARGV = ('latest');
    ok( MetaCPAN::Script::Runner->run('Release'), 'can run release script' );
}

done_testing();
