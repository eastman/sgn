use Modern::Perl;
use Test::More tests => 2;

use aliased 'CXGN::Transcript::DrawContigAlign::DepthData';

my $depth = DepthData->new(2, 3);
is($depth->position, 2, "DepthData position");
$depth->depth($depth->depth + 1);
$depth->increment;
is($depth->depth, 5, "DepthData depth");
