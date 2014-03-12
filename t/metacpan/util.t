use strict;
use warnings;

use MetaCPAN::Util;
use Test::Most;

use MetaCPAN::Util;

is( MetaCPAN::Util::author_dir('OALDERS'), 'id/O/OA/OALDERS', 'author_dir' );
is( MetaCPAN::Util::digest( 'foo', 'bar' ),
    '4sMAo5MRot_K_3mVKEFct0wZMX8', 'digest' );
is( MetaCPAN::Util::numify_version('0.1.1'),  0.001001,    'numify_version' );
is( MetaCPAN::Util::fix_version('1_234_567'), 10023400567, 'fix_version' );
is( MetaCPAN::Util::strip_pod('L<foobar> baz'), 'foobar baz', 'strip_pod' );

my $pod = <<'EOF';
=head1 NAME

Foo::Bar

=cut

my $foo = 'bar';

=head1 SYNOPSIS

Blah

=cut
EOF

is( MetaCPAN::Util::extract_section( $pod, 'NAME' ),
    'Foo::Bar', 'extract_section' );
my ( $ranges, $slop ) = MetaCPAN::Util::pod_lines($pod);
is_deeply( $ranges, [ [ 0, 5 ], [ 8, 5 ] ], 'pod_lines ranges' );
is( $slop, 6, 'pod_lines slop' );

done_testing();
